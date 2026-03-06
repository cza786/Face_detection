import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyEmployeeData = 'employee_data';

  /// Saves the authenticated user session
  static Future<void> saveEmployeeData(Map<String, dynamic> data) async {
    try {
      final jsonString = jsonEncode(data);
      await _storage.write(key: _keyEmployeeData, value: jsonString);
      debugPrint('[SecureStorageService] Session data saved securely.');
    } catch (e) {
      debugPrint('[SecureStorageService] Error saving data: $e');
    }
  }

  /// Retrieves the saved user session
  static Future<Map<String, dynamic>?> getEmployeeData() async {
    try {
      final jsonString = await _storage.read(key: _keyEmployeeData);
      if (jsonString != null && jsonString.isNotEmpty) {
        debugPrint('[SecureStorageService] Existing session found.');
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[SecureStorageService] Error reading data: $e');
    }
    debugPrint('[SecureStorageService] No saved session found.');
    return null;
  }

  /// Clears the session logic (Logout)
  static Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      debugPrint('[SecureStorageService] All data cleared (Logged out).');
    } catch (e) {
      debugPrint('[SecureStorageService] Error clearing data: $e');
    }
  }
}
