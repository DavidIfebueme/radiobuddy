import 'package:camera/camera.dart';

import 'pose_estimator.dart';

class StubPoseEstimator implements PoseEstimator {
  @override
  bool get supported => false;

  @override
  Future<void> start({
    required CameraController controller,
    required PoseMetricsCallback onMetrics,
  }) async {}

  @override
  Future<void> stop() async {}
}

PoseEstimator createPoseEstimatorImpl() => StubPoseEstimator();
