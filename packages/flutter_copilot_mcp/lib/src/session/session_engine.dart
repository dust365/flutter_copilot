import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/process/flutter_run_manager.dart';
import 'package:flutter_copilot_mcp/src/process/launch_args.dart';
import 'package:flutter_copilot_mcp/src/process/machine_output.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/session_error.dart';
import 'package:path/path.dart' as p;

/// One implementation of discovery, selection and launch used by both clients.
class SessionEngine {
  SessionEngine(
      {required this.root,
      required this.sdk,
      AppDirectory? apps,
      DtdRegistry? dtds,
      FlutterRunManager? runs})
      : apps = apps ?? AppDirectory() {
    this.dtds = dtds ?? DtdRegistry(this.apps, dartExecutable: sdk.dart);
    this.runs =
        runs ?? FlutterRunManager(apps: this.apps, dtds: this.dtds, sdk: sdk);
  }

  final String root;
  final SdkTools sdk;
  final AppDirectory apps;
  late final DtdRegistry dtds;
  late final FlutterRunManager runs;
  final Map<String, Map<String, dynamic>> _operations = {};
  final Map<String, String> _pendingEnsures = {};
  final Map<String, Map<String, dynamic>> _bindings = {};
  final Set<String> _excluded = {};
  final Set<String> _explicit = {};
  DateTime? _lastDiscovery;
  Future<void>? _discovering;
  bool _closed = false;
  bool get busy => runs.hasRunning || _pendingEnsures.isNotEmpty;

  Future<void> discover({bool force = false}) async {
    if (_closed) throw StateError('Session engine is closed');
    if (_discovering != null) return _discovering;
    if (!force &&
        _lastDiscovery != null &&
        DateTime.now().difference(_lastDiscovery!) < const Duration(seconds: 2))
      return;
    _discovering = _discover().whenComplete(() {
      _discovering = null;
    });
    return _discovering;
  }

  Future<void> _discover() async {
    try {
      await dtds.refresh();
    } catch (e) {
      dtds.diagnostics.add('DTD discovery unavailable: $e');
    }
    _lastDiscovery = DateTime.now();
    // Restore a logical id only with verified device + source identity. Names
    // and guessed Android device ids cannot establish continuity.
    for (final session in apps.sessions) {
      final existing = _bindings.entries.where((entry) {
        final old = entry.value;
        return old['deviceId'] != null &&
            old['deviceId'] == session.deviceId &&
            old['projectRoot'] == session.projectRoot &&
            old['target'] == session.target &&
            old['flavor'] == session.flavor &&
            old['mode'] == session.mode &&
            !apps.sessions.any((active) =>
                active.id == entry.key && !identical(active, session));
      }).toList();
      if (existing.length == 1) session.id = existing.single.key;
      _bindings[session.id] = session.toJson();
    }
  }

  List<AppSession> _scoped({bool includeUnknown = false}) => apps.sessions
      .where((session) =>
          !_excluded.contains(session.uri) &&
          (_explicit.contains(session.uri) || (session.projectRoot != null
              ? containsProject(root, session.projectRoot!)
              : includeUnknown)))
      .toList();

  AppSession _select(String? query) {
    final candidates = _scoped(includeUnknown: query != null);
    final selected = query == null || query.isEmpty
        ? candidates
        : candidates
            .where((s) =>
                s.id == query ||
                s.deviceId == query ||
                s.uri == query ||
                s.displayName == query)
            .toList();
    if (selected.length == 1) return selected.single;
    throw SessionError(
        selected.isEmpty ? 'app_not_found' : 'selection_required',
        selected.isEmpty
            ? 'No matching App in $root. Use ensure_apps / fcc up '
                'to start one, or connect with an explicit VM service URI.'
            : 'Several Apps match. Select an app id.',
        candidates: candidates.map((s) => s.toJson()).toList());
  }

  Future<dynamic> call(String method, Map<String, dynamic> args) async {
    switch (method) {
      case 'hello':
        return {'protocol': 1, 'root': root, 'flutter': sdk.flutter};
      case 'list_dtds':
        return (await dtds.instances()).map((e) => e.toJson()).toList();
      case 'connect_dtd':
        return {'message': await dtds.connect(args['uri'] as String)};
      case 'disconnect_dtd':
        return {'message': await dtds.disconnect(args['uri'] as String)};
      case 'list_apps':
        await discover(force: true);
        return {
          'apps': _scoped().map((s) => s.toJson()).toList(),
          'diagnostics': dtds.diagnostics,
          'unidentifiedApps': apps.sessions
              .where((s) => s.projectRoot == null)
              .map((s) => s.toJson())
              .toList()
        };
      case 'resolve':
        await discover();
        return _select(args['app'] as String?).toJson();
      case 'connect':
        final session = await apps.connectUri(
            uri: args['uri'] as String,
            id: args['name'] as String?,
            waitForExtension: const Duration(seconds: 5));
        // An explicit URI is authorization to use an otherwise unidentifiable App.
        session.projectRoot ??= root;
        _excluded.remove(session.uri);
        _explicit.add(session.uri);
        _bindings[session.id] = session.toJson();
        return session.toJson();
      case 'disconnect':
        final session = _select(args['app'] as String?);
        _excluded.add(session.uri);
        await apps.removeSession(session);
        return {'disconnected': true, 'id': session.id};
      case 'list_devices':
        final devices = await runs.listDevices(directory: root);
        return {'devices': devices.map((d) => d.toJson()).toList()};
      case 'ensure_apps':
        return _ensure(args);
      case 'operation_status':
        final operation = _operations[args['operationId']];
        if (operation == null)
          throw SessionError('operation_not_found', 'Unknown operation');
        return operation;
      case 'get_app_logs':
        return {
          'logs': runs.logs(args['app'] as String?,
              lines: (args['lines'] as num?)?.toInt() ?? 100)
        };
      case 'stop_app':
      case 'detach_app':
        final session = _select(args['app'] as String?);
        if (!session.launched)
          throw SessionError('external_session',
              'This App belongs to an IDE or another flutter run. Only owned Apps can be stopped or detached.');
        final message = await runs.stop(session.process!.id,
            detach: method == 'detach_app');
        return {'message': message};
      default:
        throw SessionError(
            'method_not_found', 'Unknown session method: $method');
    }
  }

  Future<Map<String, dynamic>> _ensure(Map<String, dynamic> args) async {
    final explicitApps = [
      if (args['app'] is String) args['app'] as String,
      ...(args['appIds'] as List? ?? []).cast<String>()
    ];
    if (explicitApps.isNotEmpty) {
      await discover(force: true);
      return {
        'state': 'completed',
        'results': [
          for (final id in explicitApps.toSet())
            {'state': 'reused', 'app': _select(id).toJson()}
        ]
      };
    }
    final timeout = (args['timeout'] as num?)?.toInt() ?? 180;
    if (timeout <= 0)
      throw SessionError('invalid_arguments', 'timeout must be positive');
    final extra = (args['args'] as List? ?? []).cast<String>();
    validateLaunchArgs(extra);
    final target = args['target'] as String?;
    if (target != null &&
        (p.isAbsolute(target) ||
            target.startsWith('-') ||
            p.isWithin(root, p.normalize(p.join(root, target))) == false)) {
      throw SessionError(
          'invalid_arguments', 'target must be a path inside the project');
    }
    await discover(force: true);
    var requested =
        (args['deviceIds'] as List? ?? []).cast<String>().toSet().toList();
    if (requested.isEmpty && args['deviceId'] is String)
      requested = [args['deviceId'] as String];
    if (requested.length > 1 && args['name'] != null) {
      throw SessionError('invalid_arguments',
          'name is only supported for a single-device launch');
    }
    final targetUri = target == null ? null : Uri.file(p.normalize(p.join(root, target))).toString();
    bool compatible(AppSession session) =>
      (targetUri == null || session.target == targetUri) &&
      (extra.isEmpty || jsonEncode(session.launchArgs) == jsonEncode(extra));
    if (requested.isEmpty) {
      final active = _scoped().where(compatible).toList();
      if (active.length == 1 && args['newSession'] != true) {
        return {
          'state': 'completed',
          'results': [
            {'state': 'reused', 'app': active.single.toJson()}
          ]
        };
      }
      if (active.length > 1 && args['newSession'] != true) {
        throw SessionError(
            'selection_required',
            'Select one or more running Apps, '
                'or select devices to start.',
            candidates: active.map((s) => s.toJson()).toList());
      }
    }
    final devices = await runs.listDevices(directory: root);
    if (requested.isEmpty) {
      final phones =
          devices.where((d) => d.toJson()['physical'] == true).toList();
      final choices = phones.isEmpty ? devices : phones;
      if (choices.length != 1)
        throw SessionError(
            choices.isEmpty ? 'no_devices' : 'selection_required',
            'Select one or more devices.',
            candidates: choices.map((d) => d.toJson()).toList());
      requested = [choices.single.id];
    }
    for (final id in requested) {
      if (!devices.any((d) => d.matches(id)))
        throw SessionError('device_not_found',
            'Device $id is not available or this project does not support it.',
            candidates: devices.map((d) => d.toJson()).toList());
    }
    requested = requested
        .map((id) => devices.singleWhere((d) => d.matches(id)).id)
        .toSet()
        .toList();
    if (args['newSession'] != true) {
      final unknown = _scoped()
          .where((s) =>
              s.deviceId == null &&
              (targetUri == null || s.target == targetUri))
          .toList();
      if (unknown.isNotEmpty)
        throw SessionError(
            'selection_required',
            'Running Apps have no verified deviceId. Select an app to reuse, or '
                'set newSession to explicitly launch on the selected devices.',
            candidates: unknown.map((s) => s.toJson()).toList());
    }
    final signature = jsonEncode([
      requested.toList()..sort(),
      target,
      extra,
      args['newSession'] == true
    ]);
    final pending = _pendingEnsures[signature];
    if (pending != null) return _operations[pending]!;
    final operationId =
        'launch-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final operation = <String, dynamic>{
      'operationId': operationId,
      'state': 'running',
      'results': requested
          .map((id) => <String, dynamic>{'deviceId': id, 'state': 'queued'})
          .toList()
    };
    _operations[operationId] = operation;
    _pendingEnsures[signature] = operationId;
    unawaited(_launchBatch(operation, args, targetUri, extra, timeout, devices)
        .whenComplete(() {
      _pendingEnsures.remove(signature);
      // Keep recent results without growing a long-lived daemon indefinitely.
      final completed = _operations.keys
          .where((key) => _operations[key]!['state'] != 'running')
          .toList();
      for (final key in completed
          .take(completed.length > 50 ? completed.length - 50 : 0)) {
        _operations.remove(key);
      }
    }));
    return operation;
  }

  Future<void> _launchBatch(
      Map<String, dynamic> operation,
      Map<String, dynamic> args,
      String? targetUri,
      List<String> extra,
      int timeout,
      List<FlutterDevice> devices) async {
    for (final result
        in (operation['results'] as List).cast<Map<String, dynamic>>()) {
      result['state'] = 'launching';
      try {
        final deviceId = result['deviceId'] as String;
        final matches = _scoped()
            .where((s) =>
                s.deviceId != null &&
                devices
                    .singleWhere((d) => d.id == deviceId)
                    .matches(s.deviceId!) &&
                (targetUri == null || s.target == targetUri) &&
                (args['name'] == null || s.id == args['name']))
            .toList();
        if (matches.length > 1 && args['newSession'] != true)
          throw SessionError('selection_required',
              'Several Apps run on $deviceId. Select an app.',
              candidates: matches.map((s) => s.toJson()).toList());
        if (matches.length == 1 && args['newSession'] != true &&
            (extra.isEmpty || jsonEncode(matches.single.launchArgs) == jsonEncode(extra))) {
          result.addAll({'state': 'reused', 'app': matches.single.toJson()});
          continue;
        }
        if (matches.isNotEmpty && args['newSession'] != true) {
          throw SessionError('configuration_mismatch',
            'The running App configuration cannot be verified against the requested flags. '
            'Select its app id to reuse it, or explicitly request newSession.');
        }
        final session = await runs.start(
            directory: root,
            deviceId: deviceId,
            name: args['name'] as String?,
            target: args['target'] as String?,
            timeoutSeconds: timeout,
            extraArgs: extra);
        _bindings[session.id] = session.toJson();
        result.addAll({'state': 'connected', 'app': session.toJson()});
      } catch (e) {
        result.addAll({
          'state': 'failed',
          'error': e is SessionError
              ? e.toJson()
              : {'code': 'launch_failed', 'message': e.toString()}
        });
      }
    }
    operation['state'] = 'completed';
  }

  Future<void> close() async {
    _closed = true;
    await dtds.close();
    await runs.close();
    await apps.close();
  }
}
