import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves Flutter and its matching Dart SDK, including project-local FVM.
class SdkTools {
  const SdkTools({required this.flutter, required this.dart});

  final String flutter;
  final String dart;

  static SdkTools forProject(String directory) {
    var current = canonicalDirectory(directory);
    while (true) {
      final candidate = p.join(current, '.fvm', 'flutter_sdk', 'bin',
          Platform.isWindows ? 'flutter.bat' : 'flutter');
      if (File(candidate).existsSync()) return _fromFlutter(candidate);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    final configured = Platform.environment['FLUTTER_ROOT'];
    if (configured != null) {
      final candidate = p.join(
          configured, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter');
      if (File(candidate).existsSync()) return _fromFlutter(candidate);
    }
    for (final directory in (Platform.environment['PATH'] ?? '')
        .split(p.separator == r'\' ? ';' : ':')) {
      final candidate =
          p.join(directory, Platform.isWindows ? 'flutter.bat' : 'flutter');
      if (File(candidate).existsSync()) return _fromFlutter(candidate);
    }
    throw StateError('Flutter SDK not found. Configure FVM, FLUTTER_ROOT, '
        'or put flutter on PATH.');
  }

  static SdkTools _fromFlutter(String executable) {
    final resolved = File(executable).resolveSymbolicLinksSync();
    final dart = p.join(p.dirname(resolved), 'cache', 'dart-sdk', 'bin',
        Platform.isWindows ? 'dart.exe' : 'dart');
    if (!File(dart).existsSync()) {
      throw StateError('Dart SDK not found next to $resolved. '
          'Run flutter --version to initialize this Flutter SDK.');
    }
    return SdkTools(flutter: resolved, dart: dart);
  }
}

String canonicalDirectory(String directory) =>
    Directory(p.absolute(directory)).resolveSymbolicLinksSync();

/// The nearest package owns the default scope. A workspace root stays a scope;
/// launching from one requires choosing a Flutter member explicitly.
String projectDirectory(String directory) {
  var current = canonicalDirectory(directory);
  while (true) {
    if (File(p.join(current, 'pubspec.yaml')).existsSync()) return current;
    final parent = p.dirname(current);
    if (parent == current) return canonicalDirectory(directory);
    current = parent;
  }
}

bool containsProject(String scope, String project) =>
    p.equals(scope, project) || p.isWithin(scope, project);
