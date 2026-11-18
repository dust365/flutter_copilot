import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtemp, mkdir, writeFile, rm, realpath } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createServer } from 'node:http';
import { parseSelection } from '../src/commands/sessions.js';
import { SessionClient, SessionError, resolveProjectSdk, statePath } from '../src/session/client.js';
import { resolveTargetFromOptions } from '../src/commands/base.js';

let directory: string;
beforeEach(async () => { directory = await realpath(await mkdtemp(path.join(os.tmpdir(), 'fcc-session-'))); });
afterEach(async () => { await rm(directory, { recursive: true, force: true }); });

const app = { id: 'phone', uri: 'ws://127.0.0.1:1234/ws', name: 'Flutter', deviceId: 'device', projectRoot: '/project', owned: false };

describe('live target selection', () => {
  it('live discovery selects an active session', async () => {
    const target = await resolveTargetFromOptions({ cwd: directory, env: {}, sessionCall: async () => app });
    expect(target.uri).toBe(app.uri);
    expect(target.displayName).toBe('phone');
  });
  it('rediscovery follows the selected id and picks up a changed URI', async () => {
    let uri = app.uri;
    const target = await resolveTargetFromOptions({ cwd: directory, env: {}, sessionCall: async (_method, args) => {
      if (args.app) expect(args.app).toBe(app.id);
      return { ...app, uri };
    } });
    uri = 'ws://127.0.0.1:2222/ws';
    expect(await target.refresh!()).toBe(uri);
  });
  it('ambiguity returns candidates without selecting an arbitrary session', async () => {
    await expect(resolveTargetFromOptions({ cwd: directory, env: {}, json: true, sessionCall: async () => {
      throw new SessionError('selection_required', 'Choose an App', [app, { ...app, id: 'tablet' }]);
    } })).rejects.toMatchObject({ code: 'selection_required', candidates: expect.any(Array) });
  });
  it('ignores an old URI file when no live App can be resolved', async () => {
    await writeFile(path.join(directory, '.vm_service_uri'), 'ws://wrong/ws');
    await expect(resolveTargetFromOptions({ cwd: directory, env: {}, sessionCall: async () => {
      throw new SessionError('app_not_found', 'App disappeared');
    } })).rejects.toMatchObject({ code: 'app_not_found' });
  });
  it('explicit --app overrides an unrelated URI environment default', async () => {
    const target = await resolveTargetFromOptions({ app: 'phone', env: { FLUTTER_COPILOT_URI: 'ws://wrong/ws' }, sessionCall: async (_method, args) => {
      expect(args.app).toBe('phone'); return app;
    } });
    expect(target.uri).toBe(app.uri);
  });
});

describe('device selection', () => {
  const candidates = [{ id: 'usb' }, { id: 'wifi' }, { id: 'iphone' }];
  it('allows selecting one or multiple devices without duplicate launches', () => {
    expect(parseSelection('1,3,1', candidates)).toEqual(['usb', 'iphone']);
    expect(parseSelection('2', candidates)).toEqual(['wifi']);
  });
  it('rejects empty and out-of-range selections', () => {
    for (const value of ['', '0', '4', '1.2', 'abc']) expect(() => parseSelection(value, candidates)).toThrow();
  });
});

describe('SDK and IPC', () => {
  it('prefers project FVM over PATH and pairs Dart from the same SDK', async () => {
    const sdkRoot = path.join(directory, '.fvm/flutter_sdk');
    await mkdir(path.join(sdkRoot, 'bin/cache/dart-sdk/bin'), { recursive: true });
    const flutter = path.join(sdkRoot, 'bin', process.platform === 'win32' ? 'flutter.bat' : 'flutter');
    const dart = path.join(sdkRoot, 'bin/cache/dart-sdk/bin', process.platform === 'win32' ? 'dart.exe' : 'dart');
    await writeFile(flutter, ''); await writeFile(dart, '');
    await writeFile(path.join(directory, 'pubspec.yaml'), 'name: app\n');
    const sdk = resolveProjectSdk(directory, {});
    expect(sdk.flutter).toBe(flutter);
    expect(sdk.dart).toBe(dart);
    expect(statePath(sdk)).toContain('.dart_tool');
    expect(statePath({ ...sdk, flutter: '/other/sdk/flutter' })).not.toBe(statePath(sdk));
  });
  it('sends authenticated requests and preserves structured selection errors', async () => {
    const server = createServer(async (request, response) => {
      expect(request.headers.authorization).toBe('Bearer secret');
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(chunk as Buffer);
      const message = JSON.parse(Buffer.concat(chunks).toString()) as { method: string };
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify(message.method === 'hello' ? { result: { protocol: 1 } } : {
        error: { message: 'Choose', data: { code: 'selection_required', candidates: [app] } },
      }));
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address() as { port: number };
    const endpoint = { url: `http://127.0.0.1:${address.port}/rpc`, token: 'secret', version: '', root: '', flutter: '' };
    try {
      expect(await SessionClient.request(endpoint, 'hello', {})).toEqual({ protocol: 1 });
      await expect(SessionClient.request(endpoint, 'resolve', {})).rejects.toMatchObject({ code: 'selection_required', candidates: [app] });
      await expect(SessionClient.request({ ...endpoint, url: 'http://example.com/rpc' }, 'hello', {})).rejects.toMatchObject({ code: 'invalid_endpoint' });
    } finally { await new Promise<void>((resolve) => server.close(() => resolve())); }
  });
});
