import { Command } from 'commander';
import { createInterface } from 'node:readline/promises';
import { SessionClient, SessionError, type LaunchOperation } from '../session/client.js';
import type { GlobalOpts } from './base.js';
import * as log from '../logging.js';

export function parseSelection(input: string, candidates: Array<Record<string, unknown>>): string[] {
  const tokens = input.trim().split(/[\s,]+/).filter(Boolean);
  const values = tokens.map((value) => {
    const index = Number(value) - 1;
    if (!Number.isInteger(index) || index < 0 || index >= candidates.length) {
      throw new Error('Enter one or more listed numbers, separated by commas.');
    }
    return String(candidates[index]!['id']);
  });
  if (!values.length) throw new Error('No devices or Apps selected.');
  return [...new Set(values)];
}

export async function chooseCandidates(error: SessionError): Promise<{ ids: string[]; apps: boolean }> {
  if (log.getOutputMode() === 'json' || !process.stdin.isTTY || !process.stderr.isTTY || error.code !== 'selection_required' || !error.candidates.length) throw error;
  const apps = error.candidates.every((item) => typeof item['uri'] === 'string');
  process.stderr.write(`${error.message}\n`);
  error.candidates.forEach((candidate, index) => {
    process.stderr.write(`  ${index + 1}. ${candidate['name'] ?? candidate['id']}  ${candidate['id']}` +
      `${candidate['deviceId'] ? `  device=${candidate['deviceId']}` : ''}\n`);
  });
  const rl = createInterface({ input: process.stdin, output: process.stderr });
  try {
    const answer = await rl.question(`Select ${apps ? 'Apps' : 'devices'} (e.g. 1 or 1,2; Ctrl-C to cancel): `);
    return { ids: parseSelection(answer, error.candidates), apps };
  } finally { rl.close(); }
}

export function sessionCommands(program: Command): void {
  const client = () => new SessionClient(program.opts<GlobalOpts>().project);
  program.command('apps').description('Discover running Apps in this project through DTD.')
    .action(async () => log.data(await client().call('list_apps')));
  program.command('devices').description('List connected devices supported by this project.')
    .action(async () => log.data(await client().call('list_devices')));
  program.command('up')
    .description('Reuse running Apps or start this project on one or more selected devices.')
    .option('-d, --device <id>', 'Device id; repeat to select several.', (value: string, all: string[]) => [...all, value], [])
    .option('-t, --target <path>', 'Project-relative entrypoint, default lib/main.dart.')
    .option('--flavor <name>', 'Flutter build flavor.')
    .option('--dart-define <key=value>', 'Dart define; repeat as needed.', (value: string, all: string[]) => [...all, value], [])
    .option('--profile', 'Run in profile mode (hot reload/restart unavailable).')
    .option('--name <alias>', 'Alias for a single-device launch.')
    .option('--new-session', 'Explicitly launch instead of reusing an existing App.')
    .option('--startup-timeout <seconds>', 'Per-device launch timeout.', '180')
    .option('--no-wait', 'Return the launch operation immediately.')
    .action(async (opts: { device: string[]; target?: string; flavor?: string; dartDefine: string[]; profile?: boolean; name?: string; newSession?: boolean; startupTimeout: string; wait: boolean }) => {
      const session = client();
      const timeout = Number(opts.startupTimeout);
      if (!Number.isInteger(timeout) || timeout <= 0) throw new Error('--startup-timeout must be a positive integer');
      const args: Record<string, unknown> = {
        app: program.opts<GlobalOpts>().app, deviceIds: opts.device, target: opts.target,
        name: opts.name, timeout, newSession: opts.newSession ?? false,
        args: [ ...(opts.profile ? ['--profile'] : []),
          ...(opts.flavor ? ['--flavor', opts.flavor] : []),
          ...opts.dartDefine.map((define) => `--dart-define=${define}`)],
      };
      let operation: LaunchOperation;
      try { operation = await session.call('ensure_apps', args); } catch (e) {
        if (!(e instanceof SessionError)) throw e;
        const selection = await chooseCandidates(e);
        operation = await session.call('ensure_apps', {
          ...args, ...(selection.apps ? { appIds: selection.ids } : { deviceIds: selection.ids }),
        });
      }
      if (opts.wait) {
        let previous = '';
        while (operation.state === 'running') {
          const state = operation.results.map((r) => `${r.deviceId}: ${r.state}`).join(', ');
          if (state !== previous) { log.info(state); previous = state; }
          await new Promise((r) => setTimeout(r, 500));
          operation = await session.call('operation_status', { operationId: operation.operationId });
        }
      }
      log.data(operation);
      if (operation.results.some((result) => result.state === 'failed')) process.exitCode = 1;
    });
  program.command('status <operation-id>').description('Read a background launch operation.')
    .action(async (operationId: string) => log.data(await client().call('operation_status', { operationId })));
  program.command('logs').description('Read Flutter tool output, including during startup.')
    .option('--lines <n>', 'Number of trailing lines.', '100')
    .action(async (opts: { lines: string }) => {
      const lines = Number(opts.lines);
      if (!Number.isInteger(lines) || lines <= 0) throw new Error('--lines must be positive');
      log.data(await client().call('get_app_logs', { app: program.opts<GlobalOpts>().app, lines }));
    });
  for (const method of ['stop', 'detach'] as const) {
    program.command(method).description(method === 'stop'
      ? 'Stop an App started by Copilot. External IDE sessions are protected.'
      : 'Detach an owned Flutter run and leave the device App running.')
      .action(async () => log.data(await client().call(`${method}_app`, { app: program.opts<GlobalOpts>().app })));
  }
  program.command('session-shutdown').description('Shut down an idle session backend; refuses while owned runs are active.')
    .action(async () => log.data(await client().call('shutdown')));
}
