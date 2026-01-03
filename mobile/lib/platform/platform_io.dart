import 'dart:io';

bool get isLinux => Platform.isLinux;
bool get isAndroid => Platform.isAndroid;
bool get isIOS => Platform.isIOS;

Future<void> speakSystem(String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return;
  }

  if (await _tryRun('spd-say', [trimmed])) {
    return;
  }
  await _tryRun('espeak', [trimmed]);
}

Future<bool> _tryRun(String command, List<String> args) async {
  try {
    final result = await Process.run(command, args);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
