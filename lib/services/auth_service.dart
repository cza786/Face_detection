import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

// ─── Auth Verification Service ───────────────────────────────────────────────
// Endpoint: POST https://myb-v4.smartworker.app/secure_api/auth_verification
//
// This service ONLY handles HTTP.  Face cropping / preparation is done
// upstream by FaceCropService before calling verifyFace().
//
// Payload:
//   face_roi    → base64-encoded JPEG of the pre-cropped face
//   latitude    → double
//   longitude   → double
//   device_hash → string
// ─────────────────────────────────────────────────────────────────────────────

class AuthVerificationService {
  static const String _endpoint =
      'https://myb-v4.smartworker.app/secure_api/auth_verification';

  static const Duration _httpTimeout = Duration(seconds: 60);

  // ─────────────────────────────────────────────────────────────────────────
  // Public: verifyFace
  //
  // [faceImageBytes] — pre-cropped, pre-resized JPEG bytes from FaceCropService
  // [latitude]       — GPS latitude
  // [longitude]      — GPS longitude
  // [deviceHash]     — SHA-256 device fingerprint
  // ─────────────────────────────────────────────────────────────────────────
  static Future<VerificationResult> verifyFace({
    required Uint8List faceImageBytes,
    required double latitude,
    required double longitude,
    required String deviceHash,
  }) async {
    try {
      // Encode face to base64
      final faceRoi = base64Encode(faceImageBytes);

      _log('Payload → '
          'face_roi: ${(faceImageBytes.length / 1024).toStringAsFixed(1)} KB  '
          '(base64: ${(faceRoi.length / 1024).toStringAsFixed(1)} KB)  |  '
          'lat=$latitude  lng=$longitude  '
          'device=${deviceHash.substring(0, 8)}…');

      final payload = <String, dynamic>{
        'face_roi': faceRoi,
        'latitude': latitude,
        'longitude': longitude,
        'device_hash': deviceHash,
      };

      return await _post(payload);
    } on SocketException catch (e) {
      _log('SocketException: $e');
      return VerificationResult.error(
          'No internet connection. Check your network and try again.');
    } on TimeoutException {
      _log('TimeoutException — server did not respond within 60 s');
      return VerificationResult.error('Server is taking too long to respond.\n'
          'Check your connection and try again.');
    } on http.ClientException catch (e) {
      _log('ClientException: $e');
      return VerificationResult.error('Connection failed: ${e.message}');
    } catch (e) {
      _log('Unexpected error in verifyFace: $e');
      return VerificationResult.error('Unexpected error. Please try again.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal: HTTP POST
  // ─────────────────────────────────────────────────────────────────────────
  static Future<VerificationResult> _post(Map<String, dynamic> payload) async {
    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_httpTimeout);

    _log('HTTP ${response.statusCode}');
    final preview = response.body.length > 400
        ? '${response.body.substring(0, 400)}…'
        : response.body;
    _log('Response: $preview');

    switch (response.statusCode) {
      case 200:
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return _parseSuccess(data);
        } catch (_) {
          return VerificationResult.failed(
              'Server returned OK but with an unreadable response.');
        }

      case 400:
        return _failFromBody(response.body, 'Bad request (400). Try again.');

      case 401:
        return VerificationResult.failed(
            'Unauthorized. Contact your administrator.');

      case 403:
        return VerificationResult.failed(
            'Access denied. Face not recognized in the system.');

      case 404:
        return VerificationResult.failed(
            'Face not registered. Please enroll first.');

      case 422:
        return _failFromBody(
            response.body, 'Invalid image (422). Please scan again.');

      case 500:
      case 502:
      case 503:
        return VerificationResult.error(
            'Server error (${response.statusCode}). Please try again later.');

      default:
        return _failFromBody(response.body,
            'Unexpected server response (${response.statusCode}).');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parse 200 OK — handles multiple server response formats robustly
  // ─────────────────────────────────────────────────────────────────────────
  static VerificationResult _parseSuccess(Map<String, dynamic> data) {
    // { "authenticated": true }
    if (data.containsKey('authenticated')) {
      final v = data['authenticated'];
      return (v == true || v == 1 || v == 'true')
          ? VerificationResult.authenticated(
              employeeData: _extractEmployee(data))
          : VerificationResult.failed(_extractMessage(data) ??
              'Face does not match any registered employee.');
    }

    // { "status": "success" / "matched" / "found" / "ok" }
    if (data.containsKey('status')) {
      final s = data['status'].toString().toLowerCase();
      return (s == 'success' || s == 'matched' || s == 'found' || s == 'ok')
          ? VerificationResult.authenticated(
              employeeData: _extractEmployee(data))
          : VerificationResult.failed(
              _extractMessage(data) ?? 'Face not recognized.');
    }

    // { "match": true }
    if (data.containsKey('match')) {
      final v = data['match'];
      return (v == true || v == 1 || v == 'true')
          ? VerificationResult.authenticated(
              employeeData: _extractEmployee(data))
          : VerificationResult.failed(_extractMessage(data) ??
              'Face does not match any registered employee.');
    }

    // { "verified": true }
    if (data.containsKey('verified')) {
      final v = data['verified'];
      return (v == true || v == 1 || v == 'true')
          ? VerificationResult.authenticated(
              employeeData: _extractEmployee(data))
          : VerificationResult.failed(
              _extractMessage(data) ?? 'Verification failed.');
    }

    // { "success": true }
    if (data.containsKey('success')) {
      final v = data['success'];
      return (v == true || v == 1 || v == 'true')
          ? VerificationResult.authenticated(
              employeeData: _extractEmployee(data))
          : VerificationResult.failed(
              _extractMessage(data) ?? 'Face not recognized.');
    }

    // { "error": "..." }
    if (data.containsKey('error')) {
      return VerificationResult.failed(data['error'].toString());
    }

    _log('WARNING: Unrecognised response format: $data');
    return VerificationResult.failed(
        'Unrecognized server response. Contact your administrator.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  static VerificationResult _failFromBody(String body, String fallback) {
    try {
      final err = jsonDecode(body) as Map<String, dynamic>;
      final msg = err['message'] ?? err['error'] ?? err['detail'];
      return VerificationResult.failed(msg?.toString() ?? fallback);
    } catch (_) {
      return VerificationResult.failed(fallback);
    }
  }

  static Map<String, dynamic> _extractEmployee(Map<String, dynamic> data) {
    for (final key in ['employee', 'user', 'staff', 'member']) {
      if (data[key] is Map) {
        return Map<String, dynamic>.from(data[key] as Map);
      }
    }
    if (data['data'] is Map) {
      final inner = data['data'] as Map;
      for (final key in ['employee', 'user', 'staff']) {
        if (inner[key] is Map) {
          return Map<String, dynamic>.from(inner[key] as Map);
        }
      }
      return Map<String, dynamic>.from(inner);
    }
    final flat = <String, dynamic>{};
    for (final k in [
      'id',
      'name',
      'email',
      'department',
      'position',
      'role',
      'phone'
    ]) {
      if (data.containsKey(k)) flat[k] = data[k];
    }
    return flat.isNotEmpty ? flat : {'name': 'Verified Employee'};
  }

  static String? _extractMessage(Map<String, dynamic> data) {
    for (final k in ['message', 'msg', 'detail', 'reason', 'description']) {
      if (data[k] is String && (data[k] as String).isNotEmpty) {
        return data[k] as String;
      }
    }
    return null;
  }

  static void _log(String msg) => debugPrint('[AuthService] $msg');
}

// ─── Result Models ────────────────────────────────────────────────────────────

enum VerificationStatus { authenticated, notAuthenticated, error }

class VerificationResult {
  final VerificationStatus status;
  final Map<String, dynamic>? employeeData;
  final String? message;

  const VerificationResult._({
    required this.status,
    this.employeeData,
    this.message,
  });

  factory VerificationResult.authenticated(
          {required Map<String, dynamic> employeeData}) =>
      VerificationResult._(
        status: VerificationStatus.authenticated,
        employeeData: employeeData,
      );

  factory VerificationResult.failed(String message) => VerificationResult._(
        status: VerificationStatus.notAuthenticated,
        message: message,
      );

  factory VerificationResult.error(String message) => VerificationResult._(
        status: VerificationStatus.error,
        message: message,
      );

  bool get isAuthenticated => status == VerificationStatus.authenticated;
  bool get isError => status == VerificationStatus.error;
}
