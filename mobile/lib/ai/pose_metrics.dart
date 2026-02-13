class PoseMetrics {
  const PoseMetrics({
    required this.poseConfidence,
    required this.framingScore,
    required this.motionScore,
    required this.rotationRisk,
    required this.tiltRisk,
    required this.chinRisk,
    required this.scapulaRisk,
    required this.sizeClass,
  });

  final double poseConfidence;
  final double framingScore;
  final double motionScore;
  final double rotationRisk;
  final double tiltRisk;
  final double chinRisk;
  final double scapulaRisk;
  final String sizeClass;

  Map<String, double> toMap() {
    return {
      'pose_confidence': poseConfidence,
      'framing_score': framingScore,
      'motion_score': motionScore,
      'rotation_risk': rotationRisk,
      'tilt_risk': tiltRisk,
      'chin_risk': chinRisk,
      'scapula_risk': scapulaRisk,
    };
  }
}
