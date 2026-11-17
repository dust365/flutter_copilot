import 'dart:io';

import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/process/flutter_run_manager.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:test/test.dart';

import 'mock_vm_server.dart';

void main() {
  group('AppDirectory', () {
    late MockVmServer phone;
    late MockVmServer tablet;
    late AppDirectory apps;

    setUp(() async {
      phone = await MockVmServer.start();
      tablet = await MockVmServer.start();
      apps = AppDirectory();
    });

    tearDown(() async {
      await apps.close();
      await phone.close();
      await tablet.close();
    });

    test('keeps both URIs and does not add a duplicate', () async {
      await apps.connectUri(uri: phone.wsUri, id: 'phone');
      await apps.connectUri(uri: tablet.wsUri, id: 'tablet');
      await apps.connectUri(uri: phone.wsUri, id: 'phone');

      expect(apps.sessions, hasLength(2));
    });

    test('requires app when several sessions are connected', () async {
      await apps.connectUri(uri: phone.wsUri, id: 'phone');
      await apps.connectUri(uri: tablet.wsUri, id: 'tablet');

      expect(() => apps.resolve(null), throwsA(isA<AppSelectionException>()));

      final selected = apps.resolve('phone');
      await selected.connector.longPress({'text': 'Login'}, 10);

      expect(
        phone.lastCallTo('ext.flutter.flutter_copilot.longPress'),
        isNotNull,
      );
      expect(
        tablet.lastCallTo('ext.flutter.flutter_copilot.longPress'),
        isNull,
      );
    });

    test('uses the only session when app is omitted', () async {
      await apps.connectUri(uri: phone.wsUri, id: 'phone');

      expect(apps.resolve(null).id, 'phone');
    });

    test('empty selection includes the remembered DTD list', () async {
      apps.dtdListing = 'ws://127.0.0.1:1/dtd';

      expect(
        () => apps.resolve(null),
        throwsA(
          predicate<AppSelectionException>(
            (error) => error.message.contains('ws://127.0.0.1:1/dtd'),
          ),
        ),
      );
    });

    test('open refreshes the DTD list before reporting an empty table',
        () async {
      apps.listDtds = () async => 'ws://127.0.0.1:9/dtd';

      expect(
        apps.open(null),
        throwsA(
          predicate<AppSelectionException>(
            (error) => error.message.contains('ws://127.0.0.1:9/dtd'),
          ),
        ),
      );
    });

    test('a registration with the same name replaces the DDS uri', () async {
      final first = await apps.connectUri(uri: phone.wsUri, id: 'phone');
      final replaced = await apps.connectUri(
        uri: tablet.wsUri,
        id: 'phone',
        replaceSameId: true,
      );

      expect(identical(first, replaced), isTrue);
      expect(apps.sessions, hasLength(1));
      expect(replaced.uri, tablet.wsUri);
      await replaced.connector.longPress({'text': 'Login'}, 10);
      expect(
        tablet.lastCallTo('ext.flutter.flutter_copilot.longPress'),
        isNotNull,
      );
    });
  });

  test('closing the run manager kills owned processes', () async {
    final apps = AppDirectory();
    final manager = FlutterRunManager(apps: apps, dtds: DtdRegistry(apps));
    final process = await Process.start('sleep', ['30']);
    manager.own(
      TrackedFlutterRun(
          process: process, deviceId: 'emulator-5554', id: 'phone'),
    );

    await manager.close();

    expect(
      process.exitCode.timeout(const Duration(seconds: 3)),
      completion(isNot(0)),
    );
  });
}
