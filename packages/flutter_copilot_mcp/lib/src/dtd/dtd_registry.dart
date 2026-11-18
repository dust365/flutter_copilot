import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dtd/dtd.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';
import 'package:logging/logging.dart' as logging;

typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Tolerates both older workspaceRoot and newer multi-root DTD listings.
class DtdInstance {
  DtdInstance(this.uri, this.roots, this.ideName);

  factory DtdInstance.fromJson(Map<String, dynamic> json) {
    final roots = <String>{};
    for (final value in [
      json['workspaceRoot'],
      json['workingDirectory'],
      ...?json['workspaceRoots'] as List?,
    ]) {
      if (value is! String || value.isEmpty) continue;
      final uri = Uri.tryParse(value);
      roots.add(uri?.scheme == 'file' ? uri!.toFilePath() : value);
    }
    return DtdInstance(canonicalDtdUri(json['wsUri'] as String), roots.toList(),
        json['ideName'] as String?);
  }

  final String uri;
  final List<String> roots;
  final String? ideName;

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'workspaceRoots': roots,
        'ideName': ideName,
      };
}

class _DtdConnection {
  _DtdConnection(this.client, this.subscription);
  final DartToolingDaemon client;
  final StreamSubscription<DTDEvent> subscription;
  Future<void> close() async {
    await subscription.cancel();
    await client.close();
  }
}

/// Discovers DTDs, subscribes before taking snapshots, and reconciles VM events.
/// A display name is deliberately never used to replace an existing session.
class DtdRegistry {
  DtdRegistry(this.apps, {this.dartExecutable = 'dart', ProcessRunner? run})
      : _run = run ?? ((exe, args) => Process.run(exe, args));

  final AppDirectory apps;
  final String dartExecutable;
  final ProcessRunner _run;
  final _logger = logging.Logger('DtdRegistry');
  final Map<String, _DtdConnection> _connections = {};
  final Map<String, Future<String>> _connecting = {};
  final Map<String, int> _revisions = {};
  final List<String> diagnostics = [];
  bool _closed = false;
  Future<void>? _refreshing;

  Future<List<DtdInstance>> instances() async {
    final result =
        await _run(dartExecutable, ['tooling-daemon', '--list', '--machine'])
            .timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      throw StateError('DTD discovery failed: ${result.stderr}. '
          'This SDK must support dart tooling-daemon --list --machine.');
    }
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];
    final decoded = jsonDecode(output);
    if (decoded is! List) throw const FormatException('Invalid DTD listing');
    final instances = <DtdInstance>[];
    for (final entry in decoded) {
      try {
        instances
            .add(DtdInstance.fromJson(Map<String, dynamic>.from(entry as Map)));
      } catch (e) {
        diagnostics.add('Ignored invalid DTD entry: $e');
      }
    }
    return instances;
  }

  Future<String> list() async {
    final result =
        jsonEncode((await instances()).map((e) => e.toJson()).toList());
    apps.dtdListing = result;
    return result;
  }

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
        _refreshing = null;
      });

  Future<void> _refresh() async {
    if (_closed) return;
    diagnostics.clear();
    final found = await instances();
    for (var start = 0; start < found.length; start += 4) {
      await Future.wait(found.skip(start).take(4).map((instance) async {
        try {
          await connect(instance.uri);
        } catch (e) {
          diagnostics.add('DTD ${instance.uri}: $e');
        }
      }));
    }
  }

  Future<String> connect(String rawUri) {
    final uri = canonicalDtdUri(rawUri);
    return _connecting[uri] ??= _connect(uri).whenComplete(() {
      _connecting.remove(uri);
    });
  }

  Future<String> _connect(String uri) async {
    if (_closed) throw StateError('DTD registry is closed');
    var existing = _connections[uri];
    if (existing != null && existing.client.isClosed) {
      _connections.remove(uri);
      await existing.close();
      existing = null;
    }
    if (existing != null) {
      await _pull(uri, existing.client);
      return 'Refreshed $uri.\n${apps.describeAll}';
    }
    final client = await DartToolingDaemon.connect(Uri.parse(uri))
        .timeout(const Duration(seconds: 5));
    StreamSubscription<DTDEvent>? subscription;
    try {
      // A successful websocket handshake alone does not distinguish DDS and DTD.
      final services = await client
          .getRegisteredServices()
          .timeout(const Duration(seconds: 3));
      if (!services.dtdServices.contains(
          '${ConnectedAppServiceConstants.serviceName}.getVmServices')) {
        throw const FormatException(
            'This endpoint does not support ConnectedApp. '
            'Use a DTD endpoint from list_dtds, or connect for a VM service URI.');
      }
      subscription = client.onVmServiceUpdate().listen((event) {
        final raw = event.data['uri']?.toString();
        if (raw == null) return;
        final key = '$uri|$raw';
        final revision = (_revisions[key] ?? 0) + 1;
        _revisions[key] = revision;
        if (event.kind == ConnectedAppServiceConstants.vmServiceUnregistered) {
          unawaited(apps.removeByUri(raw));
        } else if (event.kind ==
            ConnectedAppServiceConstants.vmServiceRegistered) {
          unawaited(_register(uri, client, event.data, key, revision,
              wait: const Duration(seconds: 15)));
        }
      }, onError: (Object e, StackTrace stack) {
        _logger.warning('DTD stream failed', e, stack);
      });
      await client
          .streamListen(ConnectedAppServiceConstants.serviceName)
          .timeout(const Duration(seconds: 3));
      if (_closed) throw StateError('DTD registry is closed');
      final connection = _DtdConnection(client, subscription);
      _connections[uri] = connection;
      unawaited(client.done.then((_) {
        if (identical(_connections[uri], connection)) _connections.remove(uri);
      }));
      await _pull(uri, client);
      return 'Connected $uri.\n${apps.describeAll}';
    } catch (_) {
      _connections.remove(uri);
      await subscription?.cancel();
      await client.close();
      rethrow;
    }
  }

  Future<void> _pull(String uri, DartToolingDaemon client) async {
    final response =
        await client.getVmServices().timeout(const Duration(seconds: 5));
    for (final info in response.vmServicesInfos) {
      final key = '$uri|${info.uri}';
      await _register(uri, client, info.toJson(), key, _revisions[key] ?? 0,
          wait: const Duration(seconds: 2));
    }
  }

  Future<void> _register(String dtdUri, DartToolingDaemon client,
      Map<String, dynamic> data, String key, int revision,
      {required Duration wait}) async {
    final raw = data['uri'] as String?;
    if (raw == null || _closed || (_revisions[key] ?? 0) != revision) return;
    try {
      // fcc/MCP run on the development host. exposedUri is for remote frontends.
      final session = await apps.connectUri(
        uri: raw,
        dtdUri: dtdUri,
        displayName: data['name'] as String?,
        waitForExtension: wait,
      );
      if (_closed || (_revisions[key] ?? 0) != revision) {
        await apps.removeByUri(raw);
        return;
      }
      try {
        final response = await client
            .call('Editor', 'getDebugSessions')
            .timeout(const Duration(seconds: 2));
        for (final entry in response.result['debugSessions'] as List? ?? []) {
          if (entry is! Map || entry['vmServiceUri'] == null) continue;
          if (normalizeVmServiceUri(entry['vmServiceUri'] as String) !=
              session.uri) continue;
          session.deviceId =
              entry['flutterDeviceId'] as String? ?? session.deviceId;
          session.mode = entry['flutterMode'] as String? ?? session.mode;
          final root = entry['projectRootPath'] as String?;
          if (root != null && Directory(root).existsSync()) {
            session.projectRoot = canonicalDirectory(root);
          }
        }
      } catch (_) {
        // Editor services are optional, including in AS/IDEA and flutter run.
      }
    } catch (e, stack) {
      diagnostics.add('Could not connect ${data['name'] ?? raw}: $e');
      _logger.fine('Skipping VM service', e, stack);
    }
  }

  Future<String> disconnect(String rawUri) async {
    final uri = canonicalDtdUri(rawUri);
    final connection = _connections.remove(uri);
    await connection?.close();
    for (final session in apps.sessionsForDtd(uri)) {
      await apps.removeSession(session);
    }
    return 'Disconnected DTD $uri. Owned flutter runs remain running.';
  }

  Future<void> close() async {
    _closed = true;
    final connections = _connections.values.toList();
    _connections.clear();
    for (final connection in connections) {
      await connection.close();
    }
  }
}
