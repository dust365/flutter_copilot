import { Command } from 'commander';
import { SessionClient } from '../session/client.js';
import * as log from '../logging.js';
import type { GlobalOpts } from './base.js';

export function connectCommands(program: Command): void {
  program.command('connect').description('Attach an explicit VM Service URI to the project session backend; writes no URI file.')
    .option('--name <alias>', 'Optional session alias.')
    .action(async (opts: { name?: string }) => {
      const global = program.opts<GlobalOpts>();
      if (!global.uri) throw new Error('Missing --uri. Example: fcc connect --uri ws://127.0.0.1:8181/abc/ws');
      log.data(await new SessionClient(global.project).call('connect', { uri: global.uri, name: opts.name }));
    });
  program.command('disconnect').description('Disconnect the selected App without stopping its Flutter run or device process.')
    .action(async () => {
      const opts = program.opts<GlobalOpts>();
      log.data(await new SessionClient(opts.project).call('disconnect', { app: opts.app }));
    });
}
