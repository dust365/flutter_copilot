import { Command } from 'commander';

/**
 * Prints the machine-readable command surface for shell-capable AI agents.
 * Keep this aligned with README command tables, Commander options, and the
 * YAML playbook schema.
 */
export function helpAiCommand(program: Command): void {
  program
    .command('help-ai')
    .description('Dump machine-readable command surface (JSON) for AI agents.')
    .action(() => {
      const surface = {
        schemaVersion: 2,
        tool: 'flutter_copilot_cli',
        bin: ['fcc', 'flutter_copilot_cli'],
        purpose:
          'Drive one currently running Flutter app through flutter_copilot_claw VM Service extensions.',
        targetResolution: [
          {
            source: '--uri <ws://...>',
            precedence: 1,
            note: 'Explicit URI for this invocation.',
          },
          {
            source: 'FLUTTER_COPILOT_URI',
            precedence: 2,
            note: 'Environment variable.',
          },
          {
            source: '.vm_service_uri',
            precedence: 3,
            note: 'Nearest file in cwd or an ancestor. Written by scripts/flutter_run.sh or fcc connect.',
          },
        ],
        globalOptions: {
          '--uri <uri>': 'VM Service WebSocket URI.',
          '--timeout <sec>': 'Connection timeout in seconds. Default: 5.',
          '--watch-uri': 'For watch/repl only: reconnect when the auto-detected .vm_service_uri changes.',
          '--json': 'Machine-readable output. Long-running watch emits NDJSON.',
        },
        matcher: {
          description: 'Widget matcher shared by gesture/input commands.',
          fields: {
            key: 'ValueKey<String>; most stable.',
            text: 'Visible text.',
            type: 'Widget type name, e.g. ElevatedButton.',
            x: 'Logical x coordinate; use with y.',
            y: 'Logical y coordinate; use with x.',
            focused: 'Currently focused element.',
          },
          rule: 'Provide at least one matcher for tap/double-tap/long-press/enter-text/scroll-to/swipe. Drag may instead use absolute from/to coordinates.',
        },
        commands: [
          {
            name: 'connect',
            category: 'target',
            mcpTool: 'connect',
            description: 'Validate a VM Service URI and save it to .vm_service_uri in cwd.',
            options: { '--uri <uri>': 'required' },
            example: 'fcc connect --uri ws://127.0.0.1:8181/abc/ws',
          },
          {
            name: 'disconnect',
            category: 'target',
            description: 'Remove the nearest .vm_service_uri file. This CLI has no persistent socket to close.',
            options: {},
            example: 'fcc disconnect',
          },
          {
            name: 'doctor',
            category: 'target',
            description: 'Check that the resolved target connects and exposes flutter_copilot extensions.',
            options: {},
            example: 'fcc doctor',
          },
          {
            name: 'get-interactive-elements',
            category: 'inspect',
            mcpTool: 'get_interactive_elements',
            description: 'Print the current interactive element tree.',
            options: {},
            example: 'fcc --json get-interactive-elements',
          },
          {
            name: 'get-logs',
            category: 'inspect',
            mcpTool: 'get_logs',
            description: 'Fetch the in-app log buffer captured by flutter_copilot_claw.',
            options: { '--limit <n>': 'Only print the last N entries.' },
            example: 'fcc get-logs --limit 50',
          },
          {
            name: 'get-rebuild-snapshot',
            category: 'inspect',
            mcpTool: 'get_rebuild_snapshot',
            description: 'Fetch rebuild hot-spot counters.',
            options: { '--top-limit <n>': 'Default: 20.' },
            example: 'fcc get-rebuild-snapshot --top-limit 10',
          },
          {
            name: 'take-screenshots',
            category: 'capture',
            mcpTool: 'take_screenshots',
            description: 'Capture all views and write PNG files.',
            options: {
              '-o, --output <path>': 'required output PNG path',
              '--numbered': 'Always suffix _0/_1/... to avoid overwrite shape changes.',
            },
            example: 'fcc take-screenshots -o /tmp/shot.png --numbered',
          },
          {
            name: 'tap',
            category: 'gesture',
            mcpTool: 'tap',
            description: 'Tap a matched element or coordinate.',
            options: '<matcher>',
            example: 'fcc tap --text "Increment"',
          },
          {
            name: 'double-tap',
            category: 'gesture',
            mcpTool: 'double_tap',
            description: 'Double tap a matched element or coordinate.',
            options: '<matcher>',
            example: 'fcc double-tap --key LikeButton',
          },
          {
            name: 'long-press',
            category: 'gesture',
            mcpTool: 'long_press',
            description: 'Long press a matched element or coordinate.',
            options: { matcher: true, '--duration <ms>': 'Default: 500.' },
            example: 'fcc long-press --key ItemCard --duration 800',
          },
          {
            name: 'enter-text',
            category: 'input',
            mcpTool: 'enter_text',
            description: 'Focus a matched text field and enter text.',
            options: { matcher: true, '--input <text>': 'required' },
            example: 'fcc enter-text --key UsernameField --input demo',
          },
          {
            name: 'scroll-to',
            category: 'gesture',
            mcpTool: 'scroll_to',
            description: 'Scroll until a matched element is visible.',
            options: '<matcher>',
            example: 'fcc scroll-to --text "Submit"',
          },
          {
            name: 'drag',
            category: 'gesture',
            mcpTool: 'flutter_copilot_drag',
            description: 'Drag by matcher plus delta, or by absolute from/to coordinates.',
            options: {
              matcher: 'optional when using absolute from/to',
              '--delta-x <n>': 'Default: 0.',
              '--delta-y <n>': 'Default: 0.',
              '--from-x/--from-y/--to-x/--to-y': 'Absolute coordinates; provide all four.',
            },
            example: 'fcc drag --key Slider --delta-x 120',
          },
          {
            name: 'swipe',
            category: 'gesture',
            mcpTool: 'swipe',
            description: 'Swipe from a matched element.',
            options: {
              matcher: true,
              '--direction <up|down|left|right>': 'required',
              '--distance <px>': 'Default: 200.',
            },
            example: 'fcc swipe --key Feed --direction up --distance 500',
          },
          {
            name: 'navigate',
            category: 'navigation',
            mcpTool: 'navigate',
            description: 'Drive Navigator push/pop/replace/pushReplacement/popUntil.',
            options: {
              '--action <push|pop|replace|pushReplacement|popUntil>': 'required',
              '--route <name>': 'required for push/replace/pushReplacement/popUntil',
              '--arguments <json>': 'Optional JSON object.',
            },
            example: 'fcc navigate --action push --route /detail --arguments \'{"id":42}\'',
          },
          {
            name: 'hot-reload',
            category: 'lifecycle',
            mcpTool: 'hot_reload',
            description: 'Trigger Flutter hot reload.',
            options: {},
            example: 'fcc hot-reload',
          },
          {
            name: 'watch',
            category: 'automation',
            description: 'Stream logs and/or rebuild snapshots until Ctrl-C.',
            options: {
              '--logs': 'Stream Stdout/Stderr/Extension events.',
              '--rebuilds': 'Poll rebuild snapshots.',
              '--interval <ms>': 'Default: 1000. Minimum: 100.',
            },
            output: '--json emits NDJSON, one event per line.',
            example: 'fcc --json watch --logs --rebuilds --interval 500',
          },
          {
            name: 'repl',
            category: 'automation',
            description: 'Open an interactive shell using the same current target.',
            options: {},
            example: 'fcc --watch-uri repl',
          },
          {
            name: 'run <script.yaml>',
            category: 'automation',
            description: 'Run a YAML playbook. In --json mode, progress goes to stderr and summary JSON goes to stdout.',
            options: {},
            example: 'fcc --json run smoke.yaml',
          },
          {
            name: 'help-ai',
            category: 'metadata',
            description: 'Print this JSON surface.',
            options: {},
            example: 'fcc help-ai',
          },
        ],
        scriptSchema: {
          format: 'YAML',
          topLevel: {
            name: 'optional string',
            stopOnFailure: 'optional boolean, default true',
            steps: 'required non-empty array',
          },
          matcherFields: ['key', 'text', 'type', 'x', 'y', 'focused'],
          retry: {
            attempts: 'positive integer, default 3 when retry is present',
            delay: 'milliseconds, non-negative integer, default 500 when retry is present',
          },
          actions: {
            tap: { fields: ['matcher', 'retry?', 'name?'] },
            'double-tap': { fields: ['matcher', 'retry?', 'name?'] },
            'long-press': { fields: ['matcher', 'duration?', 'retry?', 'name?'] },
            'enter-text': { fields: ['matcher', 'input', 'retry?', 'name?'] },
            'scroll-to': { fields: ['matcher', 'retry?', 'name?'] },
            swipe: { fields: ['matcher', 'direction', 'distance?', 'retry?', 'name?'] },
            drag: {
              fields: [
                'matcher?',
                'deltaX?',
                'deltaY?',
                'fromX?',
                'fromY?',
                'toX?',
                'toY?',
                'retry?',
                'name?',
              ],
            },
            navigate: {
              note: 'YAML uses op for the navigation operation because action is the step discriminator.',
              fields: ['op', 'route?', 'arguments?', 'retry?', 'name?'],
            },
            'hot-reload': { fields: ['retry?', 'name?'] },
            'take-screenshots': { fields: ['output', 'numbered?', 'retry?', 'name?'] },
            wait: { fields: ['ms', 'name?'] },
            'assert-element': { fields: ['matcher', 'exists?', 'retry?', 'name?'] },
          },
          example: {
            name: 'smoke-login',
            stopOnFailure: true,
            steps: [
              { action: 'tap', key: 'LoginBtn' },
              { action: 'enter-text', key: 'UsernameField', input: 'demo' },
              { action: 'wait', ms: 300 },
              { action: 'take-screenshots', output: '/tmp/after-login.png' },
              { action: 'assert-element', text: 'Welcome', exists: true },
            ],
          },
        },
      };
      process.stdout.write(JSON.stringify(surface, null, 2) + '\n');
    });
}
