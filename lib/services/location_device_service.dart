import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

// ─── LocationDeviceService ────────────────────────────────────────────────────
//
// Provides:
//   • getCurrentLocation()  → lat/lng as LocationData
//   • getDeviceId()         → raw platform device identifier string
//   • getDeviceHash()       → MD5 hex of device ID (32 chars, lowercase)
//   • printDeviceIdAndLocation() → debug helper
//
// The device hash uses MD5 (not SHA-256) to match the 32-character hex format
// required by the backend API.
// ─────────────────────────────────────────────────────────────────────────────

class LocationDeviceService {
  // ──────────────────────────────────────────────────────────────────────────
  // Debug helper — prints device ID and GPS coordinates to the console.
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> printDeviceIdAndLocation() async {
    try {
      final deviceId = await getDeviceId();
      debugPrint('Device ID: $deviceId');

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location service disabled');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      debugPrint('Latitude: ${pos.latitude}');
      debugPrint('Longitude: ${pos.longitude}');
    } catch (e) {
      debugPrint('Device/location debug error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Returns the raw device identifier string.
  //   Android → android.id  (SSAID, stable per device + user)
  //   iOS     → identifierForVendor
  // ──────────────────────────────────────────────────────────────────────────
  static Future<String> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.id; // Android ID (SSAID)
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.identifierForVendor ?? 'unknown_ios_device';
      }
      return 'unknown_platform';
    } catch (e) {
      debugPrint('[LocationDeviceService] getDeviceId error: $e');
      return 'fallback_device';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Returns a 32-character lowercase MD5 hex hash of the device ID.
  //
  // The backend expects exactly this format:
  //   e.g.  "f72dd67768dbf566a5deee0eb5f9b16d"
  // ──────────────────────────────────────────────────────────────────────────
  static Future<String> getDeviceHash() async {
    try {
      final deviceId = await getDeviceId();
      debugPrint('[LocationDeviceService] Raw Device ID: $deviceId');

      // MD5 produces a 128-bit digest → 32 lowercase hex characters
      final digest = md5.convert(utf8.encode(deviceId));
      final hash = digest.toString(); // always 32 chars, lowercase hex

      debugPrint('[LocationDeviceService] Device Hash (MD5): $hash');
      assert(hash.length == 32, 'MD5 hash must be exactly 32 characters');

      return hash;
    } catch (e) {
      debugPrint('[LocationDeviceService] getDeviceHash error: $e');
      // Fallback: MD5 of the platform name
      final fallback = md5.convert(utf8.encode(Platform.operatingSystem));
      return fallback.toString();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Requests location permission and fetches current GPS coordinates.
  // Throws a [LocationException] with a descriptive message on failure.
  // ──────────────────────────────────────────────────────────────────────────
  static Future<LocationData> getCurrentLocation() async {
    // Check if location services are enabled on the device
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
          'Location services are disabled. Please enable GPS.');
    }

    // Request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException(
            'Location permission denied. Please allow location access.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
          'Location permission permanently denied. Enable it in Settings.');
    }

    // Get position with high accuracy
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );

    debugPrint('[LocationDeviceService] Latitude:  ${position.latitude}');
    debugPrint('[LocationDeviceService] Longitude: ${position.longitude}');

    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class LocationData {
  final double latitude;
  final double longitude;
  const LocationData({required this.latitude, required this.longitude});
}

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => message;
}
