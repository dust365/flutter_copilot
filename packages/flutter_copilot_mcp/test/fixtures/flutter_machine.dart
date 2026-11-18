// A real subprocess implementing the relevant Flutter machine protocol. It
// deliberately provides no DTD, and needs no Flutter installation or device.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.first == 'devices') {
    stdout.writeln(jsonEncode([
      for (final id in ['phone-a', 'phone-b', 'broken'])
        {
          'id': id,
          'name': 'Same model',
          'isSupported': true,
          'emulator': false,
          'targetPlatform': 'android-arm64'
        }
    ]));
    return;
  }
  final device = args[args.indexOf('--device-id') + 1];
  final trace = File('${Directory.current.path}/trace');
  await trace.writeAsString('launch:$device\n', mode: FileMode.append);
  if (device == 'broken') {
    stderr.writeln('fixture build failed');
    exitCode = 1;
    return;
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map;
      final method = message['method'];
      dynamic result;
      switch (method) {
        case 'getVM':
          result = {
            'type': 'VM',
            'name': device,
            'architectureBits': 64,
            'hostCPU': 'arm64',
            'operatingSystem': 'android',
            'targetCPU': 'arm64',
            'version': 'test',
            'pid': pid,
            'startTime': 0,
            'isolates': [
              {
                'type': '@Isolate',
                'id': 'isolates/1',
                'name': 'main',
                'number': '1',
                'isSystemIsolate': false
              }
            ],
            'isolateGroups': [],
            'systemIsolates': [],
            'systemIsolateGroups': []
          };
        case 'getIsolate':
          result = {
            'type': 'Isolate',
            'id': 'isolates/1',
            'name': 'main',
            'number': '1',
            'isSystemIsolate': false,
            'rootLib': {
              'type': '@Library',
              'id': 'libraries/1',
              'name': '',
              'uri':
                  Uri.file('${Directory.current.path}/lib/main.dart').toString()
            },
            'extensionRPCs': ['ext.flutter.flutter_copilot.getLogs']
          };
        default:
          result = {'type': 'Success', 'status': 'Success'};
      }
      socket.add(jsonEncode(
          {'jsonrpc': '2.0', 'id': message['id'], 'result': result}));
    });
  });
  void event(String name, Map<String, dynamic> params) =>
      stdout.writeln(jsonEncode([
        {'event': name, 'params': params}
      ]));
  event('app.start', {
    'appId': device,
    'deviceId': device,
    'directory': Directory.current.path
  });
  event('app.debugPort',
      {'appId': device, 'wsUri': 'ws://127.0.0.1:${server.port}/ws'});
  // A small gap makes concurrent callers overlap reliably.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  event('app.started', {'appId': device});
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = (jsonDecode(line) as List).single as Map;
    final method = message['method'];
    await trace.writeAsString('$method:$device\n', mode: FileMode.append);
    stdout.writeln(jsonEncode([
      {'id': message['id'], 'result': true}
    ]));
    await stdout.flush();
    if (method == 'app.stop' || method == 'app.detach') break;
  }
  for (final socket in sockets) {
    await socket.close();
  }
  await server.close(force: true);
}
