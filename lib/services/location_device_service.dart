import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class LocationDeviceService {
  static Future<void> printDeviceIdAndLocation() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = '';
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = info.identifierForVendor ?? '';
      }
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

  /// Requests location permission and fetches current GPS coordinates.
  /// Returns [LocationData] with lat/lng, or throws a descriptive error.
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

    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  /// Generates a stable device hash from hardware identifiers.
  /// Uses SHA-256 of combined device info fields.
  static Future<String> getDeviceHash() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String rawId = '';

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        // Combine stable hardware identifiers
        rawId = [
          info.id,               // Android ID (unique per device+user)
          info.brand,
          info.model,
          info.hardware,
          info.fingerprint,
        ].join('|');
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        // identifierForVendor is stable per app install on same device
        rawId = [
          info.identifierForVendor ?? '',
          info.model,
          info.name,
          info.systemVersion,
        ].join('|');
      }

      if (rawId.isEmpty) rawId = 'unknown_device';

      // SHA-256 hash of the combined string
      final digest = sha256.convert(utf8.encode(rawId));
      return digest.toString(); // 64-char hex string
    } catch (e) {
      // Fallback — return a hash of the platform string
      final fallback = sha256.convert(utf8.encode(Platform.operatingSystem));
      return fallback.toString();
    }
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
