import 'dart:async';

import 'package:flutter_copilot_mcp/src/process/launch_args.dart';
import 'package:flutter_copilot_mcp/src/process/machine_output.dart';
import 'package:flutter_copilot_mcp/src/process/platform_launch_gate.dart';
import 'package:test/test.dart';

void main() {
  group('parseMachineLine', () {
    test('reads wsUri and the DTD uri from machine events', () {
      final port = parseMachineLine(
        '[{"event":"app.debugPort","params":{"port":12345,"wsUri":"ws://127.0.0.1:12345/token=/ws"}}]',
      );
      final dtd = parseMachineLine(
        '[{"event":"app.dtd","params":{"uri":"ws://127.0.0.1:54321/secret"}}]',
      );

      expect(port?.wsUri, 'ws://127.0.0.1:12345/token=/ws');
      expect(dtd?.dtdUri, 'ws://127.0.0.1:54321/secret');
    });

    test('converts an http baseUri when wsUri is absent', () {
      final line = parseMachineLine(
        '[{"event":"app.debugPort","params":{"baseUri":"http://127.0.0.1:8181/AbC=/"}}]',
      );

      expect(line?.wsUri, 'ws://127.0.0.1:8181/AbC=/ws');
    });

    test('ignores ordinary log lines', () {
      expect(parseMachineLine('Starting application...'), isNull);
    });
  });

  group('parseFlutterDevices', () {
    test('reads the JSON array that follows log lines', () {
      const output = '''
Waiting for another flutter command...
[
  {
    "name": "sdk gphone64",
    "id": "emulator-5554",
    "isSupported": true,
    "targetPlatform": "android-arm64",
    "emulator": true
  }
]
''';
      final devices = parseFlutterDevices(output);

      expect(devices, hasLength(1));
      expect(devices.single.id, 'emulator-5554');
      expect(devices.single.emulator, isTrue);
      expect(devices.single.supported, isTrue);
    });
  });

  group('platformFamily', () {
    test('groups targets that share a build directory', () {
      expect(platformFamily('android-arm64'), 'android');
      expect(platformFamily('android-x64'), 'android');
      expect(platformFamily('ios'), 'ios');
      expect(platformFamily('darwin'), 'macos');
      expect(platformFamily('web-javascript'), 'web');
      expect(platformFamily(''), 'unknown');
    });
  });

  group('PlatformLaunchGate', () {
    test('runs one family at a time', () async {
      final gate = PlatformLaunchGate();
      final events = <String>[];

      final first = gate.run('android', () async {
        events.add('android-start');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        events.add('android-end');
      });
      final second = gate.run('android', () async {
        events.add('android-next');
      });

      await Future.wait([first, second]);
      expect(events, ['android-start', 'android-end', 'android-next']);
    });

    test('runs different families together', () async {
      final gate = PlatformLaunchGate();
      final androidHolding = Completer<void>();
      final androidStarted = Completer<void>();

      final android = gate.run('android', () async {
        androidStarted.complete();
        await androidHolding.future;
      });
      await androidStarted.future;

      var macosStarted = false;
      final macos = gate.run('macos', () async {
        macosStarted = true;
      });
      await macos;

      expect(macosStarted, isTrue);
      androidHolding.complete();
      await android;
    });

    test('releases the next launch after the previous one fails', () async {
      final gate = PlatformLaunchGate();
      final first = gate.run<void>('android', () async {
        throw StateError('install failed');
      });
      final second = gate.run('android', () async => 'started');

      await expectLater(first, throwsA(isA<StateError>()));
      expect(await second, 'started');
    });
  });

  group('validateLaunchArgs', () {
    test('allows the documented flags', () {
      expect(
        () => validateLaunchArgs(
            ['--flavor', 'dev', '--dart-define=A=B', '--debug']),
        returnsNormally,
      );
    });

    test('rejects flags that can redirect the build', () {
      expect(
        () => validateLaunchArgs(['--dart-define-from-file', 'secrets.json']),
        throwsA(isA<LaunchArgsException>()),
      );
      expect(
        () => validateLaunchArgs(['--use-application-binary', 'app.apk']),
        throwsA(isA<LaunchArgsException>()),
      );
    });
  });
}
