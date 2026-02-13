import 'package:flutter_test/flutter_test.dart';
import 'package:radiobuddy/ai/guidance_engine.dart';

void main() {
  test('selects highest priority matching rule for stage', () {
    final payload = <String, Object?>{
      'prompts': [
        {
          'prompt_id': 'p1',
          'text': 'First',
          'tts': 'First tts',
          'cooldown_ms': 3000,
          'min_persist_ms': 700,
        },
        {
          'prompt_id': 'p2',
          'text': 'Second',
          'tts': 'Second tts',
          'cooldown_ms': 3000,
          'min_persist_ms': 700,
        },
      ],
      'rules': [
        {
          'rule_id': 'low_priority',
          'stage_ids': ['coarse'],
          'priority': 10,
          'when': {
            'all': [
              {'metric': 'rotation_risk', 'op': 'gt', 'value': 0.5},
            ],
          },
          'then': {'prompt_id': 'p1'},
        },
        {
          'rule_id': 'high_priority',
          'stage_ids': ['coarse'],
          'priority': 50,
          'when': {
            'all': [
              {'metric': 'rotation_risk', 'op': 'gt', 'value': 0.5},
            ],
          },
          'then': {'prompt_id': 'p2'},
        },
      ],
    };

    final engine = GuidanceEngine.fromProcedureRules(payload);
    final decision = engine.decide(
      stageId: 'coarse',
      metrics: {'rotation_risk': 0.9},
    );

    expect(decision, isNotNull);
    expect(decision!.ruleId, 'high_priority');
    expect(decision.prompt.id, 'p2');
  });

  test('returns null when stage does not match', () {
    final payload = <String, Object?>{
      'prompts': [
        {
          'prompt_id': 'p1',
          'text': 'First',
          'tts': 'First tts',
          'cooldown_ms': 3000,
          'min_persist_ms': 700,
        },
      ],
      'rules': [
        {
          'rule_id': 'r1',
          'stage_ids': ['fine'],
          'priority': 50,
          'when': {
            'all': [
              {'metric': 'rotation_risk', 'op': 'gt', 'value': 0.5},
            ],
          },
          'then': {'prompt_id': 'p1'},
        },
      ],
    };

    final engine = GuidanceEngine.fromProcedureRules(payload);
    final decision = engine.decide(
      stageId: 'coarse',
      metrics: {'rotation_risk': 0.9},
    );

    expect(decision, isNull);
  });

  test('supports ready signal', () {
    final payload = <String, Object?>{
      'prompts': [
        {
          'prompt_id': 'ready',
          'text': 'Ready',
          'tts': 'Ready',
          'cooldown_ms': 5000,
          'min_persist_ms': 1200,
        },
      ],
      'rules': [
        {
          'rule_id': 'ready_when_good',
          'stage_ids': ['fine'],
          'priority': 20,
          'when': {
            'all': [
              {'metric': 'pose_confidence', 'op': 'gte', 'value': 0.7},
              {'metric': 'motion_score', 'op': 'lte', 'value': 0.2},
            ],
          },
          'then': {
            'prompt_id': 'ready',
            'is_ready_signal': true,
          },
        },
      ],
    };

    final engine = GuidanceEngine.fromProcedureRules(payload);
    final decision = engine.decide(
      stageId: 'fine',
      metrics: {
        'pose_confidence': 0.9,
        'motion_score': 0.1,
      },
    );

    expect(decision, isNotNull);
    expect(decision!.isReadySignal, isTrue);
  });
}
