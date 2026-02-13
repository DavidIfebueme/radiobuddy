import 'package:camera/camera.dart';

import 'pose_metrics.dart';
import 'pose_estimator_stub.dart' if (dart.library.io) 'pose_estimator_io.dart';

typedef PoseMetricsCallback = void Function(PoseMetrics metrics);

abstract class PoseEstimator {
  bool get supported;

  Future<void> start({
    required CameraController controller,
    required PoseMetricsCallback onMetrics,
  });

  Future<void> stop();
}

PoseEstimator createPoseEstimator() => createPoseEstimatorImpl();
