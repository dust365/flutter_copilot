import { Command } from 'commander';
import { VmServiceClient } from '../vm/client.js';
import { FlutterCopilotConnector } from '../vm/connector.js';
import { InstanceRegistry } from '../registry/instance_registry.js';
import { autoDetectVmServiceUri } from '../registry/auto_uri.js';
import * as log from '../logging.js';

interface DoctorTarget {
  name: string;
  uri: string;
}

export function doctorCommand(program: Command, registry: InstanceRegistry): void {
  program
    .command('doctor')
    .description(
      'Check connectivity of registered instances, or fall back to the ' +
        'auto-detected URI (FLUTTER_COPILOT_URI / .vm_service_uri) when none ' +
        'are registered.',
    )
    .action(async () => {
      const all = await registry.listAll();
      const timeoutSec = Number(program.opts().timeout ?? '5');
      const timeoutMs = timeoutSec * 1000;

      const targets: DoctorTarget[] = all.map((i) => ({ name: i.name, uri: i.uri }));
      let usedAutoUri = false;
      if (targets.length === 0) {
        const auto = await autoDetectVmServiceUri();
        if (auto) {
          const label =
            auto.source === 'env' ? '$FLUTTER_COPILOT_URI' : `auto:${auto.path ?? '.vm_service_uri'}`;
          targets.push({ name: label, uri: auto.uri });
          usedAutoUri = true;
        }
      }

      if (targets.length === 0) {
        log.info(
          'No instances registered and no auto URI found.\n' +
          'Register one with `fcc register <name> <uri>`, or start the app ' +
            'with scripts/flutter_run.sh to create .vm_service_uri.',
        );
        return;
      }

      log.info(
        usedAutoUri
          ? 'No instances registered; probing auto-detected URI...'
          : `Checking ${targets.length} instance(s)...`,
      );
      const results: Array<{ name: string; uri: string; ok: boolean; error?: string }> = [];
      let allOk = true;
      for (const t of targets) {
        const client = new VmServiceClient();
        const connector = new FlutterCopilotConnector(client);
        try {
          await connector.connect(t.uri, timeoutMs);
          results.push({ name: t.name, uri: t.uri, ok: true });
          log.ok(`${t.name} (${t.uri}) — OK`);
        } catch (e) {
          allOk = false;
          const msg = (e as Error).message;
          results.push({ name: t.name, uri: t.uri, ok: false, error: msg });
          log.err(`${t.name} (${t.uri}) — ${msg}`);
        } finally {
          await connector.disconnect().catch(() => {});
        }
      }
      log.data({ healthy: allOk, autoUri: usedAutoUri, results });
      if (!allOk) process.exitCode = 1;
    })
    .addHelpText(
      'after',
      `
Exits 1 if any target fails to connect. Use this as a CI/sanity probe after
starting the app but before running tap/scroll commands.

Example:
  ./scripts/flutter_run.sh -d macos   # writes .vm_service_uri
  fcc doctor              # auto-detects the URI and probes it
`,
    );
}
