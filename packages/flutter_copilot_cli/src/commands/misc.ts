import { Command } from 'commander';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { InstanceRegistry } from '../registry/instance_registry.js';
import { withConnector } from './base.js';
import { resolveShotPath } from '../screenshot_path.js';
import * as log from '../logging.js';

export function miscCommands(program: Command, registry: InstanceRegistry): void {
  // elements
  program
    .command('elements')
    .description('List the tree of interactive elements currently on screen.')
    .action(async () => {
      await withConnector(program, registry, async (c) => {
        const r = await c.getInteractiveElements();
        log.data(r, () => {
          process.stdout.write(JSON.stringify(r['elements'] ?? r, null, 2) + '\n');
        });
      });
    })
    .addHelpText(
      'after',
      `
Emits a JSON tree with each node's type, key, visible text, and bounds.
Pipe to jq to filter:
  fcc --json elements | jq '.elements'
`,
    );

  // hot-reload
  program
    .command('hot-reload')
    .description('Trigger a Flutter hot reload on the connected app.')
    .action(async () => {
      await withConnector(program, registry, async (c) => {
        const success = await c.hotReload();
        if (success) {
          log.ok('hot reload succeeded', { success: true });
        } else {
          log.err('hot reload reported failure', { success: false });
          process.exitCode = 1;
        }
      });
    })
    .addHelpText(
      'after',
      `
Works under DDS (standard \`flutter run\`) — the CLI waits for the DDS-registered
\`reloadSources\` method and prefers it over the plain VM Service call.
Exits 1 on failure.
`,
    );

  // logs
  program
    .command('logs')
    .description('Fetch the in-app log buffer captured by flutter_copilot_claw.')
    .option('--limit <n>', 'Only print the last N entries.')
    .action(async (opts: { limit?: string }) => {
      await withConnector(program, registry, async (c) => {
        const r = await c.getLogs();
        const entries = Array.isArray(r.logs) ? r.logs : [];
        const limit = opts.limit ? Math.max(0, Number(opts.limit)) : entries.length;
        const slice = entries.slice(Math.max(0, entries.length - limit));
        log.data({ count: slice.length, logs: slice }, () => {
          for (const entry of slice) {
            process.stdout.write(
              typeof entry === 'string' ? entry + '\n' : JSON.stringify(entry) + '\n',
            );
          }
        });
      });
    })
    .addHelpText(
      'after',
      `
Requires \`FlutterCopilotBinding.runAppWithConfig(...)\` on the Flutter side so
\`print\` output and zone errors are captured into the shared log buffer.
For a live feed use \`watch --logs\` instead.
`,
    );

  // rebuild
  program
    .command('rebuild')
    .description('Snapshot per-widget rebuild counters (requires enableGlobalRebuildHook).')
    .option('--top <n>', 'Top N rebuild counts.', '20')
    .action(async (opts: { top: string }) => {
      await withConnector(program, registry, async (c) => {
        const r = await c.getRebuildSnapshot(Number(opts.top));
        log.data(r);
      });
    })
    .addHelpText(
      'after',
      `
Enable in the app via
  FlutterCopilotConfiguration(enableGlobalRebuildHook: true)
Note: unsupported on Flutter Web (the custom BuildOwner hook is not installed).
`,
    );

  // screenshot
  program
    .command('screenshot')
    .description('Take a PNG screenshot of all views (one file per view).')
    .requiredOption(
      '-o, --output <path>',
      'Output PNG path. Single view → exact path. Multiple views → `_N` suffix for extra files (see --numbered).',
    )
    .option(
      '--numbered',
      'Always append _0/_1/... — every file is numbered, including when there is only one view. Prevents overwriting on reruns.',
    )
    .action(async (opts: { output: string; numbered?: boolean }) => {
      await withConnector(program, registry, async (c) => {
        const r = await c.takeScreenshots();
        const shots = r.screenshots ?? [];
        if (shots.length === 0) {
          log.err('No screenshots captured.');
          process.exitCode = 1;
          return;
        }
        const forceNumbered = opts.numbered === true;
        const saved: string[] = [];
        for (let i = 0; i < shots.length; i++) {
          const p = resolveShotPath(opts.output, i, shots.length, forceNumbered);
          await fs.mkdir(path.dirname(p), { recursive: true });
          const base64 = shots[i] ?? '';
          await fs.writeFile(p, Buffer.from(base64, 'base64'));
          saved.push(p);
        }
        log.ok(`saved ${saved.length} screenshot(s)`, { paths: saved });
      });
    })
    .addHelpText(
      'after',
      `
Examples:
  fcc screenshot -o /tmp/shot.png
  # Single view → /tmp/shot.png
  # Multiple views → /tmp/shot.png, /tmp/shot_1.png, /tmp/shot_2.png, ...
  # (Note: with only one view today and multiple tomorrow, /tmp/shot.png gets
  #  overwritten on rerun — use --numbered to always suffix.)

  fcc screenshot -o /tmp/shot.png --numbered
  # Always numbered → /tmp/shot_0.png, /tmp/shot_1.png, ...
`,
    );
}
