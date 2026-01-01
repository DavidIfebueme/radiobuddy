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

  GuidanceStatus _status = GuidanceStatus.idle;
  String _statusText = 'Idle';
  int _stepIndex = 0;

  CameraController? _camera;
  bool _cameraReady = false;

  Map<String, Object?>? _procedureRules;
  Map<String, Object?>? _exposureProtocol;

  late final RadiobuddyApi _api;

  String? _sessionId;

  final List<String> _steps = const [
    'Confirm patient is erect and centered.',
    'Set SID and align central ray to T7.',
    'Ensure scapulae are rotated out of lung fields.',
    'Collimate to lung fields and check rotation.',
    'Instruct deep inspiration and expose.',
  ];

  @override
  void initState() {
    super.initState();
    final baseUrl = const String.fromEnvironment('API_BASE_URL', defaultValue: '');
    _api = RadiobuddyApi(baseUrl: baseUrl.trim().isEmpty ? _computeDefaultApiBaseUrl() : baseUrl);
  }

  @override
  void dispose() {
    _camera?.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _setStatus(GuidanceStatus status, String text) async {
    setState(() {
      _status = status;
      _statusText = text;
    });
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _loadConfigs() async {
    await _setStatus(_status, 'Loading configs');
    try {
      final rules = await _api.fetchChestPaRules();
      final protocol = await _api.fetchChestPaExposureProtocol();
      setState(() {
        _procedureRules = rules;
        _exposureProtocol = protocol;
      });
      unawaited(
        _api.postTelemetryEvent(
          eventType: 'ready_state_entered',
          procedureId: 'chest_pa',
          stageId: 'configs_loaded',
        ).catchError((_) {}),
      );
      await _setStatus(_status, 'Configs loaded');
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
    _stepIndex = 0;
    await _setStatus(GuidanceStatus.running, 'Guidance running');
    unawaited(
      _api.postTelemetryEvent(
        eventType: 'session_start',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: 'start',
      ).catchError((_) {}),
    );
    await _speak(_steps[_stepIndex]);
    unawaited(
      _api.postTelemetryEvent(
        eventType: 'prompt_emitted',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: 'step_1',
        prompt: {
          'prompt_id': 'step_1',
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
    if (_stepIndex >= _steps.length - 1) {
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
    _stepIndex += 1;
    setState(() {});
    await _speak(_steps[_stepIndex]);

    unawaited(
      _api.postTelemetryEvent(
        eventType: 'prompt_emitted',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: 'step_${_stepIndex + 1}',
        prompt: {
          'prompt_id': 'step_${_stepIndex + 1}',
          'spoken': true,
        },
      ).catchError((_) {}),
    );
  }

  Future<void> _stopGuidance() async {
    await _tts.stop();
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
    final currentStep = (_status == GuidanceStatus.running) ? _steps[_stepIndex] : null;

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
                    onPressed: _cameraReady ? _startGuidance : null,
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
              if (currentStep != null) Text('Step ${_stepIndex + 1}/${_steps.length}: $currentStep'),
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
