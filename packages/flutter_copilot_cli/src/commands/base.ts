import { Command } from 'commander';
import { VmServiceClient } from '../vm/client.js';
import { FlutterCopilotConnector } from '../vm/connector.js';
import { InstanceRegistry } from '../registry/instance_registry.js';
import { autoDetectVmServiceUri } from '../registry/auto_uri.js';
import * as log from '../logging.js';

export interface GlobalOpts {
  instance?: string;
  uri?: string;
  timeout?: string;
  json?: boolean;
  /** commander: `--no-auto-uri` sets this to `false`; default is `true`. */
  autoUri?: boolean;
  /** Enable .vm_service_uri auto-reconnect (repl/watch only). */
  watchUri?: boolean;
}

export interface ResolvedTarget {
  uri: string;
  displayName: string;
  timeoutMs: number;
  /** Non-null when URI was sourced from a `.vm_service_uri` file. */
  autoUriPath?: string;
}

/** Reads global options from the root program, resolving the URI via registry
 * or `.vm_service_uri` auto-detection if needed.
 *
 * Resolution precedence (first match wins):
 *   1. `--uri <ws>`
 *   2. `-i <name>` from registry
 *   3. `FLUTTER_COPILOT_URI` env var   (auto)
 *   4. nearest `.vm_service_uri` file  (auto; written by scripts/flutter_run.sh)
 *
 * The auto path can be disabled per-invocation with `--no-auto-uri`.
 */
export async function resolveTarget(
  program: Command,
  registry: InstanceRegistry,
): Promise<ResolvedTarget> {
  const opts = program.opts<GlobalOpts>();
  const { instance, uri } = opts;

  if (instance && uri) {
    throw new Error('--instance and --uri are mutually exclusive.');
  }

  const timeoutSec = Number(opts.timeout ?? '5');
  if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) {
    throw new Error(`Invalid --timeout: ${opts.timeout}`);
  }
  const timeoutMs = timeoutSec * 1000;

  if (uri) {
    return { uri, displayName: uri, timeoutMs };
  }

  if (instance) {
    const info = await registry.get(instance);
    if (!info) {
      throw new Error(
        `Instance "${instance}" not found. Use \`fcc list\` to see registered instances.`,
      );
    }
    return { uri: info.uri, displayName: instance, timeoutMs };
  }

  if (opts.autoUri !== false) {
    const auto = await autoDetectVmServiceUri();
    if (auto) {
      const displayName =
        auto.source === 'env'
          ? `$FLUTTER_COPILOT_URI`
          : `auto:${auto.path ?? '.vm_service_uri'}`;
      const base: ResolvedTarget = { uri: auto.uri, displayName, timeoutMs };
      if (auto.source === 'file' && auto.path) base.autoUriPath = auto.path;
      return base;
    }
  }

  throw new Error(
    'No VM Service URI. Provide one of:\n' +
      '  --uri ws://...\n' +
      '  -i <instance>      (see `fcc list`)\n' +
      '  FLUTTER_COPILOT_URI env var\n' +
      '  .vm_service_uri file in this or any parent directory',
  );
}

/** Runs `fn` with a connected connector; handles cleanup and pretty errors.
 *  The callback also receives the resolved target in case it needs access to
 *  `autoUriPath` (for `--watch-uri` auto-reconnect). */
export async function withConnector<T>(
  program: Command,
  registry: InstanceRegistry,
  fn: (
    connector: FlutterCopilotConnector,
    target: ResolvedTarget,
  ) => Promise<T>,
): Promise<T> {
  const target = await resolveTarget(program, registry);
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

/** Exponential-backoff reconnect helper used by `--watch-uri`.
 *  Tries [100, 200, 400, 800, 1600] ms before giving up for this cycle. */
export async function reconnectWithBackoff(
  connector: FlutterCopilotConnector,
  newUri: string,
  timeoutMs: number,
): Promise<void> {
  const delays = [100, 200, 400, 800, 1600];
  let lastErr: unknown = null;
  for (let i = 0; i < delays.length; i++) {
    try {
      await connector.reconnect(newUri, timeoutMs);
      return;
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, delays[i]!));
    }
  }
  throw lastErr ?? new Error(`Unable to reconnect to ${newUri}`);
}
