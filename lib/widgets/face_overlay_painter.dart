import 'package:flutter/material.dart';

class FaceOverlayPainter extends CustomPainter {
  final Rect? faceRect;
  final Size? imageSize;
  final Size previewSize;
  final bool isLive;
  final bool faceDetected;
  final double? scanLineProgress;
  final double livenessProgress;

  FaceOverlayPainter({
    required this.faceRect,
    required this.imageSize,
    required this.previewSize,
    required this.isLive,
    required this.faceDetected,
    required this.scanLineProgress,
    required this.livenessProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.6);

    final rect = Offset.zero & size;
    final overlayPath = Path()..addRect(rect);

    final ovalWidth = size.width * 0.72;
    final ovalHeight = size.height * 0.45;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: ovalWidth,
      height: ovalHeight,
    );

    final cutoutPath = Path()..addOval(ovalRect);
    final maskPath =
        Path.combine(PathOperation.difference, overlayPath, cutoutPath);
    canvas.drawPath(maskPath, overlayPaint);

    final borderColor = isLive
        ? const Color(0xFF30D158)
        : (faceDetected
            ? const Color(0xFF0A84FF)
            : Colors.white.withOpacity(0.35));

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawOval(ovalRect, borderPaint);

    if (livenessProgress > 0) {
      final progressPaint = Paint()
        ..color = const Color(0xFF30D158)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      const start = -90.0;
      final sweep = (livenessProgress.clamp(0.0, 1.0)) * 360.0;
      canvas.drawArc(
        ovalRect.inflate(8),
        start * (3.1415926535 / 180.0),
        sweep * (3.1415926535 / 180.0),
        false,
        progressPaint,
      );
    }

    if (scanLineProgress != null) {
      final y =
          ovalRect.top + ovalRect.height * scanLineProgress!.clamp(0.0, 1.0);
      const gradient = LinearGradient(
        colors: [Color(0x000A84FF), Color(0xFF0A84FF), Color(0x000A84FF)],
      );
      final shader = gradient
          .createShader(Rect.fromLTWH(ovalRect.left, y - 1, ovalRect.width, 2));
      final linePaint = Paint()
        ..shader = shader
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(ovalRect.left + 8, y),
          Offset(ovalRect.right - 8, y), linePaint);
    }

    if (faceRect != null && imageSize != null) {
      final sx = size.width / imageSize!.width;
      final sy = size.height / imageSize!.height;
      final mapped = Rect.fromLTWH(
        faceRect!.left * sx,
        faceRect!.top * sy,
        faceRect!.width * sx,
        faceRect!.height * sy,
      );
      final boxPaint = Paint()
        ..color = borderColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(mapped, boxPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.faceRect != faceRect ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.isLive != isLive ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.scanLineProgress != scanLineProgress ||
        oldDelegate.livenessProgress != livenessProgress;
  }
}
