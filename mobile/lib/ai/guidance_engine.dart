class GuidancePrompt {
  const GuidancePrompt({
    required this.id,
    required this.text,
    required this.tts,
    required this.cooldownMs,
    required this.minPersistMs,
  });

  final String id;
  final String text;
  final String tts;
  final int cooldownMs;
  final int minPersistMs;
}

class GuidanceCondition {
  const GuidanceCondition({
    required this.metric,
    required this.op,
    required this.value,
  });

  final String metric;
  final String op;
  final double value;
}

class GuidanceRule {
  const GuidanceRule({
    required this.id,
    required this.stageIds,
    required this.priority,
    required this.conditions,
    required this.promptId,
    required this.isReadySignal,
  });

  final String id;
  final List<String> stageIds;
  final int priority;
  final List<GuidanceCondition> conditions;
  final String promptId;
  final bool isReadySignal;
}

class GuidanceDecision {
  const GuidanceDecision({
    required this.ruleId,
    required this.prompt,
    required this.isReadySignal,
  });

  final String ruleId;
  final GuidancePrompt prompt;
  final bool isReadySignal;
}

class GuidanceEngine {
  GuidanceEngine({
    required List<GuidanceRule> rules,
    required Map<String, GuidancePrompt> prompts,
  })  : _rules = List<GuidanceRule>.from(rules)
          ..sort((a, b) => b.priority.compareTo(a.priority)),
        _prompts = Map<String, GuidancePrompt>.from(prompts);

  final List<GuidanceRule> _rules;
  final Map<String, GuidancePrompt> _prompts;

  factory GuidanceEngine.fromProcedureRules(Map<String, Object?> payload) {
    final promptMap = <String, GuidancePrompt>{};
    final rawPrompts = payload['prompts'];
    if (rawPrompts is List) {
      for (final item in rawPrompts) {
        if (item is! Map) {
          continue;
        }
        final map = item.cast<String, Object?>();
        final id = map['prompt_id'];
        final text = map['text'];
        if (id is! String || text is! String) {
          continue;
        }
        final ttsValue = map['tts'];
        final cooldownValue = map['cooldown_ms'];
        final persistValue = map['min_persist_ms'];
        promptMap[id] = GuidancePrompt(
          id: id,
          text: text,
          tts: ttsValue is String ? ttsValue : text,
          cooldownMs: cooldownValue is int ? cooldownValue : 3000,
          minPersistMs: persistValue is int ? persistValue : 700,
        );
      }
    }

    final rules = <GuidanceRule>[];
    final rawRules = payload['rules'];
    if (rawRules is List) {
      for (final item in rawRules) {
        if (item is! Map) {
          continue;
        }
        final map = item.cast<String, Object?>();
        final id = map['rule_id'];
        final priority = map['priority'];
        final stageIdsRaw = map['stage_ids'];
        final thenRaw = map['then'];
        if (id is! String || priority is! int || stageIdsRaw is! List || thenRaw is! Map) {
          continue;
        }

        final thenMap = thenRaw.cast<String, Object?>();
        final promptId = thenMap['prompt_id'];
        if (promptId is! String) {
          continue;
        }

        final stageIds = <String>[];
        for (final stage in stageIdsRaw) {
          if (stage is String) {
            stageIds.add(stage);
          }
        }
        if (stageIds.isEmpty) {
          continue;
        }

        final conditions = <GuidanceCondition>[];
        final whenRaw = map['when'];
        if (whenRaw is Map) {
          final whenMap = whenRaw.cast<String, Object?>();
          final allRaw = whenMap['all'];
          if (allRaw is List) {
            for (final cond in allRaw) {
              if (cond is! Map) {
                continue;
              }
              final condMap = cond.cast<String, Object?>();
              final metric = condMap['metric'];
              final op = condMap['op'];
              final value = condMap['value'];
              if (metric is String && op is String && value is num) {
                conditions.add(GuidanceCondition(metric: metric, op: op, value: value.toDouble()));
              }
            }
          }
        }

        rules.add(
          GuidanceRule(
            id: id,
            stageIds: stageIds,
            priority: priority,
            conditions: conditions,
            promptId: promptId,
            isReadySignal: thenMap['is_ready_signal'] == true,
          ),
        );
      }
    }

    return GuidanceEngine(rules: rules, prompts: promptMap);
  }

  GuidanceDecision? decide({
    required String stageId,
    required Map<String, double> metrics,
  }) {
    for (final rule in _rules) {
      if (!rule.stageIds.contains(stageId)) {
        continue;
      }
      if (!_matchesConditions(rule.conditions, metrics)) {
        continue;
      }
      final prompt = _prompts[rule.promptId];
      if (prompt == null) {
        continue;
      }
      return GuidanceDecision(
        ruleId: rule.id,
        prompt: prompt,
        isReadySignal: rule.isReadySignal,
      );
    }
    return null;
  }

  bool _matchesConditions(List<GuidanceCondition> conditions, Map<String, double> metrics) {
    for (final condition in conditions) {
      final current = metrics[condition.metric];
      if (current == null) {
        return false;
      }
      if (!_compare(current, condition.op, condition.value)) {
        return false;
      }
    }
    return true;
  }

  bool _compare(double current, String op, double target) {
    switch (op) {
      case 'lt':
        return current < target;
      case 'lte':
        return current <= target;
      case 'gt':
        return current > target;
      case 'gte':
        return current >= target;
      case 'eq':
        return current == target;
      case 'neq':
        return current != target;
      default:
        return false;
    }
  }
}
