import { Command } from 'commander';
import readline from 'node:readline';
import chalk from 'chalk';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { withConnector, reconnectWithBackoff } from './base.js';
import { UriFileWatcher } from '../vm/uri_watcher.js';
import { buildMatcher, type MatcherArgs } from '../matcher.js';
import { resolveShotPath } from '../screenshot_path.js';
import type { FlutterCopilotConnector } from '../vm/connector.js';

/**
 * Interactive REPL.
 *
 * Syntax: `<action> [k=v ...]`
 * Example:
 *   > tap key=LoginBtn
 *   > enter-text key=UsernameField input="demo user"
 *   > take-screenshots output=/tmp/s.png
 *   > reload
 *   > get-interactive-elements
 *   > get-logs 20
 *   > help
 *   > exit
 */
export function replCommand(program: Command): void {
  program
    .command('repl')
    .description('Interactive shell for driving the app (multi-command session).')
    .action(async () => {
      await withConnector(program, async (connector, target) => {
        const rl = readline.createInterface({
          input: process.stdin,
          output: process.stdout,
          terminal: process.stdout.isTTY,
        });
        const label = () => chalk.cyanBright(`fc[${target.displayName}]> `);
        const prompt = () => rl.setPrompt(label());
        prompt();
        rl.prompt();

        // --watch-uri: auto-reconnect on .vm_service_uri content change.
        const watchUri = program.opts<{ watchUri?: boolean }>().watchUri === true;
        let watcher: UriFileWatcher | null = null;
        if (watchUri) {
          if (!target.autoUriPath) {
            process.stderr.write(
              chalk.yellow(
                '! --watch-uri requires URI auto-detection; ignored because --uri was used.\n',
              ),
            );
          } else {
            watcher = new UriFileWatcher(target.autoUriPath);
            watcher.on('change', async (newUri: string) => {
              process.stdout.write(
                chalk.yellow(`\n⟳ reconnecting: ${newUri}\n`),
              );
              try {
                await reconnectWithBackoff(
                  connector,
                  newUri,
                  target.timeoutMs,
                );
                process.stdout.write(chalk.green(`✓ reconnected\n`));
              } catch (e) {
                process.stdout.write(
                  chalk.red(`✗ reconnect failed: ${(e as Error).message}\n`),
                );
              }
              rl.prompt();
            });
            await watcher.start();
          }
        }

        await new Promise<void>((resolve) => {
          rl.on('line', async (raw) => {
            const line = raw.trim();
            if (!line) {
              rl.prompt();
              return;
            }
            if (line === 'exit' || line === 'quit' || line === '.exit') {
              rl.close();
              return;
            }
            if (line === 'help' || line === '?') {
              printHelp();
              rl.prompt();
              return;
            }
            try {
              await runReplCommand(line, connector);
            } catch (e) {
              process.stdout.write(chalk.red(`! ${(e as Error).message}\n`));
            }
            rl.prompt();
          });
          rl.on('close', () => {
            watcher?.stop();
            resolve();
          });
        });
      });
    })
    .addHelpText(
      'after',
      `
Syntax: \`<action> [key=value ...]\` — one command per line.

Examples (at the fc> prompt):
  tap text="Increment"
  enter-text key=UsernameField input="demo user"
  swipe key=Feed direction=up distance=400
  navigate action=push route=/settings
  take-screenshots output=/tmp/s.png
  reload
  get-interactive-elements
  get-logs 20
  help

Aliases: dtap (double-tap), lpress (long-press), text (enter-text),
scroll (scroll-to), nav (navigate), shot (take-screenshots), ls (get-interactive-elements).

Combine with \`--watch-uri\` to transparently reconnect across \`flutter run\`
restarts without leaving the session.
`,
    );
}

async function runReplCommand(line: string, c: FlutterCopilotConnector): Promise<void> {
  const [action, ...rest] = tokenize(line);
  const args = parseKV(rest);
  switch (action) {
    case 'tap':
      ok(await c.tap(buildMatcher(args as MatcherArgs)));
      break;
    case 'double-tap':
    case 'dtap':
      ok(await c.doubleTap(buildMatcher(args as MatcherArgs)));
      break;
    case 'long-press':
    case 'lpress': {
      const dur = args['duration'] ? Number(args['duration']) : undefined;
      ok(await c.longPress(buildMatcher(args as MatcherArgs), dur));
      break;
    }
    case 'enter-text':
    case 'text': {
      const input = String(args['input'] ?? '');
      ok(await c.enterText(buildMatcher(args as MatcherArgs), input));
      break;
    }
    case 'scroll-to':
    case 'scroll':
      ok(await c.scrollTo(buildMatcher(args as MatcherArgs)));
      break;
    case 'swipe': {
      const dir = String(args['direction'] ?? 'up') as 'up' | 'down' | 'left' | 'right';
      const dist = args['distance'] ? Number(args['distance']) : undefined;
      ok(await c.swipe(buildMatcher(args as MatcherArgs), dir, dist));
      break;
    }
    case 'get-interactive-elements':
    case 'ls': {
      const r = await c.getInteractiveElements();
      process.stdout.write(JSON.stringify(r['elements'] ?? r, null, 2) + '\n');
      break;
    }
    case 'get-logs': {
      const limit = rest[0] ? Number(rest[0]) : 20;
      const r = await c.getLogs();
      const entries = Array.isArray(r.logs) ? r.logs : [];
      const slice = entries.slice(Math.max(0, entries.length - limit));
      for (const e of slice) {
        process.stdout.write(typeof e === 'string' ? e + '\n' : JSON.stringify(e) + '\n');
      }
      break;
    }
    case 'get-rebuild-snapshot': {
      const r = await c.getRebuildSnapshot(10);
      process.stdout.write(JSON.stringify(r, null, 2) + '\n');
      break;
    }
    case 'reload':
    case 'hot-reload': {
      const s = await c.hotReload();
      process.stdout.write(s ? chalk.green('✓ reloaded\n') : chalk.red('✗ reload failed\n'));
      break;
    }
    case 'take-screenshots':
    case 'shot': {
      const out = String(args['output'] ?? args['o'] ?? `fc-${Date.now()}.png`);
      const forceNumbered = args['numbered'] === true || args['numbered'] === 'true';
      const r = await c.takeScreenshots();
      const shots = r.screenshots ?? [];
      if (shots.length === 0) throw new Error('no screenshots captured');
      const saved: string[] = [];
      for (let i = 0; i < shots.length; i++) {
        const p = resolveShotPath(out, i, shots.length, forceNumbered);
        await fs.mkdir(path.dirname(p), { recursive: true });
        await fs.writeFile(p, Buffer.from(shots[i] ?? '', 'base64'));
        saved.push(p);
      }
      process.stdout.write(chalk.green(`✓ saved ${saved.join(', ')}\n`));
      break;
    }
    case 'navigate':
    case 'nav': {
      const act = String(args['action'] ?? 'push') as
        | 'push'
        | 'pop'
        | 'replace'
        | 'pushReplacement'
        | 'popUntil';
      const route = args['route'] ? String(args['route']) : undefined;
      const parsedArgs =
        typeof args['arguments'] === 'string'
          ? JSON.parse(args['arguments']) as Record<string, unknown>
          : undefined;
      ok(await c.navigate(act, route, parsedArgs));
      break;
    }
    default:
      throw new Error(`unknown command: ${action}. type 'help'.`);
  }
}

function ok(r: Record<string, unknown>): void {
  const msg = r['message'] ?? 'ok';
  process.stdout.write(chalk.green(`✓ ${msg}\n`));
}

function printHelp(): void {
  const lines = [
    'commands:',
    '  tap       <key|text|type|x|y>=...',
    '  double-tap <matcher>     (alias: dtap)',
    '  long-press <matcher> duration=<ms>  (alias: lpress)',
    '  enter-text <matcher> input="..."    (alias: text)',
    '  scroll-to <matcher>                 (alias: scroll)',
    '  swipe <matcher> direction=up|down|left|right distance=<px>',
    '  navigate action=push|pop|replace|pushReplacement|popUntil route=<name> arguments=<json>   (alias: nav)',
    '  get-interactive-elements            (alias: ls)',
    '  get-logs [N]',
    '  get-rebuild-snapshot',
    '  hot-reload                          (alias: reload)',
    '  take-screenshots output=<path>      (alias: shot)',
    '  help | exit',
    '',
    'matcher keys: key, text, type, x, y, focused',
    'example: tap text="Increment"',
  ].join('\n');
  process.stdout.write(chalk.gray(lines + '\n'));
}

/** Splits a line respecting double/single quotes. Does not interpret escapes beyond `\"`. */
function tokenize(line: string): string[] {
  const out: string[] = [];
  let buf = '';
  let quote: '"' | "'" | null = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]!;
    if (quote) {
      if (ch === '\\' && line[i + 1] === quote) {
        buf += line[++i];
        continue;
      }
      if (ch === quote) {
        quote = null;
        continue;
      }
      buf += ch;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch as '"' | "'";
      continue;
    }
    if (/\s/.test(ch)) {
      if (buf.length) {
        out.push(buf);
        buf = '';
      }
      continue;
    }
    buf += ch;
  }
  if (buf.length) out.push(buf);
  return out;
}

function parseKV(tokens: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (const t of tokens) {
    const eq = t.indexOf('=');
    if (eq === -1) {
      out[t] = true;
    } else {
      out[t.slice(0, eq)] = t.slice(eq + 1);
    }
  }
  return out;
}
