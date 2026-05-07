#!/usr/bin/env node
import { Command } from 'commander';
import { InstanceRegistry } from './registry/instance_registry.js';
import { setOutputMode } from './logging.js';
import * as log from './logging.js';

import { registerCommand } from './commands/registry.js';
import { doctorCommand } from './commands/doctor.js';
import { gestureCommands } from './commands/gestures.js';
import { miscCommands } from './commands/misc.js';
import { watchCommand } from './commands/watch.js';
import { replCommand } from './commands/repl.js';
import { runCommand } from './commands/run.js';
import { helpAiCommand } from './commands/help_ai.js';
import { adbCommands } from './commands/adb.js';
import { VERSION } from './version.generated.js';

async function main(): Promise<void> {
  const program = new Command();
  // Honor whichever bin name the user invoked us with so help text matches.
  // Both `flutter_copilot_cli` (full) and `fcc` (short) are valid entry points.
  const invokedAs = (() => {
    const argv1 = process.argv[1];
    if (!argv1) return 'flutter_copilot_cli';
    const base = argv1.split('/').pop() ?? '';
    return base === 'fcc' ? 'fcc' : 'flutter_copilot_cli';
  })();
  program
    .name(invokedAs)
    .description(
      'Drive a running debug-mode Flutter app via the `ext.flutter.flutter_copilot.*`\n' +
        'VM service extensions registered by `flutter_copilot_claw`.\n' +
        '\n' +
        'What it does:\n' +
        '  - Dispatch gestures (tap, drag, swipe, long-press, scroll-to) and text input\n' +
        '  - Navigate routes, trigger hot reload, grab screenshots and logs\n' +
        '  - Stream live logs / rebuild snapshots with transparent reconnect\n' +
        '  - Run YAML playbooks for smoke tests, or drive the app from a REPL\n' +
        '  - Manage a multi-app registry (useful when juggling devices)\n' +
        '\n' +
        'If neither --uri nor -i is given, the URI is auto-detected from\n' +
        '$FLUTTER_COPILOT_URI or the nearest .vm_service_uri file.',
    )
    .version(VERSION)
    .option('-i, --instance <name>', 'Registered instance name (see `list` / `register`).')
    .option('--uri <uri>', 'VM Service WebSocket URI. Mutually exclusive with -i.')
    .option('--no-auto-uri', 'Disable auto-detection from FLUTTER_COPILOT_URI / .vm_service_uri.')
    .option('--watch-uri', 'Auto-reconnect when .vm_service_uri changes (repl/watch only).')
    .option('--timeout <sec>', 'Connection timeout in seconds.', '5')
    .option('--json', 'Output JSON instead of TTY formatting (pipe to jq).')
    .hook('preAction', (thisCmd) => {
      if (thisCmd.optsWithGlobals().json) setOutputMode('json');
    });

  program.addHelpText(
    'after',
    `
Target resolution (first match wins):
  --uri ws://...                    explicit URI
  -i <name>                         registered instance (see \`list\`)
  $FLUTTER_COPILOT_URI              env var
  .vm_service_uri                   file in cwd or any ancestor directory

Widget matcher (shared by tap / enter-text / scroll-to / swipe / ...):
  --key <k>                         ValueKey<String> — most reliable
  --text <t>                        visible text
  --type <n>                        widget type name (e.g. ElevatedButton)
  --x <n> --y <n>                   coordinates in logical pixels
  --focused                         the currently focused element

Examples (\`fcc\` is the short alias for \`flutter_copilot_cli\`):
  # Start the app, then drive it from the CLI (URI auto-detected)
  ./scripts/flutter_run.sh -d macos
  fcc doctor
  fcc elements
  fcc tap --text "Increment"
  fcc enter-text --key UsernameField --input demo
  fcc screenshot -o /tmp/shot.png
  fcc hot-reload

  # Real-time telemetry that survives \`flutter\` restarts
  fcc --watch-uri watch --logs --rebuilds

  # Scripted smoke test
  fcc run smoke.yaml

  # Multi-app registry (when you have several devices / apps)
  fcc register demo ws://127.0.0.1:8181/abc/ws
  fcc -i demo repl

  # Android: expose host VM Service to a device
  fcc adb-reverse 8181

JSON output for scripting:
  fcc --json -i demo elements | jq '.elements'

Machine-readable surface (for AI agents):
  fcc help-ai

Run \`${invokedAs} <command> --help\` for per-command details.
`,
  );

  const registry = new InstanceRegistry();

  // Registry & health
  registerCommand(program, registry);
  doctorCommand(program, registry);

  // Actions
  gestureCommands(program, registry);
  miscCommands(program, registry);
  adbCommands(program);

  // Power features
  watchCommand(program, registry);
  replCommand(program, registry);
  runCommand(program, registry);
  helpAiCommand(program);

  try {
    await program.parseAsync(process.argv);
  } catch (e) {
    log.err((e as Error).message);
    process.exit(1);
  }
}

main().catch((e: unknown) => {
  log.err((e as Error).message);
  process.exit(1);
});
