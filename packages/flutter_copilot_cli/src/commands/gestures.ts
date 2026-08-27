import { Command, Option } from 'commander';
import { withConnector } from './base.js';
import { buildMatcher, isMatcherEmpty, type MatcherArgs } from '../matcher.js';
import * as log from '../logging.js';

function attachMatcherOptions(cmd: Command): Command {
  return cmd
    .option('--key <key>', 'Match by ValueKey<String>.')
    .option('--text <text>', 'Match by visible text.')
    .option('--type <type>', 'Match by widget type name (e.g. ElevatedButton).')
    .option('--x <x>', 'X coordinate (positional).')
    .option('--y <y>', 'Y coordinate (positional).')
    .option('--focused', 'Match the focused element.');
}

function requireMatcher(opts: MatcherArgs): ReturnType<typeof buildMatcher> {
  const m = buildMatcher(opts);
  if (isMatcherEmpty(m)) {
    throw new Error('At least one matcher required: --key, --text, --type, --x/--y or --focused.');
  }
  return m;
}

export function gestureCommands(program: Command): void {
  // tap
  const tap = attachMatcherOptions(
    program
      .command('tap')
      .description('Tap an element by key, text, type, or coordinates.'),
  ).action(async (opts: MatcherArgs) => {
    const m = requireMatcher(opts);
    await withConnector(program, async (c) => {
      const r = await c.tap(m);
      log.ok(String(r['message'] ?? 'tapped'), { result: r });
    });
  });
  tap.addHelpText(
    'after',
    `
Examples:
  fcc tap --text "点击"
  fcc tap --key <ValueKey>
  fcc tap --type ElevatedButton
  fcc tap --x 120 --y 340
`,
  );

  // double-tap
  attachMatcherOptions(
    program
      .command('double-tap')
      .description('Double-tap an element.'),
  ).action(async (opts: MatcherArgs) => {
    const m = requireMatcher(opts);
    await withConnector(program, async (c) => {
      const r = await c.doubleTap(m);
      log.ok(String(r['message'] ?? 'double tapped'), { result: r });
    });
  });

  // long-press
  attachMatcherOptions(
    program
      .command('long-press')
      .description('Long-press an element.')
      .option('--duration <ms>', 'Press duration in ms.', '500'),
  ).action(async (opts: MatcherArgs & { duration: string }) => {
    const m = requireMatcher(opts);
    const dur = Number(opts.duration);
    await withConnector(program, async (c) => {
      const r = await c.longPress(m, dur);
      log.ok(String(r['message'] ?? 'long pressed'), { result: r });
    });
  });

  // enter-text
  const enterText = attachMatcherOptions(
    program
      .command('enter-text')
      .description('Type text into a TextField.')
      .requiredOption('--input <text>', 'Text to enter.'),
  ).action(async (opts: MatcherArgs & { input: string }) => {
    const m = requireMatcher(opts);
    await withConnector(program, async (c) => {
      const r = await c.enterText(m, opts.input);
      log.ok(String(r['message'] ?? 'entered text'), { result: r });
    });
  });
  enterText.addHelpText(
    'after',
    `
Examples:
  fcc enter-text --key <TextFieldKey> --input demo
  fcc enter-text --focused --input "hello world"

The target TextField gains focus, then receives the characters one by one.
`,
  );

  // scroll-to
  attachMatcherOptions(
    program
      .command('scroll-to')
      .description('Scroll until an element is visible.'),
  ).action(async (opts: MatcherArgs) => {
    const m = requireMatcher(opts);
    await withConnector(program, async (c) => {
      const r = await c.scrollTo(m);
      log.ok(String(r['message'] ?? 'scrolled'), { result: r });
    });
  });

  // drag (by matcher delta, or absolute from/to)
  const drag = attachMatcherOptions(
    program
      .command('drag')
      .description('Drag an element by delta, or from/to absolute coordinates.')
      .option('--delta-x <n>', 'Delta X', '0')
      .option('--delta-y <n>', 'Delta Y', '0')
      .option('--from-x <n>', 'From X (absolute)')
      .option('--from-y <n>', 'From Y (absolute)')
      .option('--to-x <n>', 'To X (absolute)')
      .option('--to-y <n>', 'To Y (absolute)'),
  ).action(
    async (
      opts: MatcherArgs & {
        deltaX: string;
        deltaY: string;
        fromX?: string;
        fromY?: string;
        toX?: string;
        toY?: string;
      },
    ) => {
      const m = buildMatcher(opts);
      const hasAbsolute =
        opts.fromX !== undefined &&
        opts.fromY !== undefined &&
        opts.toX !== undefined &&
        opts.toY !== undefined;
      if (!hasAbsolute && isMatcherEmpty(m)) {
        throw new Error(
          'Provide a matcher (--key/--text/--type/--x/--y) or all four of --from-x/--from-y/--to-x/--to-y.',
        );
      }
      await withConnector(program, async (c) => {
        const r = await c.drag(m, {
          deltaX: Number(opts.deltaX),
          deltaY: Number(opts.deltaY),
          ...(opts.fromX !== undefined ? { fromX: Number(opts.fromX) } : {}),
          ...(opts.fromY !== undefined ? { fromY: Number(opts.fromY) } : {}),
          ...(opts.toX !== undefined ? { toX: Number(opts.toX) } : {}),
          ...(opts.toY !== undefined ? { toY: Number(opts.toY) } : {}),
        });
        log.ok(String(r['message'] ?? 'dragged'), { result: r });
      });
    },
  );
  drag.addHelpText(
    'after',
    `
Examples:
  # Drag an element by 100px left
  fcc drag --key Card1 --delta-x -100

  # Free drag between two absolute points (no matcher needed)
  fcc drag --from-x 50 --from-y 400 --to-x 300 --to-y 400
`,
  );

  // swipe
  const swipe = attachMatcherOptions(
    program
      .command('swipe')
      .description('Swipe from an element in a given direction.')
      .addOption(
        new Option('--direction <dir>', 'Swipe direction.')
          .choices(['up', 'down', 'left', 'right'])
          .makeOptionMandatory(),
      )
      .option('--distance <n>', 'Swipe distance in pixels.', '200'),
  ).action(async (opts: MatcherArgs & { direction: 'up' | 'down' | 'left' | 'right'; distance: string }) => {
    const m = requireMatcher(opts);
    await withConnector(program, async (c) => {
      const r = await c.swipe(m, opts.direction, Number(opts.distance));
      log.ok(String(r['message'] ?? 'swiped'), { result: r });
    });
  });
  swipe.addHelpText(
    'after',
    `
Examples:
  fcc swipe --key Feed --direction up --distance 500
`,
  );

  // navigate
  const navigate = program
    .command('navigate')
    .description('Drive the app Navigator (push / pop / replace / pushReplacement / popUntil).')
    .addOption(
      new Option('--action <action>', 'Navigator operation.')
        .choices(['push', 'pop', 'replace', 'pushReplacement', 'popUntil'])
        .makeOptionMandatory(),
    )
    .option('--route <name>', 'Route name (required for push/replace/pushReplacement/popUntil).')
    .option('--arguments <json>', 'Route arguments as JSON object.')
    .action(async (opts: { action: 'push' | 'pop' | 'replace' | 'pushReplacement' | 'popUntil'; route?: string; arguments?: string }) => {
      let args: Record<string, unknown> | undefined;
      if (opts.arguments) {
        try {
          args = JSON.parse(opts.arguments) as Record<string, unknown>;
        } catch (e) {
          throw new Error(`Invalid --arguments JSON: ${(e as Error).message}`);
        }
      }
      await withConnector(program, async (c) => {
        const r = await c.navigate(opts.action, opts.route, args);
        log.ok(String(r['message'] ?? 'navigated'), { result: r });
      });
    });
  navigate.addHelpText(
    'after',
    `
Examples:
  fcc navigate --action push --route /settings
  fcc navigate --action push --route /detail --arguments '{"id":42}'
  fcc navigate --action replace --route /home
  fcc navigate --action pushReplacement --route /onboarding
  fcc navigate --action pop
  fcc navigate --action popUntil --route /
`,
  );
}
