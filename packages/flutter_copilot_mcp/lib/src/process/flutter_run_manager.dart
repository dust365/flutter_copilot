import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/process/launch_args.dart';
import 'package:flutter_copilot_mcp/src/process/machine_output.dart';
import 'package:flutter_copilot_mcp/src/process/platform_launch_gate.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';
import 'package:logging/logging.dart' as logging;

/// A `flutter run` process owned by this MCP server.
class TrackedFlutterRun implements OwnedProcess {
  TrackedFlutterRun({
    required this.process,
    required this.deviceId,
    required this.id,
  });

  final Process process;
  @override
  final String deviceId;
  @override
  String id;

  final List<String> _lines = [];
  String? wsUri;
  String? dtdUri;
  var _stopped = false;

  @override
  bool get isRunning => !_stopped;

  void addLine(String line) {
    _lines.add(line);
    if (_lines.length > 500) {
      _lines.removeAt(0);
    }
    final parsed = parseMachineLine(line);
    if (parsed == null) return;
    wsUri ??= parsed.wsUri;
    dtdUri ??= parsed.dtdUri;
  }

  @override
  String logTail({int lines = 500}) {
    if (_lines.isEmpty) return 'No flutter run output yet.';
    final start = _lines.length > lines ? _lines.length - lines : 0;
    return _lines.sublist(start).join('\n');
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }
}

/// Starts and stops `flutter run` processes for [launch_app].
class FlutterRunManager {
  FlutterRunManager({
    required this.apps,
    required this.dtds,
  }) : _logger = logging.Logger('FlutterRunManager');

  final AppDirectory apps;
  final DtdRegistry dtds;
  final logging.Logger _logger;
  final Map<String, TrackedFlutterRun> _runs = {};
  final PlatformLaunchGate _gates = PlatformLaunchGate();
  List<FlutterDevice>? _devices;

  Future<List<FlutterDevice>> listDevices() async {
    final result = await Process.run('flutter', ['devices', '--machine']);
    final output = '${result.stdout}${result.stderr}';
    if (result.exitCode != 0 && output.trim().isEmpty) {
      throw Exception('flutter devices failed (${result.exitCode}).');
    }
    final devices = parseFlutterDevices(output);
    _devices = devices;
    return devices;
  }

  Future<String> launch({
    required String directory,
    String? deviceId,
    String? name,
    String? target,
    int timeoutSeconds = 90,
    List<String> extraArgs = const [],
  }) async {
    if (timeoutSeconds <= 0) {
      throw LaunchArgsException(
          'timeout must be a positive number of seconds.');
    }
    validateLaunchArgs(extraArgs);
    if (!Directory(directory).existsSync()) {
      throw LaunchArgsException(
          'Flutter project directory does not exist: $directory');
    }

    final device = await _resolveDevice(deviceId);
    return _gates.run(
      platformFamily(device.targetPlatform),
      () => _launchResolved(
        device: device,
        directory: directory,
        name: name,
        target: target,
        timeoutSeconds: timeoutSeconds,
        extraArgs: extraArgs,
      ),
    );
  }

  Future<String> _launchResolved({
    required FlutterDevice device,
    required String directory,
    String? name,
    String? target,
    required int timeoutSeconds,
    required List<String> extraArgs,
  }) async {
    final resolvedDevice = device.id;
    final busy = _runs.values.where(
      (run) => run.deviceId == resolvedDevice && run.isRunning,
    );
    if (busy.isNotEmpty) {
      throw LaunchArgsException(
        'This server already runs an app on $resolvedDevice '
        '(${busy.first.id}). Call stop_app before launching it again.',
      );
    }

    final args = <String>[
      'run',
      '--print-dtd',
      '--machine',
      '--device-id',
      resolvedDevice,
      if (target != null && target.isNotEmpty) ...['--target', target],
      ...extraArgs,
    ];
    _logger.info('Starting flutter ${args.join(' ')} in $directory');
    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: directory,
    );
    final run = TrackedFlutterRun(
      process: process,
      deviceId: resolvedDevice,
      id: name?.trim().isNotEmpty == true ? name!.trim() : resolvedDevice,
    );

    final ready = Completer<void>();
    void considerReady() {
      if (run.wsUri != null && run.dtdUri != null && !ready.isCompleted) {
        ready.complete();
      }
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      run.addLine(line);
      considerReady();
    });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      run.addLine(line);
      considerReady();
    });

    unawaited(
      process.exitCode.then((code) {
        run._stopped = true;
        _runs.remove(run.id);
        if (!ready.isCompleted) {
          ready.completeError(
            Exception(
              'flutter run exited with $code before the app was ready.\n'
              '${run.logTail()}',
            ),
          );
        }
      }),
    );

    try {
      await ready.future.timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      await run.stop();
      throw Exception(
        'flutter run did not report a DTD and VM service within '
        '$timeoutSeconds seconds. Increase timeout for a cold build.\n'
        '${run.logTail()}',
      );
    } catch (err) {
      await run.stop();
      rethrow;
    }

    final AppSession session;
    try {
      session = await apps.connectUri(
        uri: run.wsUri!,
        id: run.id,
        deviceId: resolvedDevice,
        dtdUri: canonicalDtdUri(run.dtdUri!),
        process: run,
        waitForExtension: const Duration(seconds: 15),
      );
    } catch (err) {
      await run.stop();
      rethrow;
    }
    run.id = session.id;
    own(run);

    var dtdNote = '';
    try {
      dtdNote = await dtds.connect(run.dtdUri!);
    } catch (err) {
      _logger.warning('App started but DTD subscribe failed', err);
      dtdNote = 'DTD subscribe failed: $err';
    }

    return 'Started ${session.id} on $resolvedDevice.\n'
        '${session.describe()}\n'
        '$dtdNote\n'
        'stop_app ends this flutter run. The app on the device stays open.';
  }

  Future<String> stop(String? app) async {
    final run = _select(app);
    final id = run.id;
    await run.stop();
    _runs.remove(id);
    final session = _sessionFor(run);
    if (session != null) {
      await apps.removeSession(session);
    }
    return 'Stopped $id. The app on the device is still running.';
  }

  String logs(String? app, {int lines = 500}) {
    final count = lines <= 0 ? 500 : lines;
    return _select(app).logTail(lines: count);
  }

  /// Remembers a process this server is responsible for stopping.
  void own(TrackedFlutterRun run) {
    _runs[run.id] = run;
  }

  Future<void> close() async {
    final runs = List<TrackedFlutterRun>.of(_runs.values);
    _runs.clear();
    for (final run in runs) {
      await run.stop();
    }
  }

  Future<FlutterDevice> _resolveDevice(String? deviceId) async {
    final requested = deviceId?.trim();
    var devices = _devices;
    final known = requested != null &&
        requested.isNotEmpty &&
        devices != null &&
        devices.any((device) => device.id == requested);
    if (devices == null ||
        (requested != null && requested.isNotEmpty && !known)) {
      devices = await listDevices();
    }
    if (requested != null && requested.isNotEmpty) {
      for (final device in devices) {
        if (device.id == requested) return device;
      }
      return FlutterDevice(
        id: requested,
        name: requested,
        supported: true,
        targetPlatform: '',
        emulator: false,
      );
    }

    final supported = devices.where((device) => device.supported).toList();
    if (supported.length == 1) return supported.single;
    throw LaunchArgsException(
      'Pass deviceId. flutter devices found:\n${formatFlutterDevices(devices)}',
    );
  }

  TrackedFlutterRun _select(String? app) {
    final running = _runs.values.where((run) => run.isRunning).toList();
    if (running.isEmpty) {
      throw AppSelectionException(
        'This server has not launched an app. Use launch_app first.',
      );
    }
    final query = app?.trim();
    if (query == null || query.isEmpty) {
      if (running.length == 1) return running.single;
      throw AppSelectionException(
        'Multiple launched apps. Pass app.\n${_describe(running)}',
      );
    }
    for (final run in running) {
      if (run.id == query || run.deviceId == query) return run;
    }
    throw AppSelectionException(
      'No launched app matches "$query".\n${_describe(running)}',
    );
  }

  AppSession? _sessionFor(TrackedFlutterRun run) {
    for (final session in apps.sessions) {
      if (identical(session.process, run) || session.id == run.id) {
        return session;
      }
    }
    return null;
  }

  String _describe(List<TrackedFlutterRun> runs) {
    return runs.map((run) => '- ${run.id}  device=${run.deviceId}').join('\n');
  }
}
