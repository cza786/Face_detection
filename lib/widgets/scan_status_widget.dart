import 'package:flutter/material.dart';
import '../screens/attendance_screen.dart';

class ScanStatusWidget extends StatelessWidget {
  final ScanState scanState;
  final String message;
  final String subMessage;

  const ScanStatusWidget({
    super.key,
    required this.scanState,
    required this.message,
    required this.subMessage,
  });

  Color get _bgColor {
    switch (scanState) {
      case ScanState.success:
        return const Color(0xFF30D158).withOpacity(0.18);
      case ScanState.failed:
        return const Color(0xFFFF453A).withOpacity(0.18);
      case ScanState.error:
        return const Color(0xFFFF9F0A).withOpacity(0.18);
      default:
        return Colors.black.withOpacity(0.58);
    }
  }

  Color get _textColor {
    switch (scanState) {
      case ScanState.success:
        return const Color(0xFF30D158);
      case ScanState.failed:
        return const Color(0xFFFF453A);
      case ScanState.error:
        return const Color(0xFFFF9F0A);
      default:
        return Colors.white;
    }
  }

  IconData? get _icon {
    switch (scanState) {
      case ScanState.success:
        return Icons.check_circle_outline;
      case ScanState.failed:
        return Icons.block_outlined;
      case ScanState.error:
        return Icons.warning_amber_outlined;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _textColor.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            if (_icon != null) ...[
              Icon(_icon, color: _textColor, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subMessage.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subMessage,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}