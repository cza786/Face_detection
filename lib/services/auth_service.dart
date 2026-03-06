import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

// ─── Auth Verification Service ────────────────────────────────────────────────
//
// Endpoint: POST https://myb-v4.smartworker.app/secure_api/auth_verification
//
// Sends a multipart/form-data request with:
//   face_roi    → "data:image/jpeg;base64,<base64>"
//   latitude    → GPS latitude as string
//   longitude   → GPS longitude as string
//   device_hash → MD5 hex of device ID (32 chars, lowercase)
//
// On success the server returns:
//   { "success": true, "data": { "session_token": { "token": "..." } } }
// ─────────────────────────────────────────────────────────────────────────────

const String _kApiUrl =
    'https://myb-v4.smartworker.app/secure_api/auth_verification';

class AuthVerificationService {
  // ───────────────────────────────────────────────────────────────────────────
  // Public: verifyFace
  // ───────────────────────────────────────────────────────────────────────────
  /// Sends the face ROI, location, and device hash to the backend API.
  ///
  /// [faceImageBytes] — raw JPEG bytes of the cropped face (from FaceCropService)
  /// [latitude]       — GPS latitude (double)
  /// [longitude]      — GPS longitude (double)
  /// [deviceHash]     — 32-char MD5 hex of the device ID
  static Future<VerificationResult> verifyFace({
    required Uint8List faceImageBytes,
    required double latitude,
    required double longitude,
    required String deviceHash,
  }) async {
    try {
      // ── 1. Build Base64 face_roi with prefix ────────────────────────────
      final rawBase64 = base64Encode(faceImageBytes);
      final faceRoi = 'data:image/jpeg;base64,$rawBase64';

      // ── 2. Debug payload values ─────────────────────────────────────────
      debugPrint('=== Auth Verification Payload ===');
      debugPrint('Face Base64 length: ${faceRoi.length}');
      debugPrint('Latitude: $latitude');
      debugPrint('Longitude: $longitude');
      debugPrint('Device Hash (MD5): $deviceHash');
      debugPrint('=================================');

      // ── 3. Build multipart request ──────────────────────────────────────
      final uri = Uri.parse(_kApiUrl);
      final request = http.MultipartRequest('POST', uri);

      request.fields['face_roi'] = faceRoi;
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      request.fields['device_hash'] = deviceHash;

      debugPrint('[AuthService] Sending multipart POST to $_kApiUrl');

      // ── 4. Send request ─────────────────────────────────────────────────
      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw Exception('Request timed out after 30 seconds'),
          );
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[AuthService] Response status: ${response.statusCode}');
      debugPrint('[AuthService] Response body: ${response.body}');

      // ── 5. Parse response ───────────────────────────────────────────────
      if (response.statusCode == 200 || response.statusCode == 201) {
        return _parseSuccessResponse(response.body);
      } else {
        return _parseErrorResponse(response.statusCode, response.body);
      }
    } on Exception catch (e) {
      debugPrint('[AuthService] Network/unexpected error: $e');
      return VerificationResult.error(
          'Network error: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  static VerificationResult _parseSuccessResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final success = json['success'];

      if (success == true) {
        // ── Extract all fields from "data" ──────────────────────────────
        final data = json['data'] as Map<String, dynamic>? ?? {};
        final sessionTokenObj =
            data['session_token'] as Map<String, dynamic>? ?? {};

        final token = sessionTokenObj['token'] as String?;
        final tokenType = sessionTokenObj['token_type'] as String? ?? 'Bearer';
        final expiresIn = sessionTokenObj['expires_in'];
        final name = data['name'] as String? ?? 'Employee';
        final serialNum = data['serial_number'] as String? ?? '';

        // ── Debug logs ──────────────────────────────────────────────────
        debugPrint('');
        debugPrint('==========  AUTH SUCCESS  ==========');
        debugPrint('Name          : $name');
        debugPrint('Serial Number : $serialNum');
        debugPrint('Token Type    : $tokenType');
        debugPrint('Expires In    : $expiresIn s');
        debugPrint('Session Token : $token');
        debugPrint('====================================');
        debugPrint('');

        // Flatten so HomeScreen can read keys directly
        return VerificationResult.authenticated(
          token: token,
          employeeData: {
            'name': name,
            'serial_number': serialNum,
            'token': token ?? '',
            'token_type': tokenType,
            'expires_in': expiresIn,
          },
        );
      } else {
        // success == false
        final message = json['message'] as String? ??
            json['error'] as String? ??
            'Authentication failed';
        debugPrint('[AuthService] \u274c Auth failed: $message');
        return VerificationResult.failed(message);
      }
    } catch (e) {
      debugPrint('[AuthService] JSON parse error: $e');
      return VerificationResult.error('Unexpected server response format.');
    }
  }

  static VerificationResult _parseErrorResponse(int statusCode, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final message = json['message'] as String? ??
          json['error'] as String? ??
          'Server error ($statusCode)';
      debugPrint('[AuthService] ❌ HTTP $statusCode — $message');

      // Treat 4xx as authentication failures, 5xx as server errors
      if (statusCode >= 500) {
        return VerificationResult.error('Server error ($statusCode): $message');
      }
      return VerificationResult.failed(message);
    } catch (_) {
      return VerificationResult.error(
          'Server returned status $statusCode. Please try again.');
    }
  }
}

// ─── Result Models ────────────────────────────────────────────────────────────

enum VerificationStatus { authenticated, notAuthenticated, error }

class VerificationResult {
  final VerificationStatus status;
  final Map<String, dynamic>? employeeData;
  final String? message;
  final String? token;

  const VerificationResult._({
    required this.status,
    this.employeeData,
    this.message,
    this.token,
  });

  factory VerificationResult.authenticated({
    required Map<String, dynamic> employeeData,
    String? token,
  }) =>
      VerificationResult._(
        status: VerificationStatus.authenticated,
        employeeData: employeeData,
        token: token,
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
