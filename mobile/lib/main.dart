import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:radiobuddy/ai/guidance_engine.dart';
import 'package:radiobuddy/ai/pose_estimator.dart';
import 'package:radiobuddy/ai/pose_metrics.dart';
import 'package:radiobuddy/exposure_selector.dart' as exposure;

import 'platform/platform.dart' as rb_platform;

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
      'platform': _platformName(),
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

  static String _platformName() {
    if (kIsWeb) {
      return 'web';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      _ => 'unknown',
    };
  }
}

class ChestPaGuidanceScreen extends StatefulWidget {
  const ChestPaGuidanceScreen({super.key});

  @override
  State<ChestPaGuidanceScreen> createState() => _ChestPaGuidanceScreenState();
}

class _ChestPaGuidanceScreenState extends State<ChestPaGuidanceScreen> {
  final _tts = FlutterTts();
  final _linuxCamera = FlutterLiteCamera();
  final _poseEstimator = createPoseEstimator();

  final _uuid = const Uuid();

  late final bool _ttsSupported;

  bool _ttsMuted = false;
  DateTime? _lastSpokenAt;
  String? _lastSpokenText;

  GuidanceStatus _status = GuidanceStatus.idle;
  String _statusText = 'Idle';
  int _stageIndex = 0;
  bool _guidanceComplete = false;

  GuidanceEngine? _guidanceEngine;
  PoseMetrics? _latestMetrics;
  Timer? _guidanceTimer;
  String? _pendingPromptId;
  DateTime? _pendingPromptSince;
  String? _lastEmittedPromptId;
  DateTime? _lastEmittedPromptAt;

  CameraController? _camera;
  bool _cameraReady = false;

  bool _linuxCameraReady = false;
  Timer? _linuxCaptureTimer;
  ui.Image? _linuxFrame;
  int _linuxFrameWidth = 0;
  int _linuxFrameHeight = 0;

  Map<String, Object?>? _procedureRules;
  Map<String, Object?>? _exposureProtocol;

  String _sizeClass = 'average';
  bool _grid = true;
  int _sidCm = 180;

  Map<String, Object?>? _selectedExposure;

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

  static const String _projectionId = 'chest_pa_erect';

  String? _stringAt(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  num? _numAt(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is num ? value : null;
  }

  void _recomputeExposureSelection() {
    final protocol = _exposureProtocol;
    if (protocol == null) {
      setState(() {
        _selectedExposure = null;
      });
      return;
    }
    final selected = exposure.selectExposureFromProtocol(
      protocol,
      projectionId: _projectionId,
      sizeClass: _sizeClass,
      grid: _grid,
      sidCm: _sidCm,
    );
    setState(() {
      _selectedExposure = selected;
    });
  }

  void _resetPromptGates() {
    _pendingPromptId = null;
    _pendingPromptSince = null;
    _lastEmittedPromptId = null;
    _lastEmittedPromptAt = null;
  }

  void _startGuidanceLoop() {
    _guidanceTimer?.cancel();
    _guidanceTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      unawaited(_tickGuidanceLoop());
    });
  }

  void _stopGuidanceLoop() {
    _guidanceTimer?.cancel();
    _guidanceTimer = null;
  }

  Future<void> _completeGuidance(String? sessionId) async {
    setState(() {
      _guidanceComplete = true;
    });
    _stopGuidanceLoop();
    await _setStatus(GuidanceStatus.ready, 'Ready');
    unawaited(
      _api.postTelemetryEvent(
        eventType: 'session_end',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: 'ready',
      ).catchError((_) {}),
    );
    _sessionId = null;
  }

  Future<void> _tickGuidanceLoop() async {
    if (_status != GuidanceStatus.running) {
      return;
    }

    final engine = _guidanceEngine;
    if (engine == null || _stages.isEmpty) {
      return;
    }

    final metrics = _latestMetrics?.toMap();
    if (metrics == null) {
      return;
    }

    final stageId = _stageIdAt(_stageIndex);
    final decision = engine.decide(stageId: stageId, metrics: metrics);
    if (decision == null) {
      return;
    }

    final now = DateTime.now();
    if (_pendingPromptId != decision.prompt.id) {
      _pendingPromptId = decision.prompt.id;
      _pendingPromptSince = now;
      return;
    }

    final pendingSince = _pendingPromptSince;
    if (pendingSince == null || now.difference(pendingSince).inMilliseconds < decision.prompt.minPersistMs) {
      return;
    }

    final lastAt = _lastEmittedPromptAt;
    final withinCooldown =
        lastAt != null && now.difference(lastAt).inMilliseconds < decision.prompt.cooldownMs;
    if (withinCooldown && _lastEmittedPromptId == decision.prompt.id) {
      return;
    }

    final spoken = await _speak(decision.prompt.tts);
    await _setStatus(GuidanceStatus.running, decision.prompt.text);
    _lastEmittedPromptId = decision.prompt.id;
    _lastEmittedPromptAt = now;

    final sessionId = _sessionId;
    final metricsPayload = <String, num>{};
    for (final entry in metrics.entries) {
      metricsPayload[entry.key] = entry.value;
    }

    unawaited(
      _api.postTelemetryEvent(
        eventType: 'prompt_emitted',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: stageId,
        prompt: {
          'prompt_id': decision.prompt.id,
          'rule_id': decision.ruleId,
          'spoken': spoken,
        },
        metrics: metricsPayload,
      ).catchError((_) {}),
    );

    if (!decision.isReadySignal) {
      return;
    }

    _resetPromptGates();
    if (_stageIndex < _stages.length - 1) {
      setState(() {
        _stageIndex += 1;
      });
      return;
    }

    await _completeGuidance(sessionId);
  }

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
    _guidanceTimer?.cancel();
    _poseEstimator.stop().catchError((_) {});
    _linuxCaptureTimer?.cancel();
    if (rb_platform.isLinux) {
      _linuxCamera.release().catchError((_) {});
    }
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

  Future<bool> _speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    if (_ttsMuted) {
      return false;
    }

    final now = DateTime.now();
    final last = _lastSpokenAt;
    const cooldown = Duration(seconds: 3);
    if (last != null && now.difference(last) < cooldown) {
      return false;
    }
    if (_lastSpokenText == trimmed && last != null && now.difference(last) < const Duration(seconds: 10)) {
      return false;
    }

    if (!_ttsSupported) {
      if (rb_platform.isLinux) {
        await rb_platform.speakSystem(trimmed);
        _lastSpokenAt = now;
        _lastSpokenText = trimmed;
        return true;
      }
      return false;
    }

    try {
      await _tts.stop();
      await _tts.speak(trimmed);
      _lastSpokenAt = now;
      _lastSpokenText = trimmed;
      return true;
    } catch (_) {
      return false;
    }
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
        _guidanceEngine = GuidanceEngine.fromProcedureRules(rules);
      });

      final sidOptions = exposure
          .sidOptionsFromProtocol(protocol, projectionId: _projectionId)
          .toList()
        ..sort();
      if (!sidOptions.contains(_sidCm)) {
        _sidCm = sidOptions.isNotEmpty ? sidOptions.first : _sidCm;
      }

      _recomputeExposureSelection();

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
    await _setStatus(GuidanceStatus.loadingCamera, 'Initializing camera');

    if (kIsWeb) {
      await _setStatus(GuidanceStatus.error, 'Camera not supported on this platform');
      return;
    }

    if (rb_platform.isLinux) {
      try {
        final devices = await _linuxCamera.getDeviceList();
        if (devices.isEmpty) {
          await _setStatus(GuidanceStatus.error, 'No camera devices found');
          return;
        }

        final opened = await _linuxCamera.open(0);
        if (!opened) {
          await _setStatus(GuidanceStatus.error, 'Failed to open camera');
          return;
        }

        setState(() {
          _linuxCameraReady = true;
          _cameraReady = true;
        });

        _linuxCaptureTimer?.cancel();
        _linuxCaptureTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
          unawaited(_captureLinuxFrame());
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
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      await _setStatus(GuidanceStatus.error, 'Camera not supported on this platform');
      return;
    }

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

      await _poseEstimator.start(
        controller: controller,
        onMetrics: (metrics) {
          if (!mounted) {
            return;
          }
          setState(() {
            _latestMetrics = metrics;
            _sizeClass = metrics.sizeClass;
          });
          _recomputeExposureSelection();
          unawaited(
            _api.postTelemetryEvent(
              eventType: 'habitus_estimated',
              procedureId: 'chest_pa',
              sessionId: _sessionId,
              stageId: _stages.isNotEmpty ? _stageIdAt(_stageIndex) : null,
              metrics: metrics.toMap(),
            ).catchError((_) {}),
          );
        },
      );

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

  Future<void> _captureLinuxFrame() async {
    if (!rb_platform.isLinux || !_linuxCameraReady) {
      return;
    }

    try {
      final frame = await _linuxCamera.captureFrame();
      final width = frame['width'];
      final height = frame['height'];
      final data = frame['data'];

      if (width is! int || height is! int || data is! Uint8List) {
        return;
      }

      final rgba = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        final r = data[i * 3];
        final g = data[i * 3 + 1];
        final b = data[i * 3 + 2];
        rgba[i * 4] = b;
        rgba[i * 4 + 1] = g;
        rgba[i * 4 + 2] = r;
        rgba[i * 4 + 3] = 255;
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (!mounted) {
        return;
      }

      setState(() {
        _linuxFrame?.dispose();
        _linuxFrame = image;
        _linuxFrameWidth = width;
        _linuxFrameHeight = height;
      });
    } catch (_) {}
  }

  Future<void> _startGuidance() async {
    final sessionId = _uuid.v4();
    _sessionId = sessionId;
    _stageIndex = 0;
    _guidanceComplete = false;
    _resetPromptGates();
    await _setStatus(GuidanceStatus.running, 'Guidance running');
    _startGuidanceLoop();
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

    if (_guidanceEngine == null) {
      final stageId = _stageIdAt(_stageIndex);
      final spoken = await _speak(_stageDescriptionAt(_stageIndex));
      unawaited(
        _api.postTelemetryEvent(
          eventType: 'prompt_emitted',
          procedureId: 'chest_pa',
          sessionId: sessionId,
          stageId: stageId,
          prompt: {
            'prompt_id': stageId,
            'spoken': spoken,
          },
        ).catchError((_) {}),
      );
    }
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
      await _completeGuidance(_sessionId);
      return;
    }

    _stageIndex += 1;
    _resetPromptGates();
    setState(() {});
    final stageId = _stageIdAt(_stageIndex);
    final spoken = await _speak(_stageDescriptionAt(_stageIndex));

    unawaited(
      _api.postTelemetryEvent(
        eventType: 'prompt_emitted',
        procedureId: 'chest_pa',
        sessionId: sessionId,
        stageId: stageId,
        prompt: {
          'prompt_id': stageId,
          'spoken': spoken,
        },
      ).catchError((_) {}),
    );

    if (_stageIndex >= _stages.length - 1) {
      await _completeGuidance(sessionId);
    }
  }

  Future<void> _stopGuidance() async {
    _stopGuidanceLoop();
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
    setState(() {
      _guidanceComplete = false;
    });
    _resetPromptGates();
  }

  @override
  Widget build(BuildContext context) {
    final apiBaseUrl = _api.baseUrl;
    final currentStageText = (_status == GuidanceStatus.running && _stages.isNotEmpty)
        ? _stageDescriptionAt(_stageIndex)
        : null;
    final configsLoaded = _procedureRules != null && _exposureProtocol != null;
    final requiresCameraForStart = !kIsWeb && (rb_platform.isAndroid || rb_platform.isIOS);
    final showManualChecklist = !configsLoaded || _status == GuidanceStatus.error;

    final exposureProtocol = _exposureProtocol;
    final exposureName = exposureProtocol != null ? _stringAt(exposureProtocol, 'protocol_name') : null;
    final exposureAssumptions = exposureProtocol != null && exposureProtocol['assumptions'] is List
      ? (exposureProtocol['assumptions'] as List).whereType<String>().toList(growable: false)
      : const <String>[];
    final sidOptions = exposureProtocol != null
      ? (exposure.sidOptionsFromProtocol(exposureProtocol, projectionId: _projectionId).toList()..sort())
      : const <int>[];
    final selectedKvp = _selectedExposure != null ? _numAt(_selectedExposure!, 'kvp') : null;
    final selectedMas = _selectedExposure != null ? _numAt(_selectedExposure!, 'mas') : null;
    final selectedNotes = _selectedExposure != null ? _stringAt(_selectedExposure!, 'notes') : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Buddy'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ListView(
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
                        (configsLoaded && _status != GuidanceStatus.running && (!requiresCameraForStart || _cameraReady))
                            ? _startGuidance
                            : null,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Mute'),
                      Switch(
                        value: _ttsMuted,
                        onChanged: (value) {
                          setState(() {
                            _ttsMuted = value;
                          });
                          if (value && _ttsSupported) {
                            _tts.stop().catchError((_) {});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Status: $_statusText'),
              Text(
                _poseEstimator.supported
                    ? (_latestMetrics == null
                        ? 'AI: waiting for pose metrics'
                        : 'AI: pose ${(_latestMetrics!.poseConfidence * 100).toStringAsFixed(0)}%')
                    : 'AI: on-device pose not supported on this platform',
              ),
              if (currentStageText != null)
                Text(
                  'Stage ${_stageIndex + 1}/${_stages.length}: ${_stageTitleAt(_stageIndex)} — $currentStageText',
                ),
              if (showManualChecklist) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Manual checklist:\n'
                    '1) Full torso in frame\n'
                    '2) Center patient to detector\n'
                    '3) Reduce rotation/tilt\n'
                    '4) Improve lighting / step back\n'
                    '5) Shoulders rolled forward\n'
                    '6) Chin up',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
              if (_guidanceComplete) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.primary),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Ready', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      if (selectedKvp != null && selectedMas != null)
                        Text(
                          '${selectedKvp.toString()} kVp / ${selectedMas.toString()} mAs',
                          style: Theme.of(context).textTheme.titleLarge,
                        )
                      else
                        Text('No technique match', style: Theme.of(context).textTheme.titleLarge),
                      if (selectedNotes != null && selectedNotes.trim().isNotEmpty)
                        Text(selectedNotes, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Exposure', style: Theme.of(context).textTheme.titleMedium),
                    if (exposureName != null) Text(exposureName, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            initialValue: _sizeClass,
                            items: const [
                              DropdownMenuItem(value: 'small', child: Text('Small')),
                              DropdownMenuItem(value: 'average', child: Text('Average')),
                              DropdownMenuItem(value: 'large', child: Text('Large')),
                            ],
                            onChanged: configsLoaded
                                ? (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _sizeClass = value;
                                    });
                                    _recomputeExposureSelection();
                                  }
                                : null,
                            decoration: const InputDecoration(labelText: 'Size class'),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Grid'),
                            Switch(
                              value: _grid,
                              onChanged: configsLoaded
                                  ? (value) {
                                      setState(() {
                                        _grid = value;
                                      });
                                      _recomputeExposureSelection();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        if (sidOptions.isNotEmpty)
                          SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<int>(
                              initialValue: sidOptions.contains(_sidCm) ? _sidCm : sidOptions.first,
                              items: [
                                for (final sid in sidOptions)
                                  DropdownMenuItem(value: sid, child: Text('${sid}cm')),
                              ],
                              onChanged: configsLoaded
                                  ? (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setState(() {
                                        _sidCm = value;
                                      });
                                      _recomputeExposureSelection();
                                    }
                                  : null,
                              decoration: const InputDecoration(labelText: 'SID'),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (selectedKvp != null && selectedMas != null)
                      Text(
                        'Suggested starting technique: ${selectedKvp.toString()} kVp / ${selectedMas.toString()} mAs',
                        style: Theme.of(context).textTheme.titleSmall,
                      )
                    else
                      const Text('Suggested starting technique: —'),
                    if (selectedNotes != null && selectedNotes.trim().isNotEmpty)
                      Text(selectedNotes, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (exposureAssumptions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        exposureAssumptions.first,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Limitations: starting technique per protocol only. Follow local policy. No PHI. Do not rely on this tool for clinical judgment.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 320,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cameraReady && _camera != null
                        ? CameraPreview(_camera!)
                        : (_linuxFrame != null && _linuxFrameWidth > 0 && _linuxFrameHeight > 0)
                            ? FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: _linuxFrameWidth.toDouble(),
                                  height: _linuxFrameHeight.toDouble(),
                                  child: RawImage(image: _linuxFrame),
                                ),
                              )
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
