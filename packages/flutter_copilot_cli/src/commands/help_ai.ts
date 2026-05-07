import { Command } from 'commander';

/**
 * Prints machine-readable command surface for LLM agents.
 * The intent is that an agent can `fcc help-ai` once and learn
 * the whole CLI without the README.
 */
export function helpAiCommand(program: Command): void {
  program
    .command('help-ai')
    .description('Dump machine-readable command surface (JSON) for AI agents.')
    .action(() => {
      const surface = {
        tool: 'flutter_copilot_cli',
        bin: ['flutter_copilot_cli', 'fcc'],
        description:
          'Drive a running debug-mode Flutter app via flutter_copilot_claw VM service extensions.',
        globalOptions: {
          '--instance,-i': 'Registered instance name (see `list`, `register`).',
          '--uri': 'Direct VM Service WebSocket URI. Mutually exclusive with --instance.',
          '--timeout': 'Connection timeout in seconds (default 5).',
          '--json': 'Output machine-readable JSON instead of TTY formatting.',
        },
        matcher: {
          description: 'Widget matcher used by tap/scroll-to/etc.',
          fields: { key: 'ValueKey<String>', text: 'Visible text', type: 'Widget type name', x: 'Number (coord)', y: 'Number (coord)', focused: 'Boolean' },
        },
        commands: [
          { name: 'register <name> <uri>', args: {} },
          { name: 'unregister <name>', args: {} },
          { name: 'list', args: {} },
          { name: 'doctor', args: {} },
          { name: 'elements', args: {} },
          { name: 'tap', args: '<matcher>' },
          { name: 'double-tap', args: '<matcher>' },
          { name: 'long-press', args: { matcher: true, '--duration <ms>': 'default 500' } },
          { name: 'enter-text', args: { matcher: true, '--input <text>': 'required' } },
          { name: 'scroll-to', args: '<matcher>' },
          {
            name: 'drag',
            args: { matcher: true, '--dx': 'delta', '--dy': 'delta', '--from-x/--from-y/--to-x/--to-y': 'absolute coords' },
          },
          {
            name: 'swipe',
            args: { matcher: true, '--direction up|down|left|right': 'required', '--distance <px>': 'default 200' },
          },
          {
            name: 'navigate',
            args: {
              '--op push|pop|replace|pushReplacement|popUntil': 'required (matches YAML step `op`)',
              '--route <name>': 'required for push/replace/pushReplacement/popUntil',
              '--args <json>': 'optional JSON object for route arguments',
            },
          },
          { name: 'hot-reload', args: {} },
          { name: 'logs', args: { '--limit <n>': 'optional' } },
          { name: 'rebuild', args: { '--top <n>': 'default 20' } },
          { name: 'screenshot', args: { '-o, --output <path>': 'required', '--numbered': 'force _N suffix on every file (prevents rerun overwrite)' } },
          {
            name: 'adb-reverse <port>',
            args: { '--remove': 'remove the mapping instead of creating it' },
          },
          { name: 'watch', args: { '--logs': 'stream log events', '--rebuilds': 'poll rebuild snapshots', '--interval <ms>': 'default 1000' } },
          { name: 'repl', args: {} },
          { name: 'run <script.yaml>', args: {} },
        ],
        scriptSchema: {
          example: {
            name: 'smoke-login',
            stopOnFailure: true,
            steps: [
              { action: 'tap', key: 'LoginBtn' },
              { action: 'enter-text', key: 'UsernameField', input: 'demo' },
              { action: 'wait', ms: 300 },
              { action: 'screenshot', output: '/tmp/after-login.png' },
              { action: 'assert-element', text: 'Welcome', exists: true },
            ],
          },
          allowedActions: [
            'tap', 'double-tap', 'long-press', 'enter-text', 'scroll-to', 'swipe',
            'drag', 'navigate', 'hot-reload', 'screenshot', 'wait', 'assert-element',
          ],
        },
      };
      process.stdout.write(JSON.stringify(surface, null, 2) + '\n');
    });
}
