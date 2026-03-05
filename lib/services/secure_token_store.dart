import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles automatic token fetching and refresh.
/// Token expires every 30 min — we refresh at 29 min to stay safe.
class TokenService {
  // ── Base URL (same API) ────────────────────────────────────────────────
  static const String _tokenUrl =
      'https://myb-v4.smartworker.app/secure_api/auth_verification';

  // ── Token lifetime: 30 min → refresh at 29 min ────────────────────────
  static const Duration _tokenLifetime = Duration(minutes: 29);

  // ── In-memory token store ──────────────────────────────────────────────
  static String? _currentToken;
  static DateTime? _tokenFetchedAt;

  // ── Lock to prevent multiple simultaneous fetches ─────────────────────
  static bool _isFetching = false;
  static Future<String?>? _ongoingFetch;

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: getValidToken
  // Call this before every API request.
  // Returns a valid token — fetches/refreshes automatically if needed.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> getValidToken() async {
    // Token exist karta hai aur abhi valid hai
    if (_currentToken != null && !_isExpired()) {
      debugLog('Token valid — using cached (age: ${_tokenAge()}min)');
      return _currentToken;
    }

    // Agar already fetch chal rahi hai toh wait karo same future pe
    if (_isFetching && _ongoingFetch != null) {
      debugLog('Token fetch already in progress — waiting...');
      return await _ongoingFetch;
    }

    // Naya token fetch karo
    _isFetching = true;
    _ongoingFetch = _fetchToken();
    final token = await _ongoingFetch;
    _isFetching = false;
    _ongoingFetch = null;
    return token;
  }

  /// Force refresh — call when API returns 401
  static Future<String?> forceRefresh() async {
    debugLog('Force refresh triggered (got 401)');
    _currentToken = null;
    _tokenFetchedAt = null;
    return await getValidToken();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: actual token fetch from API
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> _fetchToken() async {
    debugLog('Fetching new token from API...');
    try {
      // Aapki API se token lene ki request
      // Same endpoint — sirf token request (no face_roi)
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'request_type': 'get_token', // server ko batao sirf token chahiye
        }),
      ).timeout(const Duration(seconds: 15));

      debugLog('Token fetch status: ${response.statusCode}');
      debugLog('Token fetch response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = _extractToken(data);
        if (token != null && token.isNotEmpty) {
          _currentToken = token;
          _tokenFetchedAt = DateTime.now();
          debugLog('New token saved. Expires in 30min.');
          return token;
        }
      }

      // Agar API se token nahi mila — fallback to last known token
      if (_currentToken != null) {
        debugLog('Token fetch failed — using expired token as fallback');
        return _currentToken;
      }

      debugLog('Token fetch failed — no fallback available');
      return null;
    } catch (e) {
      debugLog('Token fetch error: $e');
      // Network error pe purana token try karo
      return _currentToken;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Token response se token extract karo
  // Multiple response formats handle karta hai
  // ─────────────────────────────────────────────────────────────────────────
  static String? _extractToken(Map<String, dynamic> data) {
    // Format 1: { "token": "xxx" }
    if (data['token'] is String) return data['token'] as String;

    // Format 2: { "access_token": "xxx" }
    if (data['access_token'] is String) return data['access_token'] as String;

    // Format 3: { "data": { "token": "xxx" } }
    if (data['data'] is Map) {
      final inner = data['data'] as Map;
      if (inner['token'] is String) return inner['token'] as String;
      if (inner['access_token'] is String) return inner['access_token'] as String;
    }

    // Format 4: { "auth": { "token": "xxx" } }
    if (data['auth'] is Map) {
      final inner = data['auth'] as Map;
      if (inner['token'] is String) return inner['token'] as String;
    }

    // Format 5: { "bearer_token": "xxx" }
    if (data['bearer_token'] is String) return data['bearer_token'] as String;

    debugLog('Could not extract token from response: $data');
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static bool _isExpired() {
    if (_tokenFetchedAt == null) return true;
    final age = DateTime.now().difference(_tokenFetchedAt!);
    return age >= _tokenLifetime; // 29 min ke baad expired consider karo
  }

  static int _tokenAge() {
    if (_tokenFetchedAt == null) return 0;
    return DateTime.now().difference(_tokenFetchedAt!).inMinutes;
  }

  /// App start pe call karo — token pehle se ready rakho
  static Future<void> initialize() async {
    debugLog('TokenService initializing...');
    await getValidToken();
  }

  /// Bahar se token save karne ke liye (jab API response mein naya token aaye)
  static void saveToken(String token) {
    _currentToken = token;
    _tokenFetchedAt = DateTime.now();
    debugLog("Token manually saved from API response.");
  }

  static void debugLog(String msg) {
    // ignore: avoid_print
    print('[TokenService] $msg');
  }
}