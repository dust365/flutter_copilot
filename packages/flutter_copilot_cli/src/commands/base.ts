import { Command } from 'commander';
import { VmServiceClient } from '../vm/client.js';
import { FlutterCopilotConnector } from '../vm/connector.js';
import * as log from '../logging.js';
import { SessionClient, SessionError, type AppInfo } from '../session/client.js';
import { chooseCandidates } from './sessions.js';

export interface GlobalOpts {
  uri?: string;
  app?: string;
  project?: string;
  timeout?: string;
  json?: boolean;
}

export interface TargetResolutionOpts extends GlobalOpts {
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  sessionCall?: (method: string, args: Record<string, unknown>) => Promise<AppInfo>;
}

export interface ResolvedTarget {
  uri: string;
  displayName: string;
  timeoutMs: number;
  refresh?: () => Promise<string>;
}

/** Reads global options from the root program, resolving the current app URI.
 *
 * Resolution precedence (first match wins):
 *   1. `--uri <ws>`
 *   2. `FLUTTER_COPILOT_URI` env var
 *   3. DTD discovery scoped to the current project (or --app)
 */
export async function resolveTargetFromOptions(
  opts: TargetResolutionOpts,
): Promise<ResolvedTarget> {
  const { uri } = opts;

  const timeoutSec = Number(opts.timeout ?? '5');
  if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) {
    throw new Error(`Invalid --timeout: ${opts.timeout}`);
  }
  const timeoutMs = timeoutSec * 1000;

  if (uri) {
    return { uri, displayName: uri, timeoutMs };
  }

  const env = opts.env ?? process.env;
  if (env.FLUTTER_COPILOT_URI?.trim() && !opts.app) {
    return { uri: env.FLUTTER_COPILOT_URI.trim(), displayName: '$FLUTTER_COPILOT_URI', timeoutMs };
  }
  const session = opts.sessionCall ? null : new SessionClient(opts.project ?? opts.cwd, env);
  const call = opts.sessionCall ?? ((method, args) => session!.call<AppInfo>(method, args));
  let app: AppInfo;
  try { app = await call('resolve', { app: opts.app }); } catch (e) {
    if (!(e instanceof SessionError) || opts.json) throw e;
    const selection = await chooseCandidates(e);
    if (selection.ids.length !== 1) throw new SessionError('selection_required', 'Choose one App for this command. Use fcc up to connect multiple Apps.', e.candidates);
    app = await call('resolve', { app: selection.ids[0] });
  }
  return { uri: app.uri, displayName: app.id, timeoutMs,
    refresh: async () => (await call('resolve', { app: app.id })).uri };
}

export async function resolveTarget(program: Command): Promise<ResolvedTarget> {
  return resolveTargetFromOptions(program.opts<GlobalOpts>());
}

/** Runs the callback with a connected target and closes the socket afterwards. */
export async function withConnector<T>(
  program: Command,
  fn: (
    connector: FlutterCopilotConnector,
    target: ResolvedTarget,
  ) => Promise<T>,
): Promise<T> {
  const target = await resolveTarget(program);
  const client = new VmServiceClient();
  const connector = new FlutterCopilotConnector(client);
  try {
    await connector.connect(target.uri, target.timeoutMs);
    log.dim(`connected: ${target.displayName} (${target.uri})`);
    return await fn(connector, target);
  } finally {
    try {
      await connector.disconnect();
    } catch {
      // ignore cleanup errors
    }
  }
}

/** Follow the selected logical session, without retrying or replaying gestures. */
export function followTarget(connector: FlutterCopilotConnector, target: ResolvedTarget): () => void {
  if (!target.refresh) return () => {};
  let stopped = false;
  let busy = false;
  let disconnected = false;
  const closed = () => { disconnected = true; };
  connector.client.on('close', closed);
  const timer = setInterval(async () => {
    if (busy || stopped) return;
    busy = true;
    try {
      const uri = await target.refresh!();
      if (!stopped && (uri !== target.uri || disconnected)) {
        await connector.reconnect(uri, target.timeoutMs);
        target.uri = uri;
        disconnected = false;
        log.info(`Reconnected ${target.displayName}`);
      }
    } catch (e) {
      // A stopped or ambiguous App must not silently switch to another target.
      if (e instanceof SessionError && e.code === 'selection_required') log.err(e.message, { code: e.code, candidates: e.candidates });
    } finally { busy = false; }
  }, 1000);
  return () => { stopped = true; clearInterval(timer); connector.client.off('close', closed); };
}
