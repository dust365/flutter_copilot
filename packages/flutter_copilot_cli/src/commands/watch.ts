import { Command } from 'commander';
import chalk from 'chalk';
import { InstanceRegistry } from '../registry/instance_registry.js';
import { withConnector, reconnectWithBackoff } from './base.js';
import type { VmEvent } from '../vm/client.js';
import { UriFileWatcher } from '../vm/uri_watcher.js';
import * as log from '../logging.js';
import { getOutputMode } from '../logging.js';

/**
 * Streams real-time telemetry from a connected Flutter app:
 *   --logs     Stdout/Stderr/Extension events (via streamListen)
 *   --rebuilds Polled rebuild snapshot at --interval ms
 *
 * At least one source must be enabled.
 */
export function watchCommand(program: Command, registry: InstanceRegistry): void {
  program
    .command('watch')
    .description('Stream live logs and/or rebuild snapshots from the app until Ctrl-C.')
    .option('--logs', 'Stream Stdout / Stderr / Extension events.')
    .option('--rebuilds', 'Poll rebuild snapshots.')
    .option('--interval <ms>', 'Rebuild poll interval (ms).', '1000')
    .action(async (opts: { logs?: boolean; rebuilds?: boolean; interval: string }) => {
      if (!opts.logs && !opts.rebuilds) {
        throw new Error('Pass at least one of --logs / --rebuilds.');
      }

      await withConnector(program, registry, async (connector, target) => {
        const client = connector.client;

        let rebuildTimer: NodeJS.Timeout | null = null;

        // Install Ctrl-C handler
        const stop = new Promise<void>((resolve) => {
          const handler = () => {
            process.stderr.write('\n');
            log.info('stopping...');
            resolve();
          };
          process.once('SIGINT', handler);
        });

        if (opts.logs) {
          for (const stream of ['Stdout', 'Stderr', 'Extension']) {
            // Use connector.streamListen so --watch-uri can replay after reconnect.
            await connector.streamListen(stream);
          }
          client.on('event', (streamId: string, e: VmEvent) => printLogEvent(streamId, e));
          log.info('listening for Stdout/Stderr/Extension events (Ctrl-C to stop)');
        }

        if (opts.rebuilds) {
          const interval = Math.max(100, Number(opts.interval));
          const tick = async () => {
            try {
              const snap = await connector.getRebuildSnapshot(10);
              printRebuildSnapshot(snap);
            } catch (e) {
              log.err(`rebuild snapshot failed: ${(e as Error).message}`);
            }
          };
          await tick();
          rebuildTimer = setInterval(tick, interval);
          log.info(`polling rebuild snapshot every ${interval}ms (Ctrl-C to stop)`);
        }

        // --watch-uri: auto-reconnect when .vm_service_uri content changes.
        const watchUri = program.opts<{ watchUri?: boolean }>().watchUri === true;
        let uriWatcher: UriFileWatcher | null = null;
        if (watchUri) {
          if (!target.autoUriPath) {
            process.stderr.write(
              chalk.yellow(
                '! --watch-uri requires URI auto-detection; ignored because --uri / -i was used.\n',
              ),
            );
          } else {
            uriWatcher = new UriFileWatcher(target.autoUriPath);
            uriWatcher.on('change', async (newUri: string) => {
              process.stderr.write(chalk.yellow(`\n⟳ reconnecting: ${newUri}\n`));
              try {
                await reconnectWithBackoff(connector, newUri, target.timeoutMs);
                process.stderr.write(chalk.green(`✓ reconnected\n`));
              } catch (e) {
                process.stderr.write(
                  chalk.red(`✗ reconnect failed: ${(e as Error).message}\n`),
                );
              }
            });
            await uriWatcher.start();
            log.info(`watching ${target.autoUriPath} for URI changes`);
          }
        }

        await stop;
        uriWatcher?.stop();
        if (rebuildTimer) clearInterval(rebuildTimer);
      });
    })
    .addHelpText(
      'after',
      `
Examples:
  # Tail only logs
  fcc watch --logs

  # Tail logs and rebuild counts together
  fcc watch --logs --rebuilds --interval 500

  # Survive \`flutter run\` restarts: auto-reconnect when .vm_service_uri changes
  fcc --watch-uri watch --logs --rebuilds

\`--watch-uri\` is a global flag; it requires URI auto-detection (ignored when
\`--uri\` or \`-i\` is passed).
`,
    );
}

function printLogEvent(streamId: string, e: VmEvent): void {
  const isJson = getOutputMode() === 'json';
  // `WriteEvent` (Stdout/Stderr) carries base64 `bytes`; `ExtensionEvent` doesn't.
  const bytes = e['bytes'];
  const text =
    typeof bytes === 'string'
      ? Buffer.from(bytes, 'base64').toString('utf8').trimEnd()
      : null;

  if (isJson) {
    // NDJSON line per event — stable keys for `jq`/downstream tooling.
    const payload: Record<string, unknown> = {
      ts: new Date().toISOString(),
      stream: streamId,
      kind: e['kind'] ?? null,
    };
    if (text !== null) payload['text'] = text;
    if (typeof e['extensionKind'] === 'string') payload['extensionKind'] = e['extensionKind'];
    if (e['extensionData'] !== undefined) payload['extensionData'] = e['extensionData'];
    process.stdout.write(JSON.stringify(payload) + '\n');
    return;
  }

  const ts = new Date().toISOString().slice(11, 19);
  const label =
    streamId === 'Stderr'
      ? chalk.red(streamId)
      : streamId === 'Extension'
        ? chalk.magenta(streamId)
        : chalk.cyan(streamId);
  if (text !== null) {
    process.stdout.write(`${chalk.gray(ts)} [${label}] ${text}\n`);
    return;
  }
  // ExtensionEvent — compact kind/data JSON.
  process.stdout.write(`${chalk.gray(ts)} [${label}] ${JSON.stringify(e)}\n`);
}

function printRebuildSnapshot(snap: Record<string, unknown>): void {
  const isJson = getOutputMode() === 'json';
  if (isJson) {
    process.stdout.write(
      JSON.stringify({ ts: new Date().toISOString(), kind: 'rebuild', snapshot: snap }) + '\n',
    );
    return;
  }
  if (snap['enabled'] === false) {
    process.stdout.write(
      chalk.gray('[rebuild] tracker disabled — enable with FlutterCopilotConfiguration(enableGlobalRebuildHook: true)\n'),
    );
    return;
  }
  const total = snap['totalRebuilds'] ?? snap['total'] ?? '?';
  const frame = snap['frame'] ?? '?';
  const top = snap['top'];
  process.stdout.write(
    `${chalk.gray(new Date().toISOString().slice(11, 19))} ${chalk.yellow('[rebuild]')} frame=${frame} total=${total}\n`,
  );
  if (Array.isArray(top)) {
    for (const row of top.slice(0, 5)) {
      process.stdout.write(`  ${JSON.stringify(row)}\n`);
    }
  }
}
