import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/session_error.dart';
import 'package:flutter_copilot_mcp/src/session/session_server.dart';
import 'package:flutter_copilot_mcp/src/version.g.dart';

/// A client disconnect never terminates owned Flutter processes.
class SessionClient {
  SessionClient(String directory, {Future<void> Function()? start})
      : root = projectDirectory(directory),
        sdk = SdkTools.forProject(directory),
        _start = start;
  final String root;
  final SdkTools sdk;
  final Future<void> Function()? _start;
  Future<Map<String, dynamic>>? _starting;

  Future<Map<String, dynamic>?> _existing() async {
    try {
      final endpoint =
          jsonDecode(await sessionStateFile(root, sdk).readAsString())
              as Map<String, dynamic>;
      if (endpoint['version'] != version ||
          endpoint['root'] != root ||
          endpoint['flutter'] != sdk.flutter) return null;
      await request(endpoint, 'hello', {}, timeout: const Duration(seconds: 2));
      return endpoint;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _endpoint() =>
      _starting ??= _ensure().whenComplete(() {
        _starting = null;
      });

  Future<Map<String, dynamic>> _ensure() async {
    final existing = await _existing();
    if (existing != null) return existing;
    if (_start != null) {
      await _start();
    } else {
      // Re-enter this tool's own entrypoint in daemon mode. This intentionally
      // supports both Dart scripts/snapshots and compiled MCP executables.
      final script = Platform.script;
      final interpreted = script.scheme == 'file' &&
          (script.path.endsWith('.dart') || script.path.endsWith('.snapshot'));
      await Process.start(
          Platform.resolvedExecutable,
          [
            if (interpreted) script.toFilePath(),
            '--session-daemon',
            '--directory',
            root,
          ],
          mode: ProcessStartMode.detached,
          workingDirectory: root);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final endpoint = await _existing();
      if (endpoint != null) return endpoint;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw SessionError(
        'backend_unavailable',
        'Session backend did not start for $root. '
            'Check the Flutter SDK and write access to .dart_tool/flutter_copilot.');
  }

  Future<dynamic> call(String method,
          [Map<String, dynamic> args = const {}]) async =>
      request(await _endpoint(), method, args);

  static Future<dynamic> request(
      Map<String, dynamic> endpoint, String method, Map<String, dynamic> args,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final uri = Uri.parse(endpoint['url'] as String);
    if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.path != '/rpc') {
      throw SessionError('invalid_endpoint', 'Invalid local session endpoint');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${endpoint['token']}');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(
          {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': args}));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final message = jsonDecode(body) as Map<String, dynamic>;
      if (message['error'] is Map) {
        final error = message['error'] as Map;
        final data = error['data'] as Map? ?? {};
        throw SessionError(
            data['code'] as String? ?? 'session_error', '${error['message']}',
            candidates: (data['candidates'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList());
      }
      return message['result'];
    } finally {
      client.close(force: true);
    }
  }
}
