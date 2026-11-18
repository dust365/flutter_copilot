import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/process/flutter_run_manager.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/session_engine.dart';
import 'package:flutter_copilot_mcp/src/session/session_error.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mock_vm_server.dart';

class EmptyRegistry extends DtdRegistry {
  EmptyRegistry(super.apps);
  @override
  Future<void> refresh() async {}
}

Future<Map<String, dynamic>> completeOperation(
    SessionEngine engine, Map<String, dynamic> operation) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (operation['state'] == 'running') {
    if (DateTime.now().isAfter(deadline))
      fail('Operation did not finish: $operation');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    operation = await engine
            .call('operation_status', {'operationId': operation['operationId']})
        as Map<String, dynamic>;
  }
  return operation;
}

void main() {
  late Directory project;
  late SessionEngine engine;
  late AppDirectory apps;
  setUp(() async {
    project = await Directory.systemTemp.createTemp('copilot-session-');
    project = Directory(await project.resolveSymbolicLinks());
    await Directory(p.join(project.path, 'android')).create();
    await Directory(p.join(project.path, 'lib')).create();
    await File(p.join(project.path, 'pubspec.yaml'))
        .writeAsString('name: fixture\n');
    await File(p.join(project.path, 'lib/main.dart'))
        .writeAsString('void main() {}');
    final fixture = p.absolute('test/fixtures/flutter_machine.dart');
    final executable = File(p.join(project.path, 'flutter'));
    await executable.writeAsString(
        '#!/bin/sh\nexec "${Platform.resolvedExecutable}" "$fixture" "\$@"\n');
    if (!Platform.isWindows)
      await Process.run('chmod', ['+x', executable.path]);
    final sdk =
        SdkTools(flutter: executable.path, dart: Platform.resolvedExecutable);
    apps = AppDirectory();
    final dtds = EmptyRegistry(apps);
    final runs = FlutterRunManager(
        apps: apps, dtds: dtds, sdk: sdk, identifyAndroid: (_) async => null);
    engine = SessionEngine(
        root: project.path, sdk: sdk, apps: apps, dtds: dtds, runs: runs);
  });
  tearDown(() async {
    await engine.close();
    await project.delete(recursive: true);
  });

  test('ambiguous physical devices require explicit selection before launch',
      () async {
    await expectLater(
        engine.call('ensure_apps', {}),
        throwsA(isA<SessionError>()
            .having((e) => e.code, 'code', 'selection_required')
            .having((e) => e.candidates.length, 'candidates', 3)));
    expect(File(p.join(project.path, 'trace')).existsSync(), isFalse);
  });

  test(
      'cold launch connects without DTD, and identical requests share one operation',
      () async {
    final operations = await Future.wait([
      engine.call('ensure_apps', {
        'deviceIds': ['phone-a']
      }),
      engine.call('ensure_apps', {
        'deviceIds': ['phone-a']
      }),
    ]);
    expect(operations[0]['operationId'], operations[1]['operationId']);
    final operation = await completeOperation(
        engine, operations.first as Map<String, dynamic>);
    final result = (operation['results'] as List).single as Map;
    expect(result['state'], 'connected');
    expect(result['app']['owned'], isTrue);
    expect(result['app']['projectRoot'], project.path);
    expect(apps.sessions, hasLength(1));
    final trace = await File(p.join(project.path, 'trace')).readAsLines();
    expect(trace.where((line) => line.startsWith('launch:')), hasLength(1));
    final reused = await engine.call('ensure_apps', {
      'deviceIds': ['phone-a']
    }) as Map;
    final completed =
        await completeOperation(engine, Map<String, dynamic>.from(reused));
    expect((completed['results'] as List).single['state'], 'reused');
  }, skip: Platform.isWindows ? 'POSIX fixture executable' : false);

  test(
      'partial device failure preserves connected Apps and reports both outcomes',
      () async {
    final operation = await completeOperation(
        engine,
        await engine.call('ensure_apps', {
          'deviceIds': ['broken', 'phone-b']
        }) as Map<String, dynamic>);
    final results = operation['results'] as List;
    expect(results[0]['state'], 'failed');
    expect(results[0]['error']['message'], contains('fixture build failed'));
    expect(results[1]['state'], 'connected');
    expect(apps.sessions, hasLength(1));
  }, skip: Platform.isWindows ? 'POSIX fixture executable' : false);

  test('stop and detach dispatch different machine commands', () async {
    for (final method in ['detach_app', 'stop_app']) {
      final operation = await completeOperation(
          engine,
          await engine.call('ensure_apps', {
            'deviceIds': ['phone-a']
          }) as Map<String, dynamic>);
      final app = (operation['results'] as List).single['app'] as Map;
      await engine.call(method, {'app': app['id']});
      expect(apps.sessions, isEmpty);
    }
    final trace = await File(p.join(project.path, 'trace')).readAsString();
    expect(trace, contains('app.detach:phone-a'));
    expect(trace, contains('app.stop:phone-a'));
  }, skip: Platform.isWindows ? 'POSIX fixture executable' : false);

  test('owned run remains owned and stoppable across disconnect', () async {
    final operation = await completeOperation(
        engine,
        await engine.call('ensure_apps', {
          'deviceIds': ['phone-a']
        }) as Map<String, dynamic>);
    final app = (operation['results'] as List).single['app'] as Map;
    final id = app['id'];
    await engine.call('disconnect', {'app': id});
    expect(apps.sessions, isEmpty);
    final reconnected = await engine.call('connect', {'uri': app['uri']});
    expect(reconnected['id'], id);
    expect(reconnected['owned'], isTrue);
    expect(reconnected['deviceId'], 'phone-a');
    await engine.call('disconnect', {'app': id});
    await engine.call('stop_app', {'app': id});
    expect(await File(p.join(project.path, 'trace')).readAsString(),
        contains('app.stop:phone-a'));
  }, skip: Platform.isWindows ? 'POSIX fixture executable' : false);

  test('an external App can be reused but cannot be stopped', () async {
    final vm = await MockVmServer.start();
    addTearDown(vm.close);
    final app = await apps.connectUri(
        uri: vm.wsUri, id: 'ide', projectRoot: project.path);
    final result = await engine.call('ensure_apps', {});
    expect(result['results'][0]['app']['id'], app.id);
    await expectLater(
        engine.call('stop_app', {'app': 'ide'}),
        throwsA(isA<SessionError>()
            .having((e) => e.code, 'code', 'external_session')));
    expect(app.connector.isConnected, isTrue);
  });

  test('scoped discovery never chooses another project', () async {
    final vm = await MockVmServer.start();
    addTearDown(vm.close);
    await apps.connectUri(
        uri: vm.wsUri, id: 'other', projectRoot: '/different/project');
    final listing = await engine.call('list_apps', {});
    expect(listing['apps'], isEmpty);
    await expectLater(engine.call('resolve', {}), throwsA(isA<SessionError>()));
  });

  test(
      'same names on different devices remain separate and an ambiguous name is rejected',
      () async {
    final vms = await Future.wait([MockVmServer.start(), MockVmServer.start()]);
    for (final vm in vms) {
      addTearDown(vm.close);
    }
    await apps.connectUri(
        uri: vms[0].wsUri,
        projectRoot: project.path,
        displayName: 'Flutter',
        deviceId: 'one');
    await apps.connectUri(
        uri: vms[1].wsUri,
        projectRoot: project.path,
        displayName: 'Flutter',
        deviceId: 'two');
    expect(apps.sessions, hasLength(2));
    await expectLater(
        engine.call('resolve', {'app': 'Flutter'}),
        throwsA(isA<SessionError>()
            .having((e) => e.code, 'code', 'selection_required')));
  });

  test('only verified device identity restores an App id after restart',
      () async {
    final first = await MockVmServer.start();
    final second = await MockVmServer.start();
    addTearDown(first.close);
    addTearDown(second.close);
    final old = await apps.connectUri(
        uri: first.wsUri,
        id: 'phone',
        deviceId: 'device',
        projectRoot: project.path,
        target: 'main');
    await engine.call('list_apps', {});
    await apps.removeSession(old);
    await apps.connectUri(
        uri: second.wsUri,
        deviceId: 'device',
        projectRoot: project.path,
        target: 'main');
    await engine.discover(force: true);
    expect(apps.sessions.single.id, 'phone');
  });

  test('machine DTD listing is parsed, ignoring invalid individual entries',
      () async {
    final registry = DtdRegistry(apps, run: (_, args) async {
      expect(args, ['tooling-daemon', '--list', '--machine']);
      return ProcessResult(
          0,
          0,
          jsonEncode([
            {'wsUri': 'ws://127.0.0.1:1/token', 'workspaceRoot': '/old'},
            {
              'wsUri': 'ws://127.0.0.1:2/token',
              'workingDirectory': '/cwd',
              'workspaceRoots': ['/one', 'file:///two']
            },
            {'wsUri': 'http://invalid'},
          ]),
          '');
    });
    final result = await registry.instances();
    expect(result, hasLength(2));
    expect(result[1].roots, ['/cwd', '/one', '/two']);
  });
}
