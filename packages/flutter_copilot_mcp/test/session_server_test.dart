import 'dart:convert';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/session_client.dart';
import 'package:flutter_copilot_mcp/src/session/session_engine.dart';
import 'package:flutter_copilot_mcp/src/session/session_error.dart';
import 'package:flutter_copilot_mcp/src/session/session_server.dart';
import 'package:test/test.dart';

void main() {
  test('authenticated IPC serves clients; client exit leaves the backend alive',
      () async {
    final directory = await Directory.systemTemp.createTemp('copilot-ipc-');
    final engine = SessionEngine(
        root: directory.path,
        sdk: const SdkTools(flutter: '/sdk/flutter', dart: '/sdk/dart'));
    final state = File('${directory.path}/endpoint.json');
    final server = (await SessionServer.start(engine, state: state))!;
    try {
      final endpoint =
          jsonDecode(await state.readAsString()) as Map<String, dynamic>;
      final first = await SessionClient.request(endpoint, 'hello', {});
      expect(first['root'], directory.path);
      // Independent request clients close their sockets after each call.
      final next = await SessionClient.request(endpoint, 'hello', {});
      expect(next['protocol'], 1);
      await expectLater(
          SessionClient.request(endpoint, 'unknown', {}),
          throwsA(isA<SessionError>()
              .having((e) => e.code, 'code', 'method_not_found')));
      final http = HttpClient();
      try {
        final request =
            await http.postUrl(Uri.parse(endpoint['url'] as String));
        request.write('{}');
        expect((await request.close()).statusCode, HttpStatus.forbidden);
      } finally {
        http.close(force: true);
      }
    } finally {
      await server.close();
      await directory.delete(recursive: true);
    }
  });
}
