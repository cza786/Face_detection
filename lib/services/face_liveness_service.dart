import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceLivenessService {
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  void initialize() {
    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,  // eye open + smiling probabilities
      enableTracking: false,        // tracking off — we want fresh detection each frame
      minFaceSize: 0.20,            // face must occupy at least 20% of frame
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
    _isInitialized = true;
  }

  void dispose() {
    if (_isInitialized) {
      _faceDetector.close();
      _isInitialized = false;
    }
  }

  /// Analyzes a captured [XFile] image (used after takePicture()).
  Future<FaceAnalysisResult> analyzeFace(XFile imageFile) async {
    if (!_isInitialized) initialize();
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      return _evaluate(faces);
    } catch (e) {
      return FaceAnalysisResult.error('Face analysis failed: $e');
    }
  }

  /// Analyzes raw camera stream bytes (used in real-time preview).
  Future<FaceAnalysisResult> analyzeFaceFromBytes(
      Uint8List bytes, InputImageMetadata metadata) async {
    if (!_isInitialized) initialize();
    try {
      final inputImage =
          InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final faces = await _faceDetector.processImage(inputImage);
      return _evaluate(faces);
    } catch (e) {
      return FaceAnalysisResult.error('Frame analysis failed: $e');
    }
  }

  FaceAnalysisResult _evaluate(List<Face> faces) {
    // ── No face ──────────────────────────────────────────────────────────
    if (faces.isEmpty) {
      return FaceAnalysisResult.noFace();
    }

    // ── Multiple faces — reject ──────────────────────────────────────────
    if (faces.length > 1) {
      return FaceAnalysisResult.multipleFaces();
    }

    final face = faces.first;
    return _checkSingleFace(face);
  }

  FaceAnalysisResult _checkSingleFace(Face face) {
    // ── 1. Face must be straight (not tilted/turned) ──────────────────────
    final eulerY = face.headEulerAngleY ?? 0.0;  // left-right rotation
    final eulerZ = face.headEulerAngleZ ?? 0.0;  // tilt
    final eulerX = face.headEulerAngleX ?? 0.0;  // up-down nod

    const maxYaw   = 18.0;  // left-right
    const maxRoll  = 18.0;  // tilt
    const maxPitch = 20.0;  // up-down

    if (eulerY.abs() > maxYaw) {
      return FaceAnalysisResult.notStraight(
        message: eulerY > 0
            ? 'Turn your face slightly to the left'
            : 'Turn your face slightly to the right',
        headEulerY: eulerY,
        headEulerZ: eulerZ,
      );
    }
    if (eulerZ.abs() > maxRoll) {
      return FaceAnalysisResult.notStraight(
        message: 'Keep your head straight — don\'t tilt',
        headEulerY: eulerY,
        headEulerZ: eulerZ,
      );
    }
    if (eulerX.abs() > maxPitch) {
      return FaceAnalysisResult.notStraight(
        message: eulerX > 0
            ? 'Lower your chin slightly'
            : 'Raise your chin slightly',
        headEulerY: eulerY,
        headEulerZ: eulerZ,
      );
    }

    // ── 2. Face must be close enough ─────────────────────────────────────
    final faceArea =
        face.boundingBox.width * face.boundingBox.height;
    if (faceArea < 8000) {
      return FaceAnalysisResult.tooFar();
    }

    // ── 3. Eyes must be open (liveness) ──────────────────────────────────
    final leftEye  = face.leftEyeOpenProbability  ?? 0.0;
    final rightEye = face.rightEyeOpenProbability ?? 0.0;

    // If ML Kit couldn't determine eye state, skip eye check
    final eyeDataAvailable = face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null;

    if (eyeDataAvailable) {
      if (leftEye < 0.4) {
        return FaceAnalysisResult.eyesClosed(
            'Please open your left eye fully');
      }
      if (rightEye < 0.4) {
        return FaceAnalysisResult.eyesClosed(
            'Please open your right eye fully');
      }
    }

    // ── 4. Compute liveness score ─────────────────────────────────────────
    double score = 0.5; // base: face detected + straight + close
    if (eyeDataAvailable && leftEye > 0.7 && rightEye > 0.7) score += 0.35;
    if (faceArea > 20000) score += 0.15; // bonus for being close

    final smiling = face.smilingProbability ?? 0.0;

    return FaceAnalysisResult(
      faceDetected: true,
      isLive: true,
      livenessScore: score.clamp(0.0, 1.0),
      isFacingStraight: true,
      eyesOpen: !eyeDataAvailable || (leftEye >= 0.4 && rightEye >= 0.4),
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
      smilingProbability: smiling,
      headEulerAngleY: eulerY,
      headEulerAngleZ: eulerZ,
      boundingBox: face.boundingBox,
      message: 'Live face confirmed — hold still',
      issue: FaceIssue.none,
    );
  }
}

// ─── Result Model ─────────────────────────────────────────────────────────────

class FaceAnalysisResult {
  final bool faceDetected;
  final bool isLive;
  final double livenessScore;
  final bool isFacingStraight;
  final bool eyesOpen;
  final double leftEyeOpenProbability;
  final double rightEyeOpenProbability;
  final double smilingProbability;
  final double headEulerAngleY;
  final double headEulerAngleZ;
  final dynamic boundingBox;
  final String message;
  final FaceIssue issue;

  const FaceAnalysisResult({
    required this.faceDetected,
    required this.isLive,
    required this.livenessScore,
    required this.isFacingStraight,
    required this.eyesOpen,
    required this.leftEyeOpenProbability,
    required this.rightEyeOpenProbability,
    required this.smilingProbability,
    required this.headEulerAngleY,
    required this.headEulerAngleZ,
    required this.boundingBox,
    required this.message,
    this.issue = FaceIssue.none,
  });

  // ── Named constructors for failure cases ──────────────────────────────

  factory FaceAnalysisResult.noFace() => const FaceAnalysisResult(
        faceDetected: false,
        isLive: false,
        livenessScore: 0,
        isFacingStraight: false,
        eyesOpen: false,
        leftEyeOpenProbability: 0,
        rightEyeOpenProbability: 0,
        smilingProbability: 0,
        headEulerAngleY: 0,
        headEulerAngleZ: 0,
        boundingBox: null,
        message: "It's not a face",
        issue: FaceIssue.noFace,
      );

  factory FaceAnalysisResult.multipleFaces() => const FaceAnalysisResult(
        faceDetected: true,
        isLive: false,
        livenessScore: 0,
        isFacingStraight: false,
        eyesOpen: false,
        leftEyeOpenProbability: 0,
        rightEyeOpenProbability: 0,
        smilingProbability: 0,
        headEulerAngleY: 0,
        headEulerAngleZ: 0,
        boundingBox: null,
        message: 'Only one face allowed in frame',
        issue: FaceIssue.multipleFaces,
      );

  factory FaceAnalysisResult.notStraight({
    required String message,
    required double headEulerY,
    required double headEulerZ,
  }) =>
      FaceAnalysisResult(
        faceDetected: true,
        isLive: false,
        livenessScore: 0,
        isFacingStraight: false,
        eyesOpen: false,
        leftEyeOpenProbability: 0,
        rightEyeOpenProbability: 0,
        smilingProbability: 0,
        headEulerAngleY: headEulerY,
        headEulerAngleZ: headEulerZ,
        boundingBox: null,
        message: message,
        issue: FaceIssue.notStraight,
      );

  factory FaceAnalysisResult.tooFar() => const FaceAnalysisResult(
        faceDetected: true,
        isLive: false,
        livenessScore: 0,
        isFacingStraight: true,
        eyesOpen: false,
        leftEyeOpenProbability: 0,
        rightEyeOpenProbability: 0,
        smilingProbability: 0,
        headEulerAngleY: 0,
        headEulerAngleZ: 0,
        boundingBox: null,
        message: 'Move closer to the camera',
        issue: FaceIssue.tooFar,
      );

  factory FaceAnalysisResult.eyesClosed(String msg) => FaceAnalysisResult(
        faceDetected: true,
        isLive: false,
        livenessScore: 0,
        isFacingStraight: true,
        eyesOpen: false,
        leftEyeOpenProbability: 0,
        rightEyeOpenProbability: 0,
        smilingProbability: 0,
        headEulerAngleY: 0,
        headEulerAngleZ: 0,
        boundingBox: null,
        message: msg,
        issue: FaceIssue.eyesClosed,
      );

  factory FaceAnalysisResult.error(String msg) => FaceAnalysisResult(
        faceDetected: false,
        isLive: false,
        livenessScore: 0,
        isFacingStraight: false,
        eyesOpen: false,
        leftEyeOpenProbability: 0,
        rightEyeOpenProbability: 0,
        smilingProbability: 0,
        headEulerAngleY: 0,
        headEulerAngleZ: 0,
        boundingBox: null,
        message: msg,
        issue: FaceIssue.error,
      );
}

enum FaceIssue {
  none,
  noFace,
  multipleFaces,
  notStraight,
  tooFar,
  eyesClosed,
  error,
}
