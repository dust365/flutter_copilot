import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';
import 'package:test/test.dart';

void main() {
  test('converts the http address printed by flutter run', () {
    expect(
      normalizeVmServiceUri('http://127.0.0.1:8181/AbC=/'),
      'ws://127.0.0.1:8181/AbC=/ws',
    );
  });

  test('leaves a websocket URI that already ends in /ws alone', () {
    expect(
      normalizeVmServiceUri('ws://127.0.0.1:8181/AbC=/ws'),
      'ws://127.0.0.1:8181/AbC=/ws',
    );
  });

  test('appends /ws when the token has no trailing slash', () {
    expect(
      normalizeVmServiceUri('ws://127.0.0.1:8181/AbC='),
      'ws://127.0.0.1:8181/AbC=/ws',
    );
  });

  test('rejects a non-local DTD address', () {
    expect(
      () => canonicalDtdUri('ws://example.com/token'),
      throwsFormatException,
    );
  });

  test('rejects an http address passed as a DTD', () {
    expect(
      () => canonicalDtdUri('http://127.0.0.1:8181/AbC=/'),
      throwsFormatException,
    );
  });

  test('accepts a loopback DTD websocket URI', () {
    expect(
      canonicalDtdUri('ws://127.0.0.1:54321/secret'),
      'ws://127.0.0.1:54321/secret',
    );
  });
}
