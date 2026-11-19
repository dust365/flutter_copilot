import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/process/launch_args.dart';
import 'package:flutter_copilot_mcp/src/process/machine_output.dart';
import 'package:flutter_copilot_mcp/src/process/platform_launch_gate.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';
import 'package:path/path.dart' as p;

/// A resident Flutter machine-protocol process. Stop and detach are distinct.
class TrackedFlutterRun implements OwnedProcess {
  TrackedFlutterRun(
      {required this.process, required this.deviceId, required this.id});
  final Process process;
  @override
  final String deviceId;
  @override
  String id;
  final List<String> _lines = [];
  final Map<int, Completer<dynamic>> _requests = {};
  int _nextRequest = 0;
  String? appId;
  String? wsUri;
  String? dtdUri;
  AppSession? session;
  bool started = false;
  bool _stopped = false;

  @override
  bool get isRunning => !_stopped;

  void addLine(String line) {
    _lines.add(line);
    if (_lines.length > 500) _lines.removeAt(0);
    final parsed = parseMachineLine(line);
    wsUri ??= parsed?.wsUri;
    dtdUri ??= parsed?.dtdUri;
    for (final event in machineMessages(line)) {
      final params = event['params'];
      if (params is Map && params['appId'] is String)
        appId = params['appId'] as String;
      if (event['event'] == 'app.started') started = true;
      final request = _requests.remove(event['id']);
      if (request != null) {
        if (event.containsKey('error')) {
          request.completeError(StateError('${event['error']}'));
        } else {
          request.complete(event['result']);
        }
      }
    }
  }

  Future<dynamic> command(String method) async {
    if (appId == null || !isRunning)
      throw StateError('Flutter run is not ready');
    final id = _nextRequest++;
    final completer = Completer<dynamic>();
    _requests[id] = completer;
    process.stdin.writeln(jsonEncode([
      {
        'id': id,
        'method': method,
        'params': {'appId': appId},
      }
    ]));
    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      _requests.remove(id);
    }
  }

  void exited() {
    _stopped = true;
    for (final request in _requests.values) {
      request.completeError(StateError('Flutter run exited'));
    }
    _requests.clear();
  }

  @override
  String logTail({int lines = 500}) {
    if (_lines.isEmpty) return 'No flutter run output yet.';
    return _lines
        .skip(_lines.length > lines ? _lines.length - lines : 0)
        .join('\n');
  }

  Future<void> _end({required bool detach}) async {
    if (_stopped) return;
    if (appId != null) {
      // Never fall back to a kill when detach fails: that could stop the app.
      final result = await command(detach ? 'app.detach' : 'app.stop');
      if (result != true)
        throw StateError('Flutter refused ${detach ? 'detach' : 'stop'}');
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // A detach already succeeded, so the App is no longer ours. Rethrowing
        // here would leave this run marked as running and let a later stop
        // target an App that was detached.
        if (!detach) process.kill();
      }
    } else {
      process.kill();
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      if (!detach) process.kill(ProcessSignal.sigkill);
    }
    _stopped = true;
  }

  @override
  Future<void> stop() => _end(detach: false);
  Future<void> detach() => _end(detach: true);
}

/// Owns Flutter processes independently of the MCP or CLI client lifetime.
class FlutterRunManager {
  FlutterRunManager(
      {required this.apps, required this.dtds, this.sdk, this.identifyAndroid});
  final AppDirectory apps;
  final DtdRegistry dtds;
  final SdkTools? sdk;
  final Future<String?> Function(String id)? identifyAndroid;
  final Map<String, TrackedFlutterRun> _runs = {};
  final PlatformLaunchGate _gates = PlatformLaunchGate();
  bool _closed = false;

  Future<List<FlutterDevice>> listDevices({String? directory}) async {
    final root = directory ?? Directory.current.path;
    final tools = sdk ?? SdkTools.forProject(root);
    final result = await Process.run(tools.flutter, ['devices', '--machine'],
            workingDirectory: root)
        .timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw StateError('flutter devices failed: ${result.stderr}');
    }
    final devices = parseFlutterDevices(result.stdout as String);
    final supported = devices.where((device) {
      final family = platformFamily(device.targetPlatform);
      return device.supported && Directory(p.join(root, family)).existsSync();
    }).toList();
    final identities = <String, String>{};
    await Future.wait(supported
        .where((d) => !d.emulator && d.targetPlatform.startsWith('android'))
        .map((device) async {
      final serial = await (identifyAndroid ?? _androidSerial)(device.id);
      if (serial != null) identities[device.id] = serial;
    }));
    return mergeDeviceTransports(supported, identities);
  }

  Future<String?> _androidSerial(String id) async {
    final home = Platform.environment['ANDROID_SDK_ROOT'] ??
        Platform.environment['ANDROID_HOME'];
    final adb = home == null
        ? 'adb'
        : p.join(
            home, 'platform-tools', Platform.isWindows ? 'adb.exe' : 'adb');
    try {
      final result =
          await Process.run(adb, ['-s', id, 'shell', 'getprop', 'ro.serialno'])
              .timeout(const Duration(seconds: 3));
      final serial = (result.stdout as String).trim();
      if (result.exitCode == 0 &&
          RegExp(r'^[a-zA-Z0-9_.:-]{4,}$').hasMatch(serial) &&
          serial != 'unknown') return serial;
    } catch (_) {/* Keep transports separate if identity cannot be verified. */}
    return null;
  }

  Future<String> launch(
      {required String directory,
      String? deviceId,
      String? name,
      String? target,
      int timeoutSeconds = 180,
      List<String> extraArgs = const []}) async {
    final session = await start(
        directory: directory,
        deviceId: deviceId,
        name: name,
        target: target,
        timeoutSeconds: timeoutSeconds,
        extraArgs: extraArgs);
    return 'Started ${session.describe()}';
  }

  Future<AppSession> start(
      {required String directory,
      String? deviceId,
      String? name,
      String? target,
      int timeoutSeconds = 180,
      List<String> extraArgs = const []}) async {
    if (timeoutSeconds <= 0)
      throw LaunchArgsException('timeout must be positive');
    validateLaunchArgs(extraArgs);
    final root = canonicalDirectory(directory);
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      throw LaunchArgsException('Not a Flutter package: $root');
    }
    final devices = await listDevices(directory: root);
    final matches =
        devices.where((d) => deviceId == null || d.matches(deviceId)).toList();
    if (matches.length != 1) {
      throw LaunchArgsException(
          'Select a supported device.\n${formatFlutterDevices(devices)}');
    }
    // Generated sources and .dart_tool can be shared across platforms too.
    return _gates.run(
        root,
        () => _startResolved(
            root, matches.single, name, target, timeoutSeconds, extraArgs));
  }

  Future<AppSession> _startResolved(String root, FlutterDevice device,
      String? name, String? target, int timeout, List<String> extraArgs) async {
    final existing =
        _runs.values.where((run) => run.deviceId == device.id && run.isRunning);
    if (existing.isNotEmpty)
      throw LaunchArgsException(
          'A Flutter run already owns ${device.id}. Use its app id or stop it first.');
    // Cross-process lock protects the same package even across backend versions.
    final lockFile =
        File(p.join(root, '.dart_tool', 'flutter_copilot', 'build.lock'));
    await lockFile.parent.create(recursive: true);
    final lock = await lockFile.open(mode: FileMode.append);
    await lock.lock(FileLock.blockingExclusive);
    try {
      return await _spawn(root, device, name, target, timeout, extraArgs);
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<AppSession> _spawn(String root, FlutterDevice device, String? name,
      String? target, int timeout, List<String> extraArgs) async {
    if (_closed) throw StateError('Flutter run manager is closed');
    final tools = sdk ?? SdkTools.forProject(root);
    final process = await Process.start(
        tools.flutter,
        [
          'run',
          '--machine',
          '--device-id',
          device.id,
          if (target != null) ...['--target', target],
          ...extraArgs,
        ],
        workingDirectory: root);
    final run = TrackedFlutterRun(
        process: process,
        deviceId: device.id,
        id: name?.trim().isNotEmpty == true ? name!.trim() : device.id);
    final ready = Completer<void>();
    final streams = <StreamSubscription<String>>[];
    void line(String line) {
      run.addLine(line);
      if (run.wsUri != null && run.started && !ready.isCompleted)
        ready.complete();
    }

    streams.add(process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(line));
    streams.add(process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(line));
    own(run);
    unawaited(process.exitCode.then((code) async {
      run.exited();
      if (identical(_runs[run.id], run)) _runs.remove(run.id);
      if (!ready.isCompleted)
        ready.completeError(StateError(
            'flutter run exited ($code) before readiness.\n${run.logTail()}'));
      for (final subscription in streams) {
        await subscription.cancel();
      }
    }));
    try {
      await ready.future.timeout(Duration(seconds: timeout));
      final session = await apps.connectUri(
          uri: run.wsUri!,
          id: run.id,
          deviceId: device.id,
          projectRoot: root,
          target: Uri.file(p.normalize(p.join(root, target ?? 'lib/main.dart')))
              .toString(),
          process: run,
          waitForExtension: const Duration(seconds: 20),
          flavor: _value(extraArgs, '--flavor'),
          mode: extraArgs.contains('--profile') ? 'profile' : 'debug',
          launchArgs: List.of(extraArgs));
      _runs.remove(run.id);
      run.id = session.id;
      run.session = session;
      own(run);
      return session;
    } catch (_) {
      await run.stop();
      rethrow;
    }
  }

  String? _value(List<String> args, String flag) {
    for (var i = 0; i < args.length; i++) {
      if (args[i].startsWith('$flag='))
        return args[i].substring(flag.length + 1);
      if (args[i] == flag && i + 1 < args.length) return args[i + 1];
    }
    return null;
  }

  Future<String> stop(String? app, {bool detach = false}) async {
    final run = _select(app);
    if (detach) {
      await run.detach();
    } else {
      await run.stop();
    }
    _runs.remove(run.id);
    for (final session
        in apps.sessions.where((s) => identical(s.process, run)).toList()) {
      await apps.removeSession(session);
    }
    return '${detach ? 'Detached from' : 'Stopped'} ${run.id}.';
  }

  String logs(String? app, {int lines = 500}) =>
      _select(app).logTail(lines: lines <= 0 ? 500 : lines);

  TrackedFlutterRun? ownedById(String? id) {
    final run = _runs[id];
    return run != null && run.isRunning ? run : null;
  }

  TrackedFlutterRun? ownedByUri(String uri) {
    final normalized = normalizeVmServiceUri(uri);
    return _runs.values
        .where((run) => run.isRunning && run.session?.uri == normalized)
        .firstOrNull;
  }

  Future<AppSession> reconnect(TrackedFlutterRun run) async {
    final previous = run.session!;
    final session = await apps.connectUri(
      uri: previous.uri,
      id: previous.id,
      deviceId: previous.deviceId,
      dtdUri: previous.dtdUri,
      process: run,
      projectRoot: previous.projectRoot,
      target: previous.target,
      displayName: previous.displayName,
      flavor: previous.flavor,
      mode: previous.mode,
      launchArgs: previous.launchArgs,
      waitForExtension: const Duration(seconds: 5),
    );
    if (!apps.sessions.any(
        (other) => !identical(other, session) && other.id == previous.id)) {
      session.id = previous.id;
    }
    run.session = session;
    return session;
  }

  void own(TrackedFlutterRun run) {
    _runs[run.id] = run;
  }

  bool get hasRunning => _runs.values.any((run) => run.isRunning);

  Future<void> close() async {
    _closed = true;
    final runs = _runs.values.toList();
    for (final run in runs) {
      await run.stop();
    }
    _runs.clear();
  }

  TrackedFlutterRun _select(String? app) {
    final running = _runs.values.where((run) => run.isRunning).toList();
    final matches = app == null
        ? running
        : running.where((r) => r.id == app || r.deviceId == app).toList();
    if (matches.length == 1) return matches.single;
    throw AppSelectionException(
        'Select an owned app. External IDE sessions cannot '
        'be stopped or detached here.\n${running.map((r) => r.id).join(', ')}');
  }
}
