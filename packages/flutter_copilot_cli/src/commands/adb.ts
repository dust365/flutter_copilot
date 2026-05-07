import { Command } from 'commander';
import { AdbHelper } from '../adb.js';
import * as log from '../logging.js';

/**
 * Thin wrapper around `adb reverse` for Android devices that need to reach a
 * VM Service running on the host. Parallels the per-device setup that
 * `flutter_copilot_mcp` users otherwise have to run by hand.
 */
export function adbCommands(program: Command): void {
  program
    .command('adb-reverse')
    .description('Manage `adb reverse tcp:<port> tcp:<port>` for Android VM Service access.')
    .argument('<port>', 'TCP port to forward (e.g. the VM Service port).')
    .option('--remove', 'Remove the reverse mapping instead of creating it.')
    .action(async (portArg: string, opts: { remove?: boolean }) => {
      const port = Number(portArg);
      if (!Number.isInteger(port) || port <= 0 || port > 65535) {
        throw new Error(`Invalid port: ${portArg}`);
      }
      const adb = new AdbHelper();
      if (!(await adb.isAvailable())) {
        throw new Error('adb not found on PATH. Install Android platform-tools.');
      }
      const r = opts.remove
        ? await adb.removeReverse(port)
        : await adb.setupReverse(port);
      if (!r.success) {
        throw new Error(r.stderr || 'adb reverse failed');
      }
      log.ok(
        opts.remove
          ? `removed adb reverse tcp:${port}`
          : `adb reverse tcp:${port} tcp:${port} installed`,
        { port, removed: opts.remove === true },
      );
    })
    .addHelpText(
      'after',
      `
Useful when the app runs on an Android device/emulator but the VM Service is
bound to the host's loopback: the device can then reach \`localhost:<port>\`.

Examples:
  fcc adb-reverse 8181
  fcc adb-reverse 8181 --remove

Requires \`adb\` on PATH (Android platform-tools).
`,
    );
}
