#!/usr/bin/env dart
//
// Unified version tool for the flutter_copilot workspace.
//
// Usage:
//   dart tool/version.dart                  # CI gate: verify 3 packages aligned
//                                            # + regenerate version.g.dart /
//                                            # version.generated.ts (idempotent)
//   dart tool/version.dart --set 1.0.4      # bump 3 packages to 1.0.4, then
//                                            # regenerate
//   dart tool/version.dart --check          # like default, but also exits 1
//                                            # if regeneration would change the
//                                            # generated files (CI-safe)
//   dart tool/version.dart --print          # print current shared version only
//   dart tool/version.dart -h | --help      # this help
//
// Exit codes:
//   0  OK
//   1  version mismatch / invalid semver / regenerated drift (--check mode)
//   64 bad usage
//
// Design:
//   - `version.g.dart` (Dart, for flutter_copilot_mcp) and
//     `version.generated.ts` (TS, for flutter_copilot_cli) are always derived
//     from the 3 source-of-truth manifests. This tool is the only thing that
//     writes them.
//   - In --set mode, the 3 manifests are edited in-place with a surgical regex
//     that only touches the `version:` line (YAML) / top-level `"version"`
//     key (JSON). No other formatting/keys are disturbed.
//   - If `--set` fails partway, any already-written manifest is rolled back
//     from its `.bak` sibling.

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

// ---------- Paths ----------
//
// Paths resolved relative to the repo root — i.e. the directory that contains
// `tool/`. We derive that from `Platform.script` so the tool works regardless
// of the caller's cwd (`dart tool/version.dart` from repo root, `dart
// version.dart` from inside `tool/`, or a symlink — all fine).

final String _repoRoot = _findRepoRoot();

String _p(String rel) => '$_repoRoot/$rel';

String get _clawPubspecPath => _p('packages/flutter_copilot_claw/pubspec.yaml');
String get _mcpPubspecPath => _p('packages/flutter_copilot_mcp/pubspec.yaml');
String get _cliPackageJsonPath => _p('packages/flutter_copilot_cli/package.json');
String get _dartOutputPath =>
    _p('packages/flutter_copilot_mcp/lib/src/version.g.dart');
String get _tsOutputPath =>
    _p('packages/flutter_copilot_cli/src/version.generated.ts');

/// Walks up from `Platform.script` looking for a directory that contains a
/// `tool/version.dart` and `packages/` — that's the workspace root. Falls back
/// to the script's grandparent (standard layout) if the walk finds nothing.
String _findRepoRoot() {
  var dir = File.fromUri(Platform.script).parent; // .../tool
  dir = dir.parent; // .../<repo>
  // Safety: if somebody moved the script, walk up until we find our markers.
  var probe = dir;
  for (var i = 0; i < 6; i++) {
    final hasTool = Directory('${probe.path}/tool').existsSync();
    final hasPackages = Directory('${probe.path}/packages').existsSync();
    if (hasTool && hasPackages) return probe.path;
    final parent = probe.parent;
    if (parent.path == probe.path) break;
    probe = parent;
  }
  return dir.path;
}

// ---------- Entry ----------

void main(List<String> args) {
  String? setVersion;
  bool checkMode = false;
  bool printMode = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      case '--set':
        if (i + 1 >= args.length) {
          _fatal('--set requires a version argument (e.g. --set 1.0.4)', 64);
        }
        setVersion = args[++i];
      case '--check':
        checkMode = true;
      case '--print':
        printMode = true;
      default:
        _fatal('Unknown option: $a', 64);
    }
  }

  if (setVersion != null && checkMode) {
    _fatal('--set and --check are mutually exclusive.', 64);
  }
  if (printMode && (setVersion != null || checkMode)) {
    _fatal('--print cannot be combined with --set or --check.', 64);
  }

  if (setVersion != null) {
    _bumpAll(setVersion);
    print('');
  }

  // Read current versions (always, so we verify alignment post-bump too).
  final mcpVersion = _readYamlVersion(_mcpPubspecPath);
  final clawVersion = _readYamlVersion(_clawPubspecPath);
  final cliVersion = _readJsonVersion(_cliPackageJsonPath);

  if (printMode) {
    // If aligned, print the single version; otherwise print each on its own line.
    final distinct = {mcpVersion, clawVersion, cliVersion};
    if (distinct.length == 1) {
      stdout.writeln(distinct.first);
    } else {
      stdout.writeln('flutter_copilot_claw=$clawVersion');
      stdout.writeln('flutter_copilot_mcp=$mcpVersion');
      stdout.writeln('flutter_copilot_cli=$cliVersion');
      exit(1);
    }
    return;
  }

  print('flutter_copilot_claw version: $clawVersion');
  print('flutter_copilot_mcp  version: $mcpVersion');
  print('flutter_copilot_cli  version: $cliVersion');

  // Alignment check.
  final byPkg = <String, String>{
    'flutter_copilot_claw': clawVersion,
    'flutter_copilot_mcp': mcpVersion,
    'flutter_copilot_cli': cliVersion,
  };
  if (byPkg.values.toSet().length > 1) {
    stderr.writeln(
      'ERROR: Version mismatch!\n'
      '${byPkg.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
      'All three packages must share the same version.\n'
      'Run: dart tool/version.dart --set <version>',
    );
    exit(1);
  }

  if (!_isValidSemver(mcpVersion)) {
    _fatal(
      'Invalid version format: $mcpVersion\n'
      'Version must follow semver (e.g., 1.0.0, 0.2.3, 1.2.3-beta).',
      1,
    );
  }

  // Regenerate derived files.
  final dartContent = _renderDart(mcpVersion);
  final tsContent = _renderTs(cliVersion);

  if (checkMode) {
    final dartCurrent = _readFileOrEmpty(_dartOutputPath);
    final tsCurrent = _readFileOrEmpty(_tsOutputPath);
    var drift = false;
    if (dartCurrent != dartContent) {
      stderr.writeln('drift: $_dartOutputPath is stale.');
      drift = true;
    }
    if (tsCurrent != tsContent) {
      stderr.writeln('drift: $_tsOutputPath is stale.');
      drift = true;
    }
    if (drift) {
      stderr.writeln('Run: dart tool/version.dart');
      exit(1);
    }
    print('✓ version files up to date.');
    return;
  }

  _writeFile(_dartOutputPath, dartContent);
  print('Generated $_dartOutputPath (v$mcpVersion)');
  _writeFile(_tsOutputPath, tsContent);
  print('Generated $_tsOutputPath (v$cliVersion)');
}

// ---------- Bump ----------

/// Writes [version] into the three manifest files. Validates semver first,
/// backs up each file to `.bak`, rolls back all if any write/verify fails.
void _bumpAll(String version) {
  if (!_isValidSemver(version)) {
    _fatal(
      "'$version' is not a valid semver (e.g. 1.0.4 or 1.0.0-beta.1).",
      65,
    );
  }

  print('Bumping all 3 packages → $version');

  final files = [_clawPubspecPath, _mcpPubspecPath, _cliPackageJsonPath];
  // Ensure all files exist before we start writing anywhere.
  for (final p in files) {
    if (!File(p).existsSync()) _fatal('Not found: $p', 66);
  }

  final backups = <String, String>{}; // path → backup path
  try {
    for (final p in files) {
      final bak = '$p.bak';
      File(p).copySync(bak);
      backups[p] = bak;
    }

    _writeYamlVersion(_clawPubspecPath, version);
    _writeYamlVersion(_mcpPubspecPath, version);
    _writeJsonVersion(_cliPackageJsonPath, version);

    // Post-write verification: the new version must actually be readable back.
    final actualClaw = _readYamlVersion(_clawPubspecPath);
    final actualMcp = _readYamlVersion(_mcpPubspecPath);
    final actualCli = _readJsonVersion(_cliPackageJsonPath);
    if (actualClaw != version ||
        actualMcp != version ||
        actualCli != version) {
      throw StateError(
        'Post-write verify failed: '
        'claw=$actualClaw mcp=$actualMcp cli=$actualCli (expected $version)',
      );
    }

    // Success: delete backups.
    for (final bak in backups.values) {
      File(bak).deleteSync();
    }

    print('  ✓ $_clawPubspecPath');
    print('  ✓ $_mcpPubspecPath');
    print('  ✓ $_cliPackageJsonPath');
  } catch (e) {
    // Roll back any written files.
    for (final entry in backups.entries) {
      try {
        if (File(entry.value).existsSync()) {
          File(entry.value).copySync(entry.key);
          File(entry.value).deleteSync();
        }
      } catch (_) {
        // best-effort
      }
    }
    _fatal('Bump failed; rolled back. Cause: $e', 1);
  }
}

/// Replaces the top-level `version:` line of [path] with `version: $v`.
///
/// Uses a line-anchored regex that matches at most once — additional
/// `version:`-like strings inside block scalars or comments are not touched.
void _writeYamlVersion(String path, String v) {
  final file = File(path);
  final src = file.readAsStringSync();
  final re = RegExp(r'^version:[ \t]+.*$', multiLine: true);
  final match = re.firstMatch(src);
  if (match == null) {
    throw StateError('No top-level `version:` line found in $path');
  }
  final replaced = src.replaceRange(match.start, match.end, 'version: $v');
  file.writeAsStringSync(replaced);
}

/// Replaces the top-level `"version": "X"` of a package.json.
///
/// Matches the conventional 2-space-indented `  "version": "…",` line only,
/// to avoid nested `"version"` strings inside e.g. dependency ranges.
void _writeJsonVersion(String path, String v) {
  final file = File(path);
  final src = file.readAsStringSync();
  final re = RegExp(r'^(  "version":[ \t]*")([^"]+)(",?)$', multiLine: true);
  final match = re.firstMatch(src);
  if (match == null) {
    throw StateError('No top-level `"version"` line found in $path');
  }
  final replaced = src.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}$v${match.group(3)}',
  );
  file.writeAsStringSync(replaced);
}

// ---------- Read helpers ----------

String _readYamlVersion(String path) {
  final file = File(path);
  if (!file.existsSync()) _fatal('File not found: $path', 1);
  try {
    final yaml = loadYaml(file.readAsStringSync()) as Map;
    final v = yaml['version']?.toString();
    if (v == null || v.isEmpty) _fatal('Empty/missing version in $path', 1);
    return v;
  } on YamlException catch (e) {
    _fatal('Failed to parse YAML in $path: $e', 1);
  }
}

String _readJsonVersion(String path) {
  final file = File(path);
  if (!file.existsSync()) _fatal('File not found: $path', 1);
  try {
    final parsed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final v = parsed['version']?.toString();
    if (v == null || v.isEmpty) _fatal('Empty/missing version in $path', 1);
    return v;
  } on FormatException catch (e) {
    _fatal('Failed to parse JSON in $path: $e', 1);
  }
}

String _readFileOrEmpty(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync() : '';
}

void _writeFile(String path, String content) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

// ---------- Templates ----------

String _renderDart(String v) =>
    '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
    '// Generated by tool/version.dart\n'
    '\n'
    "const version = '$v';\n";

String _renderTs(String v) =>
    '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
    '// Generated by tool/version.dart\n'
    '\n'
    "export const VERSION = '$v';\n";

// ---------- Misc ----------

bool _isValidSemver(String v) {
  final re = RegExp(
    r'^\d+\.\d+\.\d+(-[0-9A-Za-z\-\.]+)?(\+[0-9A-Za-z\-\.]+)?$',
  );
  return re.hasMatch(v);
}

Never _fatal(String msg, int code) {
  stderr.writeln('ERROR: $msg');
  exit(code);
}

void _printUsage() {
  stdout.writeln('''
Unified version tool for the flutter_copilot workspace.

Usage:
  dart tool/version.dart                 verify 3 packages aligned + regenerate
  dart tool/version.dart --set 1.0.4     bump 3 packages, then regenerate
  dart tool/version.dart --check         like default, but exit 1 on drift (CI)
  dart tool/version.dart --print         print current shared version only
  dart tool/version.dart -h, --help      show this help

The three source-of-truth manifests:
  $_clawPubspecPath
  $_mcpPubspecPath
  $_cliPackageJsonPath

The two generated files (this tool is the only writer):
  $_dartOutputPath
  $_tsOutputPath
''');
}
