String? _stringAt(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is String ? value : null;
}

List<Map<String, Object?>> recommendationsFromProtocol(Map<String, Object?> protocol) {
  final recs = protocol['recommendations'];
  if (recs is! List) {
    return const [];
  }
  final List<Map<String, Object?>> out = [];
  for (final item in recs) {
    if (item is Map) {
      out.add(item.cast<String, Object?>());
    }
  }
  return out;
}

Set<int> sidOptionsFromProtocol(
  Map<String, Object?> protocol, {
  required String projectionId,
}) {
  final recs = recommendationsFromProtocol(protocol);
  final options = <int>{};
  for (final rec in recs) {
    final inputs = rec['inputs'];
    if (inputs is Map) {
      final inputsMap = inputs.cast<String, Object?>();
      final projection = _stringAt(inputsMap, 'projection');
      if (projection != projectionId) {
        continue;
      }
      final sid = inputsMap['sid_cm'];
      if (sid is int) {
        options.add(sid);
      }
    }
  }
  return options;
}

Map<String, Object?>? selectExposureFromProtocol(
  Map<String, Object?> protocol, {
  required String projectionId,
  required String sizeClass,
  required bool grid,
  required int sidCm,
}) {
  final recs = recommendationsFromProtocol(protocol);
  if (recs.isEmpty) {
    return null;
  }

  Map<String, Object?>? best;
  var bestScore = -1000000;

  for (final rec in recs) {
    final inputsRaw = rec['inputs'];
    final outputRaw = rec['output'];
    if (inputsRaw is! Map || outputRaw is! Map) {
      continue;
    }
    final inputs = inputsRaw.cast<String, Object?>();
    final output = outputRaw.cast<String, Object?>();

    final projection = _stringAt(inputs, 'projection');
    final recSizeClass = _stringAt(inputs, 'size_class');
    if (projection != projectionId || recSizeClass != sizeClass) {
      continue;
    }

    var score = 0;

    final recGrid = inputs['grid'];
    if (recGrid is bool) {
      if (recGrid != grid) {
        continue;
      }
      score += 2;
    }

    final recSid = inputs['sid_cm'];
    if (recSid is int) {
      if (recSid != sidCm) {
        continue;
      }
      score += 1;
    }

    final kvp = output['kvp'];
    final mas = output['mas'];
    if (kvp is! num || mas is! num) {
      continue;
    }
    score += 10;

    if (score > bestScore) {
      bestScore = score;
      best = output;
    }
  }

  return best;
}
