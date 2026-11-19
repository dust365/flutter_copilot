import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:test/test.dart';
import 'mock_dtd.dart';
import 'mock_vm_server.dart';

Future<void> eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('State did not converge');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A DtdRegistry whose machine listing reports [dtdUri] as the only DTD.
DtdRegistry listingRegistry(AppDirectory apps, String dtdUri) =>
    DtdRegistry(apps,
        run: (_, __) async => ProcessResult(
            0,
            0,
            jsonEncode([
              {'wsUri': dtdUri, 'workspaceRoot': '/project'}
            ]),
            ''));

void main() {
  late AppDirectory apps;
  late DtdRegistry registry;
  late MockDtd dtd;
  late MockVmServer first;
  late MockVmServer second;
  setUp(() async {
    apps = AppDirectory();
    registry = DtdRegistry(apps);
    dtd = await MockDtd.start();
    first = await MockVmServer.start();
    second = await MockVmServer.start();
  });
  tearDown(() async {
    await registry.close();
    await apps.close();
    await dtd.close();
    await first.close();
    await second.close();
  });
  test(
      'snapshot and subsequent same-name registration do not replace each other',
      () async {
    dtd.apps.add({'uri': first.wsUri, 'name': 'Flutter'});
    await registry.connect(dtd.uri);
    dtd.event('VmServiceRegistered', {'uri': second.wsUri, 'name': 'Flutter'});
    await eventually(() => apps.sessions.length == 2);
    expect(apps.sessions.map((s) => s.uri),
        containsAll([first.wsUri, second.wsUri]));
    expect(apps.sessions.map((s) => s.id).toSet(), hasLength(2));
  });
  test('simultaneous snapshots create one connector for each VM', () async {
    dtd.apps.add({'uri': first.wsUri, 'name': 'Flutter'});
    await Future.wait([registry.connect(dtd.uri), registry.connect(dtd.uri)]);
    expect(apps.sessions, hasLength(1));
  });
  test('unregister during extension initialization cannot resurrect an App',
      () async {
    await registry.connect(dtd.uri);
    first.hideExtensionForCalls = 2;
    dtd.event('VmServiceRegistered', {'uri': first.wsUri, 'name': 'Flutter'});
    await eventually(() => first.lastCallTo('getIsolate') != null);
    dtd.event('VmServiceUnregistered', {'uri': first.wsUri, 'name': 'Flutter'});
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(apps.sessions, isEmpty);
  });
  test('one dead VM does not hide other Apps in the snapshot', () async {
    dtd.apps.addAll([
      {'uri': 'ws://127.0.0.1:1/ws', 'name': 'dead'},
      {'uri': second.wsUri, 'name': 'alive'},
    ]);
    await registry.connect(dtd.uri);
    expect(apps.sessions.single.uri, second.wsUri);
    expect(registry.diagnostics, isNotEmpty);
  });
  test('a closed DTD can be rediscovered at a new endpoint', () async {
    dtd.apps.add({'uri': first.wsUri});
    await registry.connect(dtd.uri);
    await dtd.close();
    final replacement = await MockDtd.start();
    addTearDown(replacement.close);
    replacement.apps.add({'uri': second.wsUri});
    await registry.connect(replacement.uri);
    expect(apps.sessions.map((s) => s.uri), contains(second.wsUri));
  });
  test('a suppressed App is not adopted by a later registration', () async {
    dtd.apps.add({'uri': first.wsUri, 'name': 'Flutter'});
    apps.suppress(first.wsUri);
    await registry.connect(dtd.uri);
    expect(apps.sessions, isEmpty);

    apps.unsuppress(first.wsUri);
    await registry.connect(dtd.uri);
    expect(apps.sessions.single.uri, first.wsUri);
  });
  test('a disconnected DTD stays down through refresh until connected again',
      () async {
    final discovering = listingRegistry(apps, dtd.uri);
    addTearDown(discovering.close);
    dtd.apps.add({'uri': first.wsUri, 'name': 'Flutter'});
    await discovering.connect(dtd.uri);
    expect(apps.sessions, hasLength(1));

    await discovering.disconnect(dtd.uri);
    expect(apps.sessions, isEmpty);

    // Discovery would reconnect this DTD unless the disconnect holds.
    await discovering.refresh();
    expect(apps.sessions, isEmpty);

    await discovering.connect(dtd.uri);
    expect(apps.sessions.single.uri, first.wsUri);
  });
}
