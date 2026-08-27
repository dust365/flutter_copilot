import 'package:flutter_copilot_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

import 'mock_vm_server.dart';

/// Regression tests for [VmServiceConnector] covering the two params that were
/// historically silently dropped or mis-parsed on the claw side:
///
///   - `long_press` **duration** — must be forwarded to the extension call.
///     A prior claw bug (`as num?` cast on a String) made any non-null
///     duration crash; the same code path was silently unreachable from MCP
///     because no call site ever passed a non-default value.
///   - `navigate` **arguments** — must be forwarded to the extension call.
///     claw previously treated nested maps as `Map<String, dynamic>`, which is
///     never true after VM-service transport, and silently dropped them.
///
/// These tests do not run claw (no Flutter); they assert on the JSON-RPC
/// payload that crossed the wire. A mock VM service ([MockVmServer]) records
/// every request so the tests can inspect the exact shape the MCP sent.
void main() {
  late MockVmServer server;
  late VmServiceConnector connector;

  setUp(() async {
    server = await MockVmServer.start();
    connector = VmServiceConnector();
    await connector.connect(server.wsUri);
  });

  tearDown(() async {
    await connector.disconnect();
    await server.close();
  });

  group('longPress', () {
    test('forwards the duration param to the extension', () async {
      await connector.longPress({'text': 'Login'}, 1234);

      final call = server.lastCallTo('ext.flutter.flutter_copilot.longPress');
      expect(call, isNotNull, reason: 'longPress was never invoked on the VM');
      expect(call!.params['duration'], 1234);
      expect(call.params['text'], 'Login');
      expect(call.params['isolateId'], 'isolates/1');
    });

    test('omits duration entirely when caller passes null', () async {
      await connector.longPress({'text': 'Login'}, null);

      final call = server.lastCallTo('ext.flutter.flutter_copilot.longPress');
      expect(call, isNotNull);
      // Claw defaults to 500ms when the key is absent; sending
      // `duration: null` would reach the `as num?` path on old claw and crash.
      expect(call!.params.containsKey('duration'), isFalse);
    });
  });

  group('navigate', () {
    test('forwards arguments as a nested JSON object', () async {
      await connector.navigate('push', '/checkout', {
        'source': 'cart',
        'itemCount': 3,
        'flags': {'express': true},
      });

      final call = server.lastCallTo('ext.flutter.flutter_copilot.navigate');
      expect(call, isNotNull, reason: 'navigate was never invoked on the VM');
      expect(call!.params['action'], 'push');
      expect(call.params['route'], '/checkout');
      expect(call.params['arguments'], {
        'source': 'cart',
        'itemCount': 3,
        'flags': {'express': true},
      });
    });

    test('omits the arguments field when caller passes null', () async {
      await connector.navigate('pop', null, null);

      final call = server.lastCallTo('ext.flutter.flutter_copilot.navigate');
      expect(call, isNotNull);
      expect(call!.params['action'], 'pop');
      expect(call.params.containsKey('route'), isFalse);
      expect(call.params.containsKey('arguments'), isFalse);
    });
  });
}
