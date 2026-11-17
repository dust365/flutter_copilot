import 'dart:async';
import 'dart:io';

import 'package:dtd/dtd.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';
import 'package:flutter_copilot_mcp/src/vm_service/vm_service_connector.dart';
import 'package:logging/logging.dart' as logging;

/// One subscription to a Dart Tooling Daemon.
class _DtdConnection {
  _DtdConnection(this.uri, this.client, this.subscription);

  final String uri;
  final DartToolingDaemon client;
  final StreamSubscription<DTDEvent> subscription;

  Future<void> close() async {
    await subscription.cancel();
    await client.close();
  }
}

/// Finds apps through DTD and keeps the [AppDirectory] in sync with them.
class DtdRegistry {
  DtdRegistry(this.apps) : _logger = logging.Logger('DtdRegistry');

  final AppDirectory apps;
  final logging.Logger _logger;
  final Map<String, _DtdConnection> _connections = {};

  /// Runs `dart tooling-daemon --list` and remembers the text for empty-table errors.
  Future<String> list() async {
    final result = await Process.run('dart', ['tooling-daemon', '--list']);
    final stdoutText = (result.stdout as String).trim();
    final stderrText = (result.stderr as String).trim();
    final text = [
      if (stdoutText.isNotEmpty) stdoutText,
      if (stderrText.isNotEmpty) stderrText,
    ].join('\n');
    final listing = text.isEmpty
        ? 'dart tooling-daemon --list exited ${result.exitCode} with no output.'
        : text;
    apps.dtdListing = listing;
    return listing;
  }

  /// Connects [rawUri], pulls apps already registered there, and subscribes to
  /// later registrations. Calling it again for the same address refreshes the list.
  Future<String> connect(String rawUri) async {
    final uri = canonicalDtdUri(rawUri);
    final existing = _connections[uri];
    if (existing != null) {
      if (!existing.client.isClosed) {
        final summary = await _pull(existing);
        return 'Already connected to $uri.\n$summary';
      }
      await existing.close();
      _connections.remove(uri);
    }

    final client = await DartToolingDaemon.connect(Uri.parse(uri));
    StreamSubscription<DTDEvent>? subscription;
    try {
      await _rejectVmService(client, uri);
      subscription = client.onVmServiceUpdate().listen(
        (event) {
          unawaited(_onEvent(uri, event));
        },
        onError: (Object err, StackTrace stack) {
          _logger.warning('DTD event stream failed for $uri', err, stack);
        },
      );
      await client.streamListen(ConnectedAppServiceConstants.serviceName);
      final connection = _DtdConnection(uri, client, subscription);
      _connections[uri] = connection;
      final summary = await _pull(connection);
      return 'Connected to $uri.\n$summary';
    } catch (err) {
      _connections.remove(uri);
      await subscription?.cancel();
      await client.close();
      rethrow;
    }
  }

  /// Drops the DTD subscription and the sessions that came from it.
  ///
  /// A `flutter run` this server started is not killed.
  Future<String> disconnect(String rawUri) async {
    final uri = canonicalDtdUri(rawUri);
    final connection = _connections.remove(uri);
    if (connection == null) {
      return 'Not connected to DTD $uri.';
    }
    await connection.close();
    final victims = apps.sessionsForDtd(uri);
    for (final session in victims) {
      await apps.removeSession(session);
    }
    if (victims.isEmpty) {
      return 'Disconnected DTD $uri.';
    }
    final names = victims.map((session) => session.id).join(', ');
    return 'Disconnected DTD $uri and removed $names. '
        'flutter run processes started by this server are still running until stop_app.';
  }

  Future<void> close() async {
    final connections = List<_DtdConnection>.of(_connections.values);
    _connections.clear();
    for (final connection in connections) {
      await connection.close();
    }
  }

  Future<String> _pull(_DtdConnection connection) async {
    final response = await connection.client.getVmServices();
    final connected = <String>[];
    final skipped = <String>[];
    final seen = <String>{};

    for (final info in response.vmServicesInfos) {
      final raw = _preferredUri(info.uri, info.exposedUri);
      if (raw == null || !seen.add(raw)) continue;
      try {
        final session = await apps.connectUri(
          uri: raw,
          id: info.name,
          dtdUri: connection.uri,
          waitForExtension: const Duration(seconds: 2),
        );
        connected.add(session.describe());
      } on NoCopilotExtensionException {
        skipped.add(info.name ?? raw);
      }
    }

    final buffer = StringBuffer();
    if (connected.isEmpty) {
      buffer.writeln('No Flutter Copilot apps on this DTD.');
    } else {
      buffer.writeln('Apps:');
      for (final line in connected) {
        buffer.writeln('- $line');
      }
    }
    if (skipped.isNotEmpty) {
      buffer.writeln(
        'Skipped (FlutterCopilotBinding is not initialized):',
      );
      for (final line in skipped) {
        buffer.writeln('- $line');
      }
    }
    return buffer.toString().trimRight();
  }

  Future<void> _onEvent(String dtdUri, DTDEvent event) async {
    final raw = _preferredUri(
      event.data['uri']?.toString(),
      event.data['exposedUri']?.toString(),
    );
    if (raw == null) {
      _logger.warning('DTD ${event.kind} event had no uri: ${event.data}');
      return;
    }

    if (event.kind == ConnectedAppServiceConstants.vmServiceUnregistered) {
      await apps.removeByUri(raw);
      return;
    }
    if (event.kind != ConnectedAppServiceConstants.vmServiceRegistered) {
      return;
    }

    final name = event.data['name']?.toString();
    try {
      await apps.connectUri(
        uri: raw,
        id: name,
        dtdUri: dtdUri,
        replaceSameId: name != null && name.isNotEmpty,
        waitForExtension: const Duration(seconds: 15),
      );
    } on NoCopilotExtensionException {
      _logger.info('Skipping $raw ($name): flutter_copilot is not initialized');
    } catch (err, stack) {
      _logger.warning('Failed to connect app from DTD event $raw', err, stack);
    }
  }

  Future<void> _rejectVmService(DartToolingDaemon client, String uri) async {
    try {
      final response = await client.call(null, 'getVM');
      final looksLikeVm =
          response.type == 'VM' || response.result['isolates'] != null;
      if (looksLikeVm) {
        throw FormatException(
          '$uri is a VM service address, not a DTD. '
          'Use connect with the ws:// address.',
        );
      }
    } catch (err) {
      if (err is FormatException) rethrow;
      if (_isMethodNotFound(err)) return;
      rethrow;
    }
  }

  String? _preferredUri(String? uri, String? exposedUri) {
    final preferred =
        (exposedUri != null && exposedUri.isNotEmpty) ? exposedUri : uri;
    if (preferred == null || preferred.isEmpty) return null;
    return preferred;
  }

  bool _isMethodNotFound(Object error) {
    final text = error.toString();
    return text.contains('-32601') ||
        text.toLowerCase().contains('method not found');
  }
}
