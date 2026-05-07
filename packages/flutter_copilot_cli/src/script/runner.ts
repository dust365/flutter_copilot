import { promises as fs } from 'node:fs';
import path from 'node:path';
import chalk from 'chalk';
import type { FlutterCopilotConnector, Matcher } from '../vm/connector.js';
import type { ScriptT, StepT } from './schema.js';
import { resolveShotPath } from '../screenshot_path.js';

export interface StepResult {
  index: number;
  step: StepT;
  ok: boolean;
  attempts: number;
  durationMs: number;
  error?: string;
}

/**
 * Executes a validated script sequentially.
 * Each step can carry `retry: {attempts, delay}`; failures abort when
 * `script.stopOnFailure` is true.
 */
export async function runScript(
  connector: FlutterCopilotConnector,
  script: ScriptT,
): Promise<StepResult[]> {
  const results: StepResult[] = [];
  for (let i = 0; i < script.steps.length; i++) {
    const step = script.steps[i]!;
    const attempts = step.retry?.attempts ?? 1;
    const delayMs = step.retry?.delay ?? 500;
    const label = step.name ?? step.action;
    const t0 = Date.now();
    let lastError: Error | undefined;
    let ok = false;
    let used = 0;

    for (let a = 1; a <= attempts; a++) {
      used = a;
      try {
        await executeStep(connector, step);
        ok = true;
        break;
      } catch (e) {
        lastError = e as Error;
        if (a < attempts) await sleep(delayMs);
      }
    }
    const dur = Date.now() - t0;
    results.push({ index: i, step, ok, attempts: used, durationMs: dur, error: lastError?.message });
    process.stdout.write(
      ok
        ? `${chalk.green('✓')} [${i + 1}/${script.steps.length}] ${label} (${dur}ms, ${used}x)\n`
        : `${chalk.red('✗')} [${i + 1}/${script.steps.length}] ${label} (${dur}ms): ${lastError?.message}\n`,
    );
    if (!ok && script.stopOnFailure) break;
  }
  return results;
}

async function executeStep(c: FlutterCopilotConnector, step: StepT): Promise<void> {
  const m: Matcher = matcherFrom(step);
  switch (step.action) {
    case 'tap':
      await c.tap(m);
      return;
    case 'double-tap':
      await c.doubleTap(m);
      return;
    case 'long-press':
      await c.longPress(m, step.duration);
      return;
    case 'enter-text':
      await c.enterText(m, step.input);
      return;
    case 'scroll-to':
      await c.scrollTo(m);
      return;
    case 'swipe':
      await c.swipe(m, step.direction, step.distance);
      return;
    case 'drag': {
      const opts: {
        deltaX?: number;
        deltaY?: number;
        fromX?: number;
        fromY?: number;
        toX?: number;
        toY?: number;
      } = {};
      if (step.dx !== undefined) opts.deltaX = step.dx;
      if (step.dy !== undefined) opts.deltaY = step.dy;
      if (step.fromX !== undefined) opts.fromX = step.fromX;
      if (step.fromY !== undefined) opts.fromY = step.fromY;
      if (step.toX !== undefined) opts.toX = step.toX;
      if (step.toY !== undefined) opts.toY = step.toY;
      await c.drag(m, opts);
      return;
    }
    case 'navigate':
      await c.navigate(step.op, step.route, step.arguments);
      return;
    case 'hot-reload': {
      const ok = await c.hotReload();
      if (!ok) throw new Error('hot reload reported failure');
      return;
    }
    case 'screenshot': {
      const r = await c.takeScreenshots();
      const shots = r.screenshots ?? [];
      if (shots.length === 0) throw new Error('no screenshots captured');
      const forceNumbered = step.numbered === true;
      for (let i = 0; i < shots.length; i++) {
        const p = resolveShotPath(step.output, i, shots.length, forceNumbered);
        await fs.mkdir(path.dirname(p), { recursive: true });
        await fs.writeFile(p, Buffer.from(shots[i] ?? '', 'base64'));
      }
      return;
    }
    case 'wait':
      await sleep(step.ms);
      return;
    case 'assert-element': {
      const r = await c.getInteractiveElements();
      const exists = elementExists(r['elements'], m);
      if (exists !== step.exists) {
        throw new Error(
          `assert-element failed: expected exists=${step.exists}, got ${exists}`,
        );
      }
      return;
    }
  }
}

function matcherFrom(step: StepT): Matcher {
  const m: Matcher = {};
  const s = step as Record<string, unknown>;
  if (typeof s['key'] === 'string') m.key = s['key'];
  if (typeof s['text'] === 'string') m.text = s['text'];
  if (typeof s['type'] === 'string') m.type = s['type'];
  if (typeof s['x'] === 'number') m.x = s['x'];
  if (typeof s['y'] === 'number') m.y = s['y'];
  if (s['focused'] === true) m.focused = true;
  return m;
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * Recursively scans an interactive-elements tree and returns true if any node
 * matches. Comparison is loose: each provided matcher field must equal the
 * node's value for that field.
 *
 * Supports `key`, `text`, `type`, and `focused`. (`x`/`y` coordinate matching
 * is a runtime gesture concept and is not part of the static element dump, so
 * it's rejected up front rather than silently returning false.)
 *
 * The claw elements dump uses `data` for `Text` widgets and `text` for
 * `RichText`. Accept either when matching by `text`.
 */
function elementExists(tree: unknown, m: Matcher): boolean {
  if (m.x !== undefined || m.y !== undefined) {
    throw new Error(
      'assert-element does not support x/y coordinate matchers — use key, text, type, or focused.',
    );
  }
  if (
    m.key === undefined &&
    m.text === undefined &&
    m.type === undefined &&
    m.focused !== true
  ) {
    throw new Error(
      'assert-element requires at least one of: key, text, type, focused.',
    );
  }
  const queue: unknown[] = Array.isArray(tree) ? [...tree] : [tree];
  while (queue.length) {
    const node = queue.shift();
    if (!node || typeof node !== 'object') continue;
    const obj = node as Record<string, unknown>;
    const visibleText = obj['data'] ?? obj['text'];
    if (
      (m.key === undefined || obj['key'] === m.key) &&
      (m.text === undefined || visibleText === m.text) &&
      (m.type === undefined || obj['type'] === m.type) &&
      (m.focused !== true || obj['focused'] === true)
    ) {
      return true;
    }
    const children = obj['children'];
    if (Array.isArray(children)) {
      for (const c of children) queue.push(c);
    }
  }
  return false;
}
