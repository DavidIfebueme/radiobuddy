import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

String _computeDefaultApiBaseUrl() {
  if (kIsWeb) {
    return 'http://127.0.0.1:8000';
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }

  return 'http://127.0.0.1:8000';
}

void main() {
  runApp(const RadioBuddyApp());
}

class RadioBuddyApp extends StatelessWidget {
  const RadioBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radio Buddy',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: const ChestPaGuidanceScreen(),
    );
  }
}

enum GuidanceStatus {
  idle,
  loadingCamera,
  ready,
  running,
  error,
}

class RadiobuddyApi {
  RadiobuddyApi({required this.baseUrl});

  final String baseUrl;

  static const _uuid = Uuid();

  Future<Map<String, Object?>> getJson(String path) async {
    final uri = Uri.parse(baseUrl).resolve(path);
    final response = await http.get(uri, headers: {'accept': 'application/json'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    throw Exception('Unexpected JSON');
  }

  Future<Map<String, Object?>> fetchChestPaRules() {
    return getJson('/procedure-rules/chest-pa');
  }

  Future<Map<String, Object?>> fetchChestPaExposureProtocol() {
    return getJson('/exposure-protocols/chest-pa');
  }

  Future<void> postTelemetryEvent({
    required String eventType,
    required String procedureId,
    String? procedureVersion,
    String? sessionId,
    String? stageId,
    Map<String, Object?>? prompt,
    Map<String, num>? metrics,
  }) async {
    final uri = Uri.parse(baseUrl).resolve('/telemetry/events');
    final now = DateTime.now().toUtc().toIso8601String();

    final Map<String, Object?> payload = {
      'schema_version': 'v1',
      'event_id': _uuid.v4(),
      'timestamp': now,
      'event_type': eventType,
      'procedure_id': procedureId,
    };

    if (procedureVersion != null) {
      payload['procedure_version'] = procedureVersion;
    }
    if (sessionId != null) {
      payload['session_id'] = sessionId;
    }
    if (stageId != null) {
      payload['stage_id'] = stageId;
    }

    payload['device'] = {
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    };

    if (prompt != null) {
      payload['prompt'] = prompt;
    }
    if (metrics != null) {
      payload['metrics'] = metrics;
    }

    final response = await http.post(
      uri,
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }
}

class ChestPaGuidanceScreen extends StatefulWidget {
  const ChestPaGuidanceScreen({super.key});

  @override
  State<ChestPaGuidanceScreen> createState() => _ChestPaGuidanceScreenState();
}

class _ChestPaGuidanceScreenState extends State<ChestPaGuidanceScreen> {
  final _tts = FlutterTts();

  final _uuid = const Uuid();

  late final bool _ttsSupported;

  GuidanceStatus _status = GuidanceStatus.idle;
  String _statusText = 'Idle';
  int _stageIndex = 0;

  CameraController? _camera;
  bool _cameraReady = false;

  Map<String, Object?>? _procedureRules;
  Map<String, Object?>? _exposureProtocol;

  List<Map<String, Object?>> _stages = const [];

  late final RadiobuddyApi _api;

  String? _sessionId;

  static const List<Map<String, Object?>> _fallbackStages = [
    {
      'stage_id': 'acquire_view',
      'stage_name': 'Acquire View',
      'description': 'Get the full torso in frame and centered.',
    },
    {
      'stage_id': 'coarse',
      'stage_name': 'Coarse Coaching',
      'description': 'Fix the biggest positioning issues first.',
    },
    {
      'stage_id': 'fine',
      'stage_name': 'Fine Coaching',
      'description': 'Make micro-adjustments and stabilize.',
    },
    {
      'stage_id': 'ready',
      'stage_name': 'Ready',
      'description': 'Positioning looks good. Hold still.',
    },
  ];

  List<Map<String, Object?>> _extractStages(Map<String, Object?> rules) {
    final rawStages = rules['stages'];
    if (rawStages is! List) {
      return List<Map<String, Object?>>.from(_fallbackStages);
    }

    final List<Map<String, Object?>> stages = [];
    for (final item in rawStages) {
      if (item is Map) {
        final stageId = item['stage_id'];
        final stageName = item['stage_name'];
        if (stageId is String && stageName is String) {
          stages.add(item.cast<String, Object?>());
        }
      }
    }

    if (stages.isEmpty) {
      return List<Map<String, Object?>>.from(_fallbackStages);
    }

    return stages;
  }

  String _stageIdAt(int index) {
    final stage = _stages[index];
    final stageId = stage['stage_id'];
    return stageId is String ? stageId : 'stage_${index + 1}';
  }

  String _stageTitleAt(int index) {
    final stage = _stages[index];
    final stageName = stage['stage_name'];
    return stageName is String ? stageName : 'Stage ${index + 1}';
  }

  String _stageDescriptionAt(int index) {
    final stage = _stages[index];
    final description = stage['description'];
    if (description is String && description.trim().isNotEmpty) {
      return description;
    }
    return _stageTitleAt(index);
  }

  @override
  void initState() {
    super.initState();
    final baseUrl = const String.fromEnvironment('API_BASE_URL', defaultValue: '');
    _api = RadiobuddyApi(baseUrl: baseUrl.trim().isEmpty ? _computeDefaultApiBaseUrl() : baseUrl);

    _ttsSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  @override
  void dispose() {
    _camera?.dispose();
    if (_ttsSupported) {
      _tts.stop().catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _setStatus(GuidanceStatus status, String text) async {
    setState(() {
      _status = status;
      _statusText = text;
    });
  }

  Future<void> _speak(String text) async {
    if (!_ttsSupported) {
      return;
    }
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _loadConfigs() async {
    await _setStatus(GuidanceStatus.idle, 'Loading configs');
    try {
      final rules = await _api.fetchChestPaRules();
      final protocol = await _api.fetchChestPaExposureProtocol();
      setState(() {
        _procedureRules = rules;
        _exposureProtocol = protocol;
        _stages = _extractStages(rules);
      });
      unawaited(
        _api.postTelemetryEvent(
          eventType: 'ready_state_entered',
          procedureId: 'chest_pa',
          stageId: 'configs_loaded',
        ).catchError((_) {}),
      );
      await _setStatus(GuidanceStatus.ready, 'Configs loaded');
    } catch (e) {
      unawaited(
        _api.postTelemetryEvent(
          eventType: 'vision_low_confidence',
          procedureId: 'chest_pa',
          stageId: 'config_load_failed',
        ).catchError((_) {}),
      );
      await _setStatus(GuidanceStatus.error, 'Config load failed');
    }
  }

  Future<void> _initCamera() async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      await _setStatus(
        GuidanceStatus.error,
        'Camera not supported on this platform',
      );
      return;
    }

    await _setStatus(GuidanceStatus.loadingCamera, 'Initializing camera');
    try {
      final cameras = await availableCameras();
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(selected, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
      unawaited(
        _api.postTelemetryEvent(
          eventType: 'ready_state_entered',
          procedureId: 'chest_pa',
          stageId: 'camera_ready',
        ).catchError((_) {}),
      );
      await _setStatus(GuidanceStatus.ready, 'Camera ready');
    } catch (e) {
      await _setStatus(GuidanceStatus.error, 'Camera init failed: $e');
    }
  }

  Future<void> _startGuidance() async {
    final sessionId = _uuid.v4();
    _sessionId = sessionId;
    _stageIndex = 0;
    await _setStatus(GuidanceStatus.running, 'Guidance running');
    unawaited(
      _api.postTelemetryEvent(
        eventType: 'session_start',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: 'start',
      ).catchError((_) {}),
    );
    if (_stages.isEmpty) {
      setState(() {
        _stages = List<Map<String, Object?>>.from(_fallbackStages);
      });
    }

    final stageId = _stageIdAt(_stageIndex);
    await _speak(_stageDescriptionAt(_stageIndex));
    unawaited(
      _api.postTelemetryEvent(
        eventType: 'prompt_emitted',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: stageId,
        prompt: {
          'prompt_id': stageId,
          'spoken': true,
        },
      ).catchError((_) {}),
    );
  }

  Future<void> _nextStep() async {
    if (_status != GuidanceStatus.running) {
      return;
    }

    final sessionId = _sessionId;
    if (_stages.isEmpty) {
      setState(() {
        _stages = List<Map<String, Object?>>.from(_fallbackStages);
      });
    }

    if (_stageIndex >= _stages.length - 1) {
      await _setStatus(GuidanceStatus.ready, 'Guidance complete');
      await _speak('Guidance complete');
      unawaited(
        _api.postTelemetryEvent(
          eventType: 'session_end',
          procedureId: 'chest_pa',
          sessionId: sessionId,
          stageId: 'complete',
        ).catchError((_) {}),
      );
      _sessionId = null;
      return;
    }
    _stageIndex += 1;
    setState(() {});
    final stageId = _stageIdAt(_stageIndex);
    await _speak(_stageDescriptionAt(_stageIndex));

    unawaited(
      _api.postTelemetryEvent(
        eventType: 'prompt_emitted',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: stageId,
        prompt: {
          'prompt_id': stageId,
          'spoken': true,
        },
      ).catchError((_) {}),
    );
  }

  Future<void> _stopGuidance() async {
    if (_ttsSupported) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    await _setStatus(GuidanceStatus.ready, 'Stopped');
    final sessionId = _sessionId;
    unawaited(
      _api.postTelemetryEvent(
        eventType: 'session_end',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: 'stopped',
      ).catchError((_) {}),
    );
    _sessionId = null;
  }

  @override
  Widget build(BuildContext context) {
    final apiBaseUrl = _api.baseUrl;
    final currentStageText = (_status == GuidanceStatus.running && _stages.isNotEmpty)
        ? _stageDescriptionAt(_stageIndex)
        : null;
    final configsLoaded = _procedureRules != null && _exposureProtocol != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Buddy'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Procedure: Chest PA', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('API: $apiBaseUrl', maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _loadConfigs,
                    child: const Text('Load configs'),
                  ),
                  FilledButton(
                    onPressed: _cameraReady ? null : _initCamera,
                    child: const Text('Init camera'),
                  ),
                  FilledButton(
                    onPressed:
                        (configsLoaded && _status != GuidanceStatus.running) ? _startGuidance : null,
                    child: const Text('Start'),
                  ),
                  FilledButton(
                    onPressed: (_status == GuidanceStatus.running) ? _nextStep : null,
                    child: const Text('Next'),
                  ),
                  OutlinedButton(
                    onPressed: (_status == GuidanceStatus.running) ? _stopGuidance : null,
                    child: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Status: $_statusText'),
              if (currentStageText != null)
                Text(
                  'Stage ${_stageIndex + 1}/${_stages.length}: ${_stageTitleAt(_stageIndex)} — $currentStageText',
                ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cameraReady && _camera != null
                        ? CameraPreview(_camera!)
                        : const Center(child: Text('Camera preview')),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text(_procedureRules == null ? 'Rules: not loaded' : 'Rules: loaded')),
                  Expanded(
                    child: Text(
                      _exposureProtocol == null ? 'Protocol: not loaded' : 'Protocol: loaded',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
