import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A captured JSON-RPC request received by [MockVmServer].
class RecordedRequest {
  RecordedRequest(this.method, this.params);

  final String method;
  final Map<String, dynamic> params;
}

/// A minimal Dart VM service stand-in for integration-testing the
/// [VmServiceConnector].
///
/// Implements just enough of the JSON-RPC 2.0 surface that the `vm_service`
/// client package exercises during `connect()` and `callServiceExtension`:
///   - `getVM` → one isolate
///   - `getIsolate` → advertises `ext.flutter.flutter_copilot.getLogs`
///   - `streamListen` → success
///   - `ext.flutter.flutter_copilot.*` → recorded and echoed back as success
///
/// Every JSON-RPC request is appended to [requests] so tests can assert on the
/// exact params that crossed the wire — the whole point of a regression test
/// for "does the MCP forward `duration` / `arguments`?".
class MockVmServer {
  MockVmServer._(this._server);

  final HttpServer _server;

  /// All requests received, in arrival order.
  final List<RecordedRequest> requests = [];

  /// Starts the server on loopback with an OS-assigned port.
  static Future<MockVmServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = MockVmServer._(server);
    server.listen(mock._onRequest);
    return mock;
  }

  /// The `ws://...` URI to pass to [VmServiceConnector.connect].
  String get wsUri => 'ws://127.0.0.1:${_server.port}/ws';

  /// Returns the last recorded request whose method equals [method], or null.
  RecordedRequest? lastCallTo(String method) {
    for (final r in requests.reversed) {
      if (r.method == method) return r;
    }
    return null;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = msg['id'];
      final method = msg['method'] as String;
      final params = (msg['params'] as Map<String, dynamic>? ?? const {});
      requests.add(RecordedRequest(method, params));
      final result = _handle(method, params);
      ws.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
    });
  }

  Map<String, dynamic> _handle(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'getVM':
        return {
          'type': 'VM',
          'name': 'mock',
          'architectureBits': 64,
          'hostCPU': 'test',
          'operatingSystem': 'test',
          'targetCPU': 'test',
          'version': '0.0',
          'pid': 0,
          'startTime': 0,
          'isolates': [
            {
              'type': '@Isolate',
              'id': 'isolates/1',
              'name': 'main',
              'number': '1',
              'isSystemIsolate': false,
            },
          ],
          'isolateGroups': <dynamic>[],
          'systemIsolates': <dynamic>[],
          'systemIsolateGroups': <dynamic>[],
        };
      case 'getIsolate':
        return {
          'type': 'Isolate',
          'id': 'isolates/1',
          'name': 'main',
          'number': '1',
          'isSystemIsolate': false,
          'extensionRPCs': ['ext.flutter.flutter_copilot.getLogs'],
        };
      case 'streamListen':
        return {'type': 'Success'};
      default:
        // Claw extensions are all of the form `ext.flutter.flutter_copilot.*`.
        // Echo success so the connector's error-status short-circuit is not
        // taken.
        return {
          'type': '_extensionType',
          'status': 'Success',
          'message': 'ok',
        };
    }
  }
}
