import { Command } from 'commander';
import { VmServiceClient } from '../vm/client.js';
import { FlutterCopilotConnector } from '../vm/connector.js';
import { resolveTarget } from './base.js';
import * as log from '../logging.js';

export function doctorCommand(program: Command): void {
  program
    .command('doctor')
    .description('Check connectivity of the current VM Service URI.')
    .action(async () => {
      const target = await resolveTarget(program);
      const client = new VmServiceClient();
      const connector = new FlutterCopilotConnector(client);
      try {
        log.info(`Checking ${target.displayName}...`);
        await connector.connect(target.uri, target.timeoutMs);
        log.ok(`${target.uri} — OK`, { uri: target.uri, source: target.displayName });
        log.data({ healthy: true, uri: target.uri, source: target.displayName });
      } catch (e) {
        log.err(`${target.uri} — ${(e as Error).message}`, {
          uri: target.uri,
          source: target.displayName,
        });
        log.data({
          healthy: false,
          uri: target.uri,
          source: target.displayName,
          error: (e as Error).message,
        });
        process.exitCode = 1;
      } finally {
        await connector.disconnect().catch(() => {});
      }
    })
    .addHelpText(
      'after',
      `
Exits 1 if the current target fails to connect.

Target resolution:
  --uri ws://...
  FLUTTER_COPILOT_URI (unless --app is set)
  DTD discovery for --project / cwd

Example:
  fcc up --device macos
  fcc doctor
  fcc --uri ws://127.0.0.1:8181/abc/ws doctor
`,
    );
}
