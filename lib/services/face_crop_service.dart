import 'dart:typed_data';
import 'dart:ui' show Rect, Size;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

// ─── FaceCropService ──────────────────────────────────────────────────────────
//
// Responsible for one thing: given a full captured JPEG and the ML Kit
// bounding box, produce a correctly-cropped, rotated, resized face JPEG.
//
// Pipeline:
//   1. Decode JPEG
//   2. Apply EXIF / sensor rotation so the image is upright
//   3. Mirror horizontally if front camera was used
//      (captured image is NOT mirrored even though preview is)
//   4. Scale MLKit bounding box (which is in *stream* pixel space) to the
//      decoded image's pixel space
//   5. Add padding (20 % horizontal, 25 % vertical)
//   6. Clamp to image bounds
//   7. Validate minimum crop size (≥ 60 × 60 px after scaling)
//   8. Crop  →  resize (max 320 px on longest side)  →  JPEG @ 82 %
//
// ─────────────────────────────────────────────────────────────────────────────

class FaceCropResult {
  final Uint8List? croppedBytes; // null = failed
  final String? error;
  final bool success;

  const FaceCropResult._({
    required this.success,
    this.croppedBytes,
    this.error,
  });

  factory FaceCropResult.ok(Uint8List bytes) =>
      FaceCropResult._(success: true, croppedBytes: bytes);

  factory FaceCropResult.fail(String reason) =>
      FaceCropResult._(success: false, error: reason);
}

class FaceCropService {
  // ── Tunable constants ──────────────────────────────────────────────────────
  static const double _padX = 0.20; // 20 % horizontal padding
  static const double _padY = 0.25; // 25 % vertical padding
  static const int _maxPx = 320; // longest side after resize
  static const int _jpegQ = 82; // JPEG quality
  static const int _minCropPx = 60; // min crop size (scaled) before resize

  // ── Public entry point ─────────────────────────────────────────────────────
  /// [imageBytes]      — raw JPEG from takePicture()
  /// [faceBoundingBox] — bounding box in *camera stream* pixel space
  ///                     as reported by ML Kit
  /// [streamImageSize] — size of the camera stream frame ML Kit processed
  ///                     (image.width × image.height from CameraImage)
  /// [sensorOrientation] — _cameraController.description.sensorOrientation
  /// [isFrontCamera]   — true when lens direction is front
  static FaceCropResult crop({
    required Uint8List imageBytes,
    required Rect? faceBoundingBox,
    required Size streamImageSize,
    required int sensorOrientation,
    required bool isFrontCamera,
  }) {
    // ── 1. Decode ────────────────────────────────────────────────────────────
    final original = img.decodeImage(imageBytes);
    if (original == null) {
      return FaceCropResult.fail('Could not decode captured image.');
    }

    debugPrint('[FaceCrop] Raw image: ${original.width}×${original.height}px');
    debugPrint('[FaceCrop] Stream size: '
        '${streamImageSize.width.toInt()}×${streamImageSize.height.toInt()}px');
    debugPrint('[FaceCrop] Sensor orientation: $sensorOrientation°  '
        'isFrontCamera: $isFrontCamera');
    debugPrint('[FaceCrop] MLKit BoundingBox: $faceBoundingBox');

    // ── 2. Rotate to upright ─────────────────────────────────────────────────
    // On Android, takePicture() saves the JPEG with the sensor rotation baked
    // in via EXIF, but the image/package may not auto-apply it.  We rotate
    // explicitly so the pixel layout matches what the user sees.
    final rotated = _applyRotation(original, sensorOrientation, isFrontCamera);
    debugPrint(
        '[FaceCrop] After rotation: ${rotated.width}×${rotated.height}px');

    // ── 3. No bounding box — resize full image and return ───────────────────
    if (faceBoundingBox == null) {
      debugPrint('[FaceCrop] No bounding box — sending resized full image.');
      return FaceCropResult.ok(_resizeAndEncode(rotated));
    }

    // ── 4. Scale bounding box to rotated image space ─────────────────────────
    //
    // MLKit bounding box is in *stream* pixel space.
    // After rotation the image might have swapped width/height.
    // We must scale from stream coords → rotated image coords.
    //
    // For a 90° or 270° rotation the image is transposed, so the stream's
    // width maps to the image's height and vice versa.
    final double imgW = rotated.width.toDouble();
    final double imgH = rotated.height.toDouble();

    // Stream size in the *same orientation as the bounding box*
    // ML Kit on Android with NV21 in portrait gives stream as landscape
    // (width > height) even though the face appears portrait on screen.
    final double streamW = streamImageSize.width;
    final double streamH = streamImageSize.height;

    final double scaleX = imgW / streamW;
    final double scaleY = imgH / streamH;

    double left = faceBoundingBox.left * scaleX;
    double top = faceBoundingBox.top * scaleY;
    double width = faceBoundingBox.width * scaleX;
    double height = faceBoundingBox.height * scaleY;

    debugPrint('[FaceCrop] Scaled crop (before pad): '
        'left=${left.toInt()} top=${top.toInt()} '
        'w=${width.toInt()} h=${height.toInt()}');

    // ── 5. Front camera mirror correction ───────────────────────────────────
    // The captured JPEG (after rotation) is NOT mirrored — only the *preview*
    // is mirrored.  MLKit runs on the preview stream, so its coordinates are
    // in mirrored space.  We need to flip the left edge.
    if (isFrontCamera) {
      left = imgW - (left + width);
      debugPrint('[FaceCrop] Mirror-corrected left: ${left.toInt()}');
    }

    // ── 6. Padding ───────────────────────────────────────────────────────────
    final padX = width * _padX;
    final padY = height * _padY;
    left -= padX;
    top -= padY;
    width += padX * 2;
    height += padY * 2;

    // ── 7. Clamp to image bounds ─────────────────────────────────────────────
    final x = left.round().clamp(0, rotated.width - 1);
    final y = top.round().clamp(0, rotated.height - 1);
    final w = width.round().clamp(1, rotated.width - x);
    final h = height.round().clamp(1, rotated.height - y);

    debugPrint('[FaceCrop] Final crop rect: x=$x y=$y w=$w h=$h');

    // ── 8. Validate minimum crop size ────────────────────────────────────────
    if (w < _minCropPx || h < _minCropPx) {
      debugPrint('[FaceCrop] Crop too small ($w×${h}px) — '
          'falling back to full image resize.');
      return FaceCropResult.ok(_resizeAndEncode(rotated));
    }

    // ── 9. Crop ──────────────────────────────────────────────────────────────
    final cropped = img.copyCrop(rotated, x: x, y: y, width: w, height: h);
    debugPrint(
        '[FaceCrop] Final crop size: ${cropped.width}×${cropped.height}px');

    return FaceCropResult.ok(_resizeAndEncode(cropped));
  }

  // ── Rotation helper ────────────────────────────────────────────────────────
  static img.Image _applyRotation(
      img.Image src, int sensorDeg, bool isFrontCamera) {
    // For the front (selfie) camera the sensor is typically mounted rotated
    // 270° on Android.  takePicture() honours the sensor orientation for the
    // JPEG, but the image package does NOT auto-rotate by EXIF.
    // We rotate the raw pixels here so the image is always upright.
    int deg = sensorDeg;

    // Front cameras behave differently from back cameras — the mirroring
    // means the effective rotation is the complement.
    if (isFrontCamera) {
      // Common: sensorOrientation = 270 on front → rotate 90 CW to fix
      // Adjust so that 270 → 90, 90 → 270 (flip), 0/180 stay the same.
      deg = (360 - deg) % 360;
    }

    switch (deg) {
      case 90:
        return img.copyRotate(src, angle: 90);
      case 180:
        return img.copyRotate(src, angle: 180);
      case 270:
        return img.copyRotate(src, angle: 270);
      default:
        return src; // 0° — already upright
    }
  }

  // ── Resize + JPEG encode ───────────────────────────────────────────────────
  static Uint8List _resizeAndEncode(img.Image src) {
    img.Image out;
    if (src.width > _maxPx || src.height > _maxPx) {
      out = src.width >= src.height
          ? img.copyResize(src,
              width: _maxPx, interpolation: img.Interpolation.linear)
          : img.copyResize(src,
              height: _maxPx, interpolation: img.Interpolation.linear);
    } else {
      out = src;
    }
    final bytes = Uint8List.fromList(img.encodeJpg(out, quality: _jpegQ));
    debugPrint('[FaceCrop] Encoded: ${out.width}×${out.height}px | '
        '${(bytes.length / 1024).toStringAsFixed(1)} KB');
    return bytes;
  }
}
