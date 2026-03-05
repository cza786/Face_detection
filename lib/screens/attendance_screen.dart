import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/face_liveness_service.dart';
import '../services/face_crop_service.dart';
import '../services/auth_service.dart';
import '../services/location_device_service.dart';
import '../widgets/face_overlay_painter.dart';
import '../widgets/scan_status_widget.dart';
import 'home_screen.dart';

enum ScanState {
  idle,
  initializing,
  scanning,
  analyzing,
  verifying,
  success,
  failed,
  error,
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  final FaceLivenessService _livenessService = FaceLivenessService();

  ScanState _scanState = ScanState.idle;
  String _statusMessage = 'Tap "Start Attendance" to begin';
  String _subMessage = '';

  bool _torchEnabled = false;
  bool _torchAvailable = false;

  // ── Frame throttle ─────────────────────────────────────────────────────────
  bool _isProcessingFrame = false;
  int _frameSkipCounter = 0;
  static const int _frameSkipRate = 3;

  // ── Liveness gate ──────────────────────────────────────────────────────────
  // 8 consecutive clean frames required — reduces false positives and makes
  // the crop more stable before capture.
  int _consecutiveLiveFrames = 0;
  static const int _requiredLiveFrames = 8;

  // ── Prevent double-capture ─────────────────────────────────────────────────
  bool _captureTriggered = false;

  // ── Last known ML Kit bounding box + stream frame size ────────────────────
  // These are in *camera stream* pixel space — passed to FaceCropService.
  Rect? _lastFaceBoundingBox;
  Size? _lastStreamSize; // size of the CameraImage frame MLKit ran on

  // ── Overlay state ──────────────────────────────────────────────────────────
  bool _faceDetected = false;
  bool _isLive = false;

  // ── Device hash (prefetched) ───────────────────────────────────────────────
  String? _cachedDeviceHash;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  late Animation<double> _pulseAnim;
  late Animation<double> _scanLineAnim;

  // ── Camera metadata (needed for crop) ─────────────────────────────────────
  int _sensorOrientation = 0;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _livenessService.initialize();
    LocationDeviceService.printDeviceIdAndLocation();

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _scanLineController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _scanLineController, curve: Curves.linear));

    _prefetchDeviceHash();
  }

  @override
  void dispose() {
    _releaseCamera();
    _livenessService.dispose();
    _pulseController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  // ─── Prefetch device hash ────────────────────────────────────────────────

  Future<void> _prefetchDeviceHash() async {
    try {
      _cachedDeviceHash = await LocationDeviceService.getDeviceHash();
      debugPrint('[AttendanceScreen] Device hash ready: '
          '${_cachedDeviceHash?.substring(0, 8)}…');
    } catch (e) {
      debugPrint('[AttendanceScreen] Device hash fetch failed: $e');
    }
  }

  // ─── Torch (stubs — kept for UI compatibility) ────────────────────────────

  Future<void> _checkTorchAvailability() async {
    if (mounted) setState(() => _torchAvailable = false);
  }

  Future<void> _enableTorch() async {
    if (mounted) setState(() => _torchEnabled = false);
  }

  Future<void> _disableTorch() async {
    if (mounted) setState(() => _torchEnabled = false);
  }

  // ─── Camera ──────────────────────────────────────────────────────────────

  Future<void> _releaseCamera() async {
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    try {
      await _cameraController?.dispose();
    } catch (_) {}
    _cameraController = null;
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<void> _initializeCamera() async {
    _setUiState(ScanState.initializing, 'Initializing camera…');

    final granted = await _requestCameraPermission();
    if (!granted) {
      _setUiState(ScanState.error, 'Camera permission denied',
          sub: 'Allow camera access in Settings');
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _setUiState(ScanState.error, 'No cameras found on this device');
        return;
      }

      // Prefer front camera for selfie attendance
      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      // Store camera metadata for FaceCropService
      _sensorOrientation = front.sensorOrientation;
      _isFrontCamera = front.lensDirection == CameraLensDirection.front;

      debugPrint('[AttendanceScreen] Camera: '
          '${_isFrontCamera ? "FRONT" : "BACK"}  '
          'sensorOrientation: $_sensorOrientation°');

      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _enableTorch();
      await _checkTorchAvailability();

      _resetLiveness();
      _captureTriggered = false;
      _lastFaceBoundingBox = null;
      _lastStreamSize = null;

      _setUiState(ScanState.scanning, 'Position your face in the oval',
          sub: 'Look straight at the camera');

      await _cameraController!.startImageStream(_processFrame);
    } catch (e) {
      _setUiState(ScanState.error, 'Camera failed to start', sub: e.toString());
    }
  }

  // ─── Frame Processing ─────────────────────────────────────────────────────
  // NOTE: No cropping here.  We only run MLKit liveness detection.
  // Cropping happens ONCE after takePicture() in _captureAndVerify().

  Future<void> _processFrame(CameraImage image) async {
    _frameSkipCounter++;
    if (_frameSkipCounter % _frameSkipRate != 0) return;
    if (_isProcessingFrame ||
        _scanState != ScanState.scanning ||
        _captureTriggered ||
        !mounted) {
      return;
    }

    _isProcessingFrame = true;

    try {
      // Pack all planes into a single byte buffer for MLKit
      final totalLength =
          image.planes.fold<int>(0, (sum, p) => sum + p.bytes.length);
      final bytes = Uint8List(totalLength);
      var offset = 0;
      for (final p in image.planes) {
        bytes.setRange(offset, offset + p.bytes.length, p.bytes);
        offset += p.bytes.length;
      }

      // Stream frame dimensions (in camera sensor space)
      final streamSize = Size(image.width.toDouble(), image.height.toDouble());
      final rotation = _cameraController!.description.sensorOrientation;

      final metadata = InputImageMetadata(
        size: streamSize,
        rotation: _rotationFromDegrees(rotation),
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final result =
          await _livenessService.analyzeFaceFromBytes(bytes, metadata);

      if (!mounted || _scanState != ScanState.scanning) return;

      setState(() {
        _faceDetected = result.faceDetected;
        _isLive = result.isLive;
        // Cache the latest bounding box + stream frame size.
        // These are used ONLY for the post-capture crop — not for real-time UI.
        if (result.boundingBox != null) {
          _lastFaceBoundingBox = result.boundingBox as Rect?;
          _lastStreamSize = streamSize;
        }
      });

      // ── Liveness gate ────────────────────────────────────────────────────
      if (result.isLive && result.isFacingStraight && result.faceDetected) {
        _consecutiveLiveFrames++;
        final remaining = _requiredLiveFrames - _consecutiveLiveFrames;
        if (remaining > 0) {
          _updateMessage(
            'Hold still… confirming liveness',
            sub: 'Keep looking straight ($remaining more frames)',
          );
        }
        if (_consecutiveLiveFrames >= _requiredLiveFrames &&
            !_captureTriggered) {
          _captureTriggered = true;
          await _captureAndVerify();
        }
      } else {
        _resetLiveness();
        _updateMessage(result.message, sub: _subForIssue(result.issue));
      }
    } catch (e) {
      debugPrint('[AttendanceScreen] Frame error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  // ─── Capture & Verify ─────────────────────────────────────────────────────

  Future<void> _captureAndVerify() async {
    if (_scanState != ScanState.scanning) return;
    _setUiState(ScanState.analyzing, 'Analyzing face…', sub: 'Hold still');

    try {
      // ── Stop stream, take high-quality still ─────────────────────────────
      await _cameraController?.stopImageStream();
      await Future.delayed(const Duration(milliseconds: 200));
      await _disableTorch();

      final XFile imageFile = await _cameraController!.takePicture();

      debugPrint('[AttendanceScreen] Captured: ${imageFile.path}');

      // ── Final liveness check on still image ──────────────────────────────
      final liveness = await _livenessService.analyzeFace(imageFile);

      if (!liveness.faceDetected) {
        _resetToScanning("No face detected in captured image — try again");
        return;
      }
      if (!liveness.isLive) {
        _resetToScanning(liveness.message);
        return;
      }
      if (!liveness.isFacingStraight) {
        _resetToScanning('Face straight to camera, then try again');
        return;
      }

      // Update bounding box from still-image liveness if available
      final stillBox = liveness.boundingBox != null
          ? liveness.boundingBox as Rect
          : _lastFaceBoundingBox;

      // ── Crop face ─────────────────────────────────────────────────────────
      _setUiState(ScanState.analyzing, 'Cropping face…',
          sub: 'Processing image');

      final imageBytes = await File(imageFile.path).readAsBytes();

      // Stream size at time of detection — use last cached, or derive from
      // camera controller if not available.
      final streamSize = _lastStreamSize ??
          Size(
            _cameraController!.value.previewSize?.height ?? 1920,
            _cameraController!.value.previewSize?.width ?? 1080,
          );

      debugPrint('[AttendanceScreen] Using streamSize: '
          '${streamSize.width.toInt()}×${streamSize.height.toInt()}  '
          'for bounding box: $stillBox');

      final cropResult = FaceCropService.crop(
        imageBytes: imageBytes,
        faceBoundingBox: stillBox,
        streamImageSize: streamSize,
        sensorOrientation: _sensorOrientation,
        isFrontCamera: _isFrontCamera,
      );

      if (!cropResult.success || cropResult.croppedBytes == null) {
        _setUiState(ScanState.error, 'Image crop failed',
            sub: cropResult.error ?? 'Please try again.');
        return;
      }

      debugPrint('[AttendanceScreen] Crop succeeded → '
          '${(cropResult.croppedBytes!.length / 1024).toStringAsFixed(1)} KB');

      // ── Get location ──────────────────────────────────────────────────────
      _setUiState(ScanState.verifying, 'Getting location…',
          sub: 'Preparing verification data');

      LocationData location;
      try {
        location = await LocationDeviceService.getCurrentLocation();
      } on LocationException catch (e) {
        _setUiState(ScanState.error, 'Location error', sub: e.message);
        return;
      }

      final deviceHash =
          _cachedDeviceHash ?? await LocationDeviceService.getDeviceHash();

      // ── Call API ──────────────────────────────────────────────────────────
      _setUiState(ScanState.verifying, 'Verifying identity…',
          sub: 'Matching face with registered employees');

      final result = await AuthVerificationService.verifyFace(
        faceImageBytes: cropResult.croppedBytes!,
        latitude: location.latitude,
        longitude: location.longitude,
        deviceHash: deviceHash,
      );

      if (!mounted) return;

      if (result.isAuthenticated) {
        // ── SUCCESS ──────────────────────────────────────────────────────────
        _setUiState(ScanState.success, 'Identity Verified ✓', sub: 'Welcome!');
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          await _releaseCamera();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  HomeScreen(employeeData: result.employeeData ?? {}),
            ),
          );
        }
      } else if (result.isError) {
        // ── NETWORK / SERVER ERROR ────────────────────────────────────────────
        _setUiState(
          ScanState.error,
          'Verification Error',
          sub: result.message ?? 'Could not reach server. Try again.',
        );
      } else {
        // ── NOT AUTHENTICATED ─────────────────────────────────────────────────
        _setUiState(
          ScanState.failed,
          'Not Authenticated',
          sub: result.message ?? 'Face does not match any registered employee.',
        );
      }
    } catch (e) {
      debugPrint('[AttendanceScreen] captureAndVerify error: $e');
      _setUiState(ScanState.error, 'Verification error', sub: e.toString());
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _resetToScanning(String msg) {
    if (!mounted) return;
    _captureTriggered = false;
    _lastFaceBoundingBox = null;
    _resetLiveness();
    setState(() {
      _scanState = ScanState.scanning;
      _statusMessage = msg;
      _subMessage = 'Try again';
      _faceDetected = false;
      _isLive = false;
    });
    _enableTorch();
    _cameraController?.startImageStream(_processFrame);
  }

  void _resetLiveness() => _consecutiveLiveFrames = 0;

  void _setUiState(ScanState state, String msg, {String sub = ''}) {
    if (!mounted) return;
    setState(() {
      _scanState = state;
      _statusMessage = msg;
      _subMessage = sub;
    });
  }

  void _updateMessage(String msg, {String sub = ''}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _subMessage = sub;
    });
  }

  InputImageRotation _rotationFromDegrees(int d) {
    switch (d) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  String _subForIssue(FaceIssue issue) {
    switch (issue) {
      case FaceIssue.noFace:
        return 'Position your face inside the oval';
      case FaceIssue.multipleFaces:
        return 'Only one face allowed in the frame';
      case FaceIssue.notStraight:
        return 'Align your nose with the centre of the oval';
      case FaceIssue.tooFar:
        return 'Move the phone closer to your face';
      case FaceIssue.eyesClosed:
        return 'Open both eyes and look at the camera';
      default:
        return '';
    }
  }

  Future<void> _startAttendance() async {
    if (_scanState == ScanState.scanning ||
        _scanState == ScanState.initializing) {
      return;
    }
    if (_cameraController?.value.isInitialized == true) {
      await _releaseCamera();
    }
    setState(() {
      _faceDetected = false;
      _isLive = false;
      _lastFaceBoundingBox = null;
    });
    await _initializeCamera();
  }

  Future<void> _cancelScan() async {
    await _releaseCamera();
    await _disableTorch();
    _resetLiveness();
    _captureTriggered = false;
    _setUiState(ScanState.idle, 'Tap "Start Attendance" to begin');
    setState(() {
      _faceDetected = false;
      _isLive = false;
      _lastFaceBoundingBox = null;
    });
  }

  bool get _isCameraActive =>
      _cameraController != null &&
      _cameraController!.value.isInitialized &&
      (_scanState == ScanState.scanning ||
          _scanState == ScanState.analyzing ||
          _scanState == ScanState.verifying);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child:
                  _isCameraActive ? _buildCameraView(size) : _buildIdleView(),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [Color(0xFF0A84FF), Color(0xFF30D158)]),
            ),
            child: const Icon(Icons.face_retouching_natural,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SmartWorker',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              Text('Face Attendance',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 12)),
            ],
          ),
          const Spacer(),
          if (_torchAvailable && _isCameraActive)
            GestureDetector(
              onTap: () => _torchEnabled ? _disableTorch() : _enableTorch(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _torchEnabled
                      ? const Color(0xFF0A84FF).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _torchEnabled
                        ? const Color(0xFF0A84FF)
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Icon(
                  _torchEnabled ? Icons.flash_on : Icons.flash_off,
                  color: _torchEnabled
                      ? const Color(0xFF0A84FF)
                      : Colors.white.withOpacity(0.4),
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraView(Size size) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: CameraPreview(_cameraController!),
          ),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (_, __) => CustomPaint(
              painter: FaceOverlayPainter(
                faceRect: _lastFaceBoundingBox,
                imageSize: _lastStreamSize,
                previewSize: size,
                isLive: _isLive,
                faceDetected: _faceDetected,
                scanLineProgress:
                    _scanState == ScanState.scanning && _faceDetected
                        ? _scanLineAnim.value
                        : null,
                livenessProgress: _requiredLiveFrames > 0
                    ? _consecutiveLiveFrames / _requiredLiveFrames
                    : 0.0,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: ScanStatusWidget(
            scanState: _scanState,
            message: _statusMessage,
            subMessage: _subMessage,
          ),
        ),
        if (_scanState == ScanState.analyzing ||
            _scanState == ScanState.verifying)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                          color: Color(0xFF0A84FF), strokeWidth: 3),
                    ),
                    const SizedBox(height: 20),
                    Text(_statusMessage,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                    if (_subMessage.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(_subMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _scanState == ScanState.idle ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _stateColor, width: 2.5),
                  color: _stateColor.withOpacity(0.08),
                ),
                child: Icon(_stateIcon, size: 72, color: _stateColor),
              ),
            ),
            const SizedBox(height: 32),
            Text(_statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _stateColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            if (_subMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_subMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5), fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: _isCameraActive
          ? SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _cancelScan,
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                label: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.15)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            )
          : SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _scanState == ScanState.initializing
                    ? null
                    : _startAttendance,
                icon: const Icon(Icons.face_unlock_outlined, size: 24),
                label: Text(
                  _scanState == ScanState.failed
                      ? 'Try Again'
                      : 'Start Attendance',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scanState == ScanState.failed
                      ? const Color(0xFFFF453A)
                      : const Color(0xFF0A84FF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF0A84FF).withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
              ),
            ),
    );
  }

  Color get _stateColor {
    switch (_scanState) {
      case ScanState.success:
        return const Color(0xFF30D158);
      case ScanState.failed:
        return const Color(0xFFFF453A);
      case ScanState.error:
        return const Color(0xFFFF9F0A);
      default:
        return const Color(0xFF0A84FF);
    }
  }

  IconData get _stateIcon {
    switch (_scanState) {
      case ScanState.success:
        return Icons.verified_user_outlined;
      case ScanState.failed:
        return Icons.no_accounts_outlined;
      case ScanState.error:
        return Icons.error_outline;
      default:
        return Icons.face_retouching_natural;
    }
  }
}
