import { Command } from 'commander';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { VmServiceClient } from '../vm/client.js';
import { FlutterCopilotConnector } from '../vm/connector.js';
import {
  findAncestorFile,
  VM_SERVICE_URI_FILENAME,
} from '../registry/auto_uri.js';
import * as log from '../logging.js';
import type { GlobalOpts } from './base.js';

export function connectCommands(program: Command): void {
  program
    .command('connect')
    .description('Validate a VM Service URI and save it as the current project connection.')
    .action(async () => {
      const uri = program.opts<GlobalOpts>().uri;
      if (!uri) {
        throw new Error('Missing required --uri. Example: fcc connect --uri ws://127.0.0.1:8181/abc/ws');
      }
      const timeoutSec = Number(program.opts<{ timeout?: string }>().timeout ?? '5');
      if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) {
        throw new Error(`Invalid --timeout: ${program.opts<{ timeout?: string }>().timeout}`);
      }
      const timeoutMs = timeoutSec * 1000;
      const client = new VmServiceClient();
      const connector = new FlutterCopilotConnector(client);
      try {
        await connector.connect(uri, timeoutMs);
      } finally {
        await connector.disconnect().catch(() => {});
      }

      const filePath = path.join(process.cwd(), VM_SERVICE_URI_FILENAME);
      await fs.writeFile(filePath, `${uri.trim()}\n`);
      log.ok(`connected and saved ${VM_SERVICE_URI_FILENAME}`, {
        uri,
        path: filePath,
      });
    })
    .addHelpText(
      'after',
      `
Example:
  fcc connect --uri ws://127.0.0.1:8181/abc/ws
  fcc --uri ws://127.0.0.1:8181/abc/ws connect

The URI is written to .vm_service_uri in the current working directory. Later
commands automatically use that file.
`,
    );

  program
    .command('disconnect')
    .description('Remove the current project .vm_service_uri file.')
    .action(async () => {
      const filePath = await findAncestorFile(process.cwd(), VM_SERVICE_URI_FILENAME);
      if (!filePath) {
        log.info(`No ${VM_SERVICE_URI_FILENAME} found.`);
        log.data({ disconnected: false });
        return;
      }
      await fs.unlink(filePath);
      log.ok(`removed ${filePath}`, { disconnected: true, path: filePath });
    });
}
