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

  /// Isolate id advertised by `getVM`. Tests change this to simulate a hot restart.
  String isolateId = 'isolates/1';

  /// How many `getIsolate` lookups should pretend the Copilot extension is absent.
  int hideExtensionForCalls = 0;

  /// When true, `streamListen` is followed by `ServiceRegistered` events for
  /// the `reloadSources` and `hotRestart` services that `flutter run` registers.
  bool announceFlutterRunServices = false;

  WebSocket? _socket;
  final List<WebSocket> _sockets = [];

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
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    _socket = ws;
    _sockets.add(ws);
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

  void _announce(String service, String method) {
    _socket?.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'streamNotify',
        'params': {
          'streamId': 'Service',
          'event': {
            'type': 'Event',
            'kind': 'ServiceRegistered',
            'timestamp': 0,
            'service': service,
            'method': method,
          },
        },
      }),
    );
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
              'id': isolateId,
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
        final requested = params['isolateId'] as String? ?? isolateId;
        var current = requested == isolateId;
        if (current && hideExtensionForCalls > 0) {
          hideExtensionForCalls--;
          current = false;
        }
        return {
          'type': 'Isolate',
          'id': requested,
          'name': 'main',
          'number': '1',
          'isSystemIsolate': false,
          'extensionRPCs':
              current ? ['ext.flutter.flutter_copilot.getLogs'] : <String>[],
        };
      case 'streamListen':
        if (announceFlutterRunServices) {
          _announce('reloadSources', 's0.reloadSources');
          _announce('hotRestart', 's0.hotRestart');
        }
        return {'type': 'Success'};
      case 's0.reloadSources':
      case 's0.hotRestart':
        return {'type': 'Success'};
      case 'reloadSources':
        return {'type': 'ReloadReport', 'success': true};
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
