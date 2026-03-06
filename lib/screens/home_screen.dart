import 'package:flutter/material.dart';
import '../services/secure_storage_service.dart';
import 'attendance_screen.dart';

// ─── HomeScreen ───────────────────────────────────────────────────────────────
//
// Shown after successful face authentication.
//
// employeeData keys (flattened from the API response):
//   'name'          → employee / team name   (e.g. "Inventory Team")
//   'serial_number' → serial number           (e.g. "HWKD-00831")
//   'token'         → Bearer session token
//   'token_type'    → "Bearer"
//   'expires_in'    → token lifetime in seconds (e.g. 3600)
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> employeeData;

  const HomeScreen({super.key, this.employeeData = const {}});

  @override
  Widget build(BuildContext context) {
    final name = (employeeData['name'] ?? 'Employee') as String;
    final serialNum = (employeeData['serial_number'] ?? '') as String;
    final token = (employeeData['token'] ?? '') as String;
    final tokenType = (employeeData['token_type'] ?? 'Bearer') as String;
    final expiresIn = employeeData['expires_in'];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Attendance',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Employee card ──────────────────────────────────────────────
            _Card(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF0A84FF), Color(0xFF30D158)],
                      ),
                    ),
                    child: const Icon(Icons.verified_user,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (serialNum.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            serialNum,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Green "verified" badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF30D158).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF30D158).withOpacity(0.4)),
                    ),
                    child: const Text(
                      '✓ Verified',
                      style: TextStyle(
                          color: Color(0xFF30D158),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Session token card ─────────────────────────────────────────
            if (token.isNotEmpty)
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.key_rounded,
                            color: Color(0xFF0A84FF), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Session Token',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        _Chip(label: tokenType),
                        if (expiresIn != null) ...[
                          const SizedBox(width: 6),
                          _Chip(label: '${expiresIn}s'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      token,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // ── Log Out ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await SecureStorageService.clearAll();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AttendanceScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout),
                label: const Text(
                  'Log Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF453A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small reusable widgets ───────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: child,
      );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0A84FF).withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Color(0xFF0A84FF),
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      );
}
