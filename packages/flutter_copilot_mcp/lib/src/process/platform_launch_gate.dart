import 'dart:async';

/// Groups Flutter `targetPlatform` values that share one build directory.
///
/// Two Android devices both write `build/app/outputs/flutter-apk`. Two iOS
/// devices share `build/ios`. A macOS run uses `build/macos`. Launches in
/// different families do not touch the same artifact.
String platformFamily(String targetPlatform) {
  final platform = targetPlatform.trim().toLowerCase();
  if (platform.startsWith('android')) return 'android';
  if (platform == 'ios') return 'ios';
  if (platform == 'darwin') return 'macos';
  if (platform.startsWith('windows')) return 'windows';
  if (platform.startsWith('linux')) return 'linux';
  if (platform.startsWith('web')) return 'web';
  if (platform.isEmpty) return 'unknown';
  return platform;
}

/// Runs work for one platform family at a time.
///
/// The next call waits until the previous future completes, including when
/// that future completes with an error. Different families run together.
class PlatformLaunchGate {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(String family, Future<T> Function() action) {
    final key = family.trim().isEmpty ? 'unknown' : family;
    final previous = _tails[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _tails[key] = gate.future;
    final result = previous.onError((Object error, StackTrace stackTrace) {
      return Future<void>.value();
    }).then((_) {
      return action();
    });
    result.whenComplete(gate.complete).ignore();
    return result;
  }
}
