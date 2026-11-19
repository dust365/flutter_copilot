import 'dart:convert';
import 'dart:io';

/// A loopback DTD that answers the ConnectedApp calls used by DtdRegistry.
class MockDtd {
  MockDtd(this.server);
  final HttpServer server;
  final sockets = <WebSocket>[];
  final apps = <Map<String, dynamic>>[];
  String get uri => 'ws://127.0.0.1:${server.port}/token';

  static Future<MockDtd> start() async {
    final mock =
        MockDtd(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    mock.server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      mock.sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map;
        final dynamic result;
        switch (message['method']) {
          case 'getRegisteredServices':
            result = {
              'type': 'RegisteredServicesResponse',
              'dtdServices': ['ConnectedApp.getVmServices'],
              'clientServices': []
            };
          case 'ConnectedApp.getVmServices':
            result = {'type': 'VmServicesResponse', 'vmServices': mock.apps};
          case 'streamListen':
            result = {'type': 'Success'};
          default:
            socket.add(jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              'error': {'code': -32601, 'message': 'Method not found'}
            }));
            return;
        }
        socket.add(jsonEncode(
            {'jsonrpc': '2.0', 'id': message['id'], 'result': result}));
      });
    });
    return mock;
  }

  void event(String kind, Map<String, dynamic> app) {
    for (final socket in sockets) {
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'streamNotify',
        'params': {
          'streamId': 'ConnectedApp',
          'eventKind': kind,
          'eventData': app,
          'timestamp': 0,
        }
      }));
    }
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
