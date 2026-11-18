import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { promises as fs, existsSync, realpathSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { VERSION } from '../version.generated.js';

export interface AppInfo {
  id: string;
  uri: string;
  name: string;
  deviceId: string | null;
  projectRoot: string | null;
  target?: string | null;
  platform?: string | null;
  owned: boolean;
}
export interface DeviceInfo {
  id: string;
  name: string;
  physical: boolean;
  targetPlatform: string;
  emulator: boolean;
}
export interface LaunchResult {
  deviceId?: string;
  state: 'queued' | 'launching' | 'connected' | 'reused' | 'failed';
  app?: AppInfo;
  error?: { code: string; message: string };
}
export interface LaunchOperation {
  operationId?: string;
  state: 'running' | 'completed';
  results: LaunchResult[];
}
export class SessionError extends Error {
  constructor(public readonly code: string, message: string,
    public readonly candidates: Array<Record<string, unknown>> = []) {
    super(message);
    this.name = 'SessionError';
  }
}
interface Endpoint {
  version: string;
  root: string;
  flutter: string;
  url: string;
  token: string;
}
export interface ProjectSdk { root: string; flutter: string; dart: string }

/** Resolve the nearest package and the same SDK policy used by the Dart engine. */
export function resolveProjectSdk(directory = process.cwd(), env = process.env): ProjectSdk {
  const input = realpathSync(path.resolve(directory));
  let root = input;
  for (let dir = input;; dir = path.dirname(dir)) {
    if (existsSync(path.join(dir, 'pubspec.yaml'))) { root = dir; break; }
    if (path.dirname(dir) === dir) break;
  }
  const binary = process.platform === 'win32' ? 'flutter.bat' : 'flutter';
  let flutter: string | undefined;
  for (let dir = input;; dir = path.dirname(dir)) {
    const candidate = path.join(dir, '.fvm', 'flutter_sdk', 'bin', binary);
    if (existsSync(candidate)) { flutter = realpathSync(candidate); break; }
    if (path.dirname(dir) === dir) break;
  }
  const search = [
    ...(env.FLUTTER_ROOT ? [path.join(env.FLUTTER_ROOT, 'bin')] : []),
    ...(env.PATH ?? '').split(path.delimiter),
  ];
  if (!flutter) for (const dir of search) {
    const candidate = path.join(dir, binary);
    if (existsSync(candidate)) { flutter = realpathSync(candidate); break; }
  }
  if (!flutter) throw new SessionError('sdk_not_found', 'Flutter SDK not found. Configure FVM, FLUTTER_ROOT or PATH.');
  const dart = path.join(path.dirname(flutter), 'cache', 'dart-sdk', 'bin', process.platform === 'win32' ? 'dart.exe' : 'dart');
  if (!existsSync(dart)) throw new SessionError('sdk_not_found', 'Initialize this Flutter SDK with flutter --version.');
  return { root, flutter, dart };
}
export function statePath(sdk: ProjectSdk): string {
  const key = createHash('sha256').update(`${sdk.root}\n${sdk.flutter}\n${VERSION}`).digest('hex').slice(0, 16);
  return path.join(sdk.root, '.dart_tool', 'flutter_copilot', `session-${key}.json`);
}

async function execute(executable: string, args: string[], cwd: string, timeoutMs = 120_000): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(executable, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    let output = '';
    const append = (data: Buffer) => { output = (output + data.toString()).slice(-6000); };
    child.stdout.on('data', append);
    child.stderr.on('data', append);
    const timer = setTimeout(() => { child.kill(); reject(new Error(`Backend setup timed out.\n${output}`)); }, timeoutMs);
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(); else reject(new Error(`Backend setup exited ${code}.\n${output}`));
    });
  });
}

async function prepareRuntime(sdk: ProjectSdk): Promise<string> {
  const source = fileURLToPath(new URL('../../runtime/', import.meta.url));
  if (!existsSync(path.join(source, 'manifest.json'))) {
    const script = fileURLToPath(new URL('../../scripts/prepare-runtime.mjs', import.meta.url));
    if (!existsSync(script)) throw new SessionError('runtime_missing', 'The npm package is missing its session runtime. Reinstall flutter_copilot_cli.');
    await execute(process.execPath, [script], path.dirname(script));
  }
  const manifest = JSON.parse(await fs.readFile(path.join(source, 'manifest.json'), 'utf8')) as { hash: string };
  const sdkKey = createHash('sha256').update(sdk.dart).digest('hex').slice(0, 12);
  const cacheHome = process.env.FLUTTER_COPILOT_CACHE ?? path.join(
    process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), '.cache'), 'flutter_copilot');
  const runtime = path.join(cacheHome, `${manifest.hash.slice(0, 20)}-${sdkKey}`);
  const ready = path.join(runtime, '.dart_tool', 'package_config.json');
  if (existsSync(ready)) return runtime;
  await fs.mkdir(cacheHome, { recursive: true });
  const lock = `${runtime}.lock`;
  const deadline = Date.now() + 150_000;
  while (true) {
    try { await fs.mkdir(lock); break; } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== 'EEXIST') throw e;
      if (existsSync(ready)) return runtime;
      const stat = await fs.stat(lock).catch(() => null);
      if (stat && Date.now() - stat.mtimeMs > 140_000) { await fs.rm(lock, { recursive: true, force: true }); continue; }
      if (Date.now() > deadline) throw new SessionError('backend_unavailable', 'Timed out waiting for session runtime setup.');
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  try {
    if (!existsSync(ready)) {
      await fs.cp(source, runtime, { recursive: true });
      await execute(sdk.dart, ['pub', 'get', '--enforce-lockfile', '--no-precompile'], runtime);
    }
    return runtime;
  } finally { await fs.rm(lock, { recursive: true, force: true }); }
}

export class SessionClient {
  readonly sdk: ProjectSdk;
  constructor(directory = process.cwd(), env = process.env) { this.sdk = resolveProjectSdk(directory, env); }
  private starting?: Promise<Endpoint>;

  private async existing(): Promise<Endpoint | null> {
    try {
      const endpoint = JSON.parse(await fs.readFile(statePath(this.sdk), 'utf8')) as Endpoint;
      if (endpoint.version !== VERSION || endpoint.root !== this.sdk.root || endpoint.flutter !== this.sdk.flutter) return null;
      await SessionClient.request(endpoint, 'hello', {}, 2000);
      return endpoint;
    } catch { return null; }
  }
  private endpoint(): Promise<Endpoint> {
    return this.starting ??= this.ensure().finally(() => { this.starting = undefined; });
  }
  private async ensure(): Promise<Endpoint> {
    const existing = await this.existing();
    if (existing) return existing;
    const runtime = await prepareRuntime(this.sdk);
    const state = statePath(this.sdk);
    await fs.mkdir(path.dirname(state), { recursive: true });
    const logfile = `${state}.log`;
    const log = await fs.open(logfile, 'a', 0o600);
    try {
      const child = spawn(this.sdk.dart, [
        `--packages=${path.join(runtime, '.dart_tool', 'package_config.json')}`,
        path.join(runtime, 'bin', 'flutter_copilot_session.dart'), '--directory', this.sdk.root,
      ], { cwd: this.sdk.root, detached: true, stdio: ['ignore', log.fd, log.fd], windowsHide: true });
      await new Promise<void>((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
      child.unref();
    } finally { await log.close(); }
    const deadline = Date.now() + 20_000;
    while (Date.now() < deadline) {
      const endpoint = await this.existing();
      if (endpoint) return endpoint;
      await new Promise((r) => setTimeout(r, 100));
    }
    const tail = (await fs.readFile(logfile, 'utf8').catch(() => '')).slice(-4000);
    throw new SessionError('backend_unavailable', `Session backend did not start. See ${logfile}\n${tail}`);
  }
  async call<T = Record<string, unknown>>(method: string, args: Record<string, unknown> = {}): Promise<T> {
    return SessionClient.request<T>(await this.endpoint(), method, args);
  }
  static async request<T>(endpoint: Endpoint, method: string, args: Record<string, unknown>, timeout = 60_000): Promise<T> {
    const uri = new URL(endpoint.url);
    if (uri.protocol !== 'http:' || uri.hostname !== '127.0.0.1' || uri.pathname !== '/rpc') {
      throw new SessionError('invalid_endpoint', 'Invalid local session endpoint');
    }
    const response = await fetch(uri, {
      method: 'POST', headers: { 'Authorization': `Bearer ${endpoint.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params: args }), signal: AbortSignal.timeout(timeout),
    });
    if (!response.ok) throw new SessionError('backend_unavailable', `Session HTTP error ${response.status}`);
    const message = await response.json() as { result: T; error?: { message: string; data?: { code?: string; candidates?: Array<Record<string, unknown>> } } };
    if (message.error) throw new SessionError(message.error.data?.code ?? 'session_error', message.error.message, message.error.data?.candidates);
    return message.result;
  }
}
