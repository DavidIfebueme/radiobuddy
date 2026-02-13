import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_estimator.dart';
import 'pose_metrics.dart';

class MlKitPoseEstimator implements PoseEstimator {
  MlKitPoseEstimator()
      : _detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        );

  final PoseDetector _detector;

  CameraController? _controller;
  Timer? _timer;
  Pose? _previousPose;
  bool _busy = false;

  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<void> start({
    required CameraController controller,
    required PoseMetricsCallback onMetrics,
  }) async {
    await stop();
    if (!supported) {
      return;
    }

    _controller = controller;
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      unawaited(_captureAndEstimate(onMetrics));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _controller = null;
    _previousPose = null;
  }

  Future<void> _captureAndEstimate(PoseMetricsCallback onMetrics) async {
    if (_busy) {
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    _busy = true;
    try {
      final image = await controller.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final poses = await _detector.processImage(inputImage);
      if (poses.isEmpty) {
        return;
      }

      final currentPose = poses.first;
      final metrics = _buildMetrics(currentPose, controller.value.previewSize);
      _previousPose = currentPose;
      onMetrics(metrics);

      final imageFile = File(image.path);
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  PoseMetrics _buildMetrics(Pose pose, Size? previewSize) {
    final landmarks = pose.landmarks;

    final confidence = _clamp01(
      landmarks.values.fold<double>(0.0, (sum, lm) => sum + lm.likelihood) /
          math.max(1, landmarks.length).toDouble(),
    );

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final nose = landmarks[PoseLandmarkType.nose];

    final width = (previewSize?.width ?? 1280).abs();
    final height = (previewSize?.height ?? 720).abs();
    final centerX = width / 2.0;
    final centerY = height / 2.0;

    final torsoPoints = [leftShoulder, rightShoulder, leftHip, rightHip]
        .whereType<PoseLandmark>()
        .toList(growable: false);

    double framingScore = 0.0;
    if (torsoPoints.length >= 3) {
      final avgX = torsoPoints.fold<double>(0.0, (sum, p) => sum + p.x) / torsoPoints.length;
      final avgY = torsoPoints.fold<double>(0.0, (sum, p) => sum + p.y) / torsoPoints.length;
      final dx = (avgX - centerX).abs() / math.max(1.0, width / 2.0);
      final dy = (avgY - centerY).abs() / math.max(1.0, height / 2.0);
      final centerPenalty = _clamp01((dx + dy) / 2.0);

      final minY = torsoPoints.map((p) => p.y).reduce(math.min);
      final maxY = torsoPoints.map((p) => p.y).reduce(math.max);
      final minX = torsoPoints.map((p) => p.x).reduce(math.min);
      final maxX = torsoPoints.map((p) => p.x).reduce(math.max);
      final boxHeightRatio = _clamp01((maxY - minY) / math.max(1.0, height));
      final boxWidthRatio = _clamp01((maxX - minX) / math.max(1.0, width));
      final sizeFactor = _clamp01((boxHeightRatio * 1.5 + boxWidthRatio) / 2.0);

      framingScore = _clamp01((1.0 - centerPenalty) * 0.7 + sizeFactor * 0.3);
    }

    double motionScore = 0.0;
    if (_previousPose != null) {
      final prevLandmarks = _previousPose!.landmarks;
      var total = 0.0;
      var count = 0;
      for (final entry in landmarks.entries) {
        final prev = prevLandmarks[entry.key];
        if (prev == null) {
          continue;
        }
        final dx = entry.value.x - prev.x;
        final dy = entry.value.y - prev.y;
        total += math.sqrt(dx * dx + dy * dy);
        count += 1;
      }
      if (count > 0) {
        final avg = total / count;
        final diag = math.sqrt(width * width + height * height);
        motionScore = _clamp01(avg / math.max(1.0, diag * 0.02));
      }
    }

    double rotationRisk = 0.5;
    if (leftShoulder != null && rightShoulder != null) {
      final zDiff = (leftShoulder.z - rightShoulder.z).abs();
      final zRisk = _clamp01(zDiff / 250.0);
      final visRisk = _clamp01((leftShoulder.likelihood - rightShoulder.likelihood).abs());
      rotationRisk = _clamp01((zRisk * 0.7) + (visRisk * 0.3));
    }

    double tiltRisk = 0.5;
    if (leftShoulder != null && rightShoulder != null) {
      final angle = (math.atan2(
            rightShoulder.y - leftShoulder.y,
            rightShoulder.x - leftShoulder.x,
          ) *
          180.0 /
          math.pi)
          .abs();
      final normalized = _clamp01(angle / 30.0);
      tiltRisk = normalized;
    }

    double chinRisk = 0.5;
    if (nose != null && leftShoulder != null && rightShoulder != null) {
      final shoulderY = (leftShoulder.y + rightShoulder.y) / 2.0;
      final delta = (nose.y - shoulderY) / math.max(1.0, height * 0.2);
      chinRisk = _clamp01((delta + 1.0) / 2.0);
    }

    double scapulaRisk = 0.5;
    if (leftShoulder != null && rightShoulder != null && leftHip != null && rightHip != null) {
      final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
      final hipWidth = (leftHip.x - rightHip.x).abs();
      final ratio = shoulderWidth / math.max(1.0, hipWidth);
      scapulaRisk = _clamp01((ratio - 0.8) / 0.6);
    }

    final torsoHeight = torsoPoints.length >= 2
        ? (torsoPoints.map((p) => p.y).reduce(math.max) - torsoPoints.map((p) => p.y).reduce(math.min))
        : 0.0;
    final sizeRatio = torsoHeight / math.max(1.0, height);
    final sizeClass = sizeRatio < 0.35
        ? 'small'
        : sizeRatio > 0.55
            ? 'large'
            : 'average';

    return PoseMetrics(
      poseConfidence: confidence,
      framingScore: framingScore,
      motionScore: motionScore,
      rotationRisk: rotationRisk,
      tiltRisk: tiltRisk,
      chinRisk: chinRisk,
      scapulaRisk: scapulaRisk,
      sizeClass: sizeClass,
    );
  }

  double _clamp01(double value) {
    if (value < 0.0) {
      return 0.0;
    }
    if (value > 1.0) {
      return 1.0;
    }
    return value;
  }
}

PoseEstimator createPoseEstimatorImpl() => MlKitPoseEstimator();
