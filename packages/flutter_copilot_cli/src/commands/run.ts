import { Command } from 'commander';
import { promises as fs } from 'node:fs';
import YAML from 'yaml';
import { withConnector } from './base.js';
import { Script } from '../script/schema.js';
import { runScript } from '../script/runner.js';
import * as log from '../logging.js';

export function runCommand(program: Command): void {
  program
    .command('run <script>')
    .description('Run a YAML playbook of actions against the target app.')
    .action(async (scriptPath: string) => {
      const raw = await fs.readFile(scriptPath, 'utf8');
      const parsed = YAML.parse(raw);
      const script = Script.parse(parsed);

      await withConnector(program, async (connector) => {
        const results = await runScript(connector, script);
        const failed = results.filter((r) => !r.ok);
        log.data({
          script: script.name ?? scriptPath,
          total: results.length,
          passed: results.length - failed.length,
          failed: failed.length,
          results,
        });
        if (failed.length > 0) process.exitCode = 1;
      });
    })
    .addHelpText(
      'after',
      `
A playbook is a YAML file with a list of steps. Each step has an \`action\` and
optional \`retry: { attempts, delay }\`. Exits non-zero if any step fails when
\`stopOnFailure: true\` (default).

Supported actions:
  tap, double-tap, long-press, enter-text, scroll-to, swipe, drag,
  navigate, hot-reload, take-screenshots, wait, assert-element

Minimal example for the bundled demo home page (smoke.yaml):

  name: smoke-home
  stopOnFailure: true
  steps:
    - action: assert-element
      text: Flutter Copilot 功能演示
    - action: tap
      text: 点击
    - action: wait
      ms: 300
    - action: take-screenshots
      output: /tmp/fcc-smoke.png
    - action: assert-element
      text: 点击

Then:
  fcc run smoke.yaml
  fcc --json run smoke.yaml | jq '.results[] | select(.ok==false)'

Run \`fcc help-ai\` for the full machine-readable schema.
`,
    );
}
