import { describe, it, expect } from 'vitest';
import { mkdtemp, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Script } from '../src/script/schema.js';
import { runScript } from '../src/script/runner.js';
import type { FlutterCopilotConnector, Matcher } from '../src/vm/connector.js';

describe('Script schema', () => {
  it('accepts a well-formed script', () => {
    const s = Script.parse({
      name: 'smoke',
      steps: [
        { action: 'tap', key: 'LoginBtn' },
        { action: 'enter-text', key: 'UsernameField', input: 'demo' },
        { action: 'wait', ms: 100 },
        { action: 'screenshot', output: '/tmp/a.png' },
        { action: 'assert-element', text: 'Welcome' },
      ],
    });
    expect(s.steps).toHaveLength(5);
    expect(s.stopOnFailure).toBe(true); // default
  });

  it('rejects unknown action', () => {
    expect(() =>
      Script.parse({ steps: [{ action: 'teleport' }] }),
    ).toThrow();
  });

  it('rejects enter-text without input', () => {
    expect(() =>
      Script.parse({ steps: [{ action: 'enter-text', key: 'x' }] }),
    ).toThrow();
  });

  it('rejects empty steps', () => {
    expect(() => Script.parse({ steps: [] })).toThrow();
  });
});

// A minimal fake connector that records calls and can be scripted to fail.
class FakeConnector {
  calls: Array<{ method: string; args: unknown }> = [];
  failures: Record<string, number> = {};

  private record<T>(method: string, args: unknown, result: T): T {
    this.calls.push({ method, args });
    if (this.failures[method] && this.failures[method]! > 0) {
      this.failures[method]!--;
      throw new Error(`simulated ${method} failure`);
    }
    return result;
  }

  tap(m: Matcher) {
    return this.record('tap', m, { status: 'Success', message: 'tapped' });
  }
  doubleTap(m: Matcher) {
    return this.record('doubleTap', m, { status: 'Success', message: 'dtapped' });
  }
  longPress(m: Matcher, d?: number) {
    return this.record('longPress', { m, d }, { status: 'Success', message: 'lp' });
  }
  enterText(m: Matcher, input: string) {
    return this.record('enterText', { m, input }, { status: 'Success', message: 'typed' });
  }
  scrollTo(m: Matcher) {
    return this.record('scrollTo', m, { status: 'Success', message: 'scrolled' });
  }
  drag(m: Matcher, o: Record<string, number | undefined>) {
    return this.record('drag', { m, o }, { status: 'Success', message: 'dragged' });
  }
  swipe(m: Matcher, d: string, dist?: number) {
    return this.record('swipe', { m, d, dist }, { status: 'Success', message: 'swiped' });
  }
  navigate(action: string, route?: string) {
    return this.record('navigate', { action, route }, { status: 'Success', message: 'navved' });
  }
  hotReload() {
    return this.record('hotReload', {}, true);
  }
  takeScreenshots() {
    return this.record('takeScreenshots', {}, {
      status: 'Success',
      screenshots: [Buffer.from('PNG').toString('base64')],
    });
  }
  getInteractiveElements() {
    return this.record('getInteractiveElements', {}, {
      status: 'Success',
      elements: [{ text: 'Welcome', children: [] }],
    });
  }
  getLogs() {
    return this.record('getLogs', {}, { status: 'Success', logs: [], count: 0 });
  }
  getRebuildSnapshot() {
    return this.record('getRebuildSnapshot', {}, { status: 'Success', enabled: false });
  }
}

describe('runScript', () => {
  it('runs all steps in order and reports success', async () => {
    const fake = new FakeConnector();
    const s = Script.parse({
      steps: [
        { action: 'tap', key: 'a' },
        { action: 'wait', ms: 1 },
        { action: 'enter-text', key: 'b', input: 'x' },
      ],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r.every((x) => x.ok)).toBe(true);
    expect(fake.calls.map((c) => c.method)).toEqual(['tap', 'enterText']);
  });

  it('retries a failing step and recovers', async () => {
    const fake = new FakeConnector();
    fake.failures['tap'] = 2;
    const s = Script.parse({
      steps: [{ action: 'tap', key: 'a', retry: { attempts: 3, delay: 1 } }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(true);
    expect(r[0]?.attempts).toBe(3);
  });

  it('stops on failure by default', async () => {
    const fake = new FakeConnector();
    fake.failures['tap'] = 5;
    const s = Script.parse({
      steps: [
        { action: 'tap', key: 'a' },
        { action: 'wait', ms: 1 },
      ],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r).toHaveLength(1);
    expect(r[0]?.ok).toBe(false);
  });

  it('continues when stopOnFailure=false', async () => {
    const fake = new FakeConnector();
    fake.failures['tap'] = 5;
    const s = Script.parse({
      stopOnFailure: false,
      steps: [
        { action: 'tap', key: 'a' },
        { action: 'wait', ms: 1 },
      ],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r).toHaveLength(2);
    expect(r[0]?.ok).toBe(false);
    expect(r[1]?.ok).toBe(true);
  });

  it('assert-element positive case', async () => {
    const fake = new FakeConnector();
    const s = Script.parse({
      steps: [{ action: 'assert-element', text: 'Welcome', exists: true }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(true);
  });

  it('assert-element negative case fails', async () => {
    const fake = new FakeConnector();
    const s = Script.parse({
      steps: [{ action: 'assert-element', text: 'Missing', exists: true }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(false);
  });

  it('assert-element with focused=true matches a focused node', async () => {
    // Override: tree has a focused element.
    const fake = new FakeConnector();
    fake.getInteractiveElements = () =>
      Promise.resolve({
        status: 'Success',
        elements: [{ type: 'TextField', focused: true, children: [] }],
      }) as ReturnType<FakeConnector['getInteractiveElements']>;
    const s = Script.parse({
      steps: [{ action: 'assert-element', focused: true, exists: true }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(true);
  });

  it('assert-element with only focused=false rejects (no matcher)', async () => {
    const fake = new FakeConnector();
    const s = Script.parse({
      steps: [{ action: 'assert-element', focused: false, exists: true }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(false);
    expect(r[0]?.error).toMatch(/requires at least one of/);
  });

  it('assert-element rejects x/y coordinate matchers', async () => {
    const fake = new FakeConnector();
    const s = Script.parse({
      steps: [{ action: 'assert-element', x: 10, y: 20, exists: true }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(false);
    expect(r[0]?.error).toMatch(/x\/y coordinate matchers/);
  });

  it('screenshot step writes every view with numbered:true', async () => {
    class MultiViewConnector extends FakeConnector {
      override takeScreenshots() {
        return Promise.resolve({
          status: 'Success',
          screenshots: [
            Buffer.from('A').toString('base64'),
            Buffer.from('B').toString('base64'),
          ],
        }) as ReturnType<FakeConnector['takeScreenshots']>;
      }
    }
    const fake = new MultiViewConnector();
    const dir = await mkdtemp(path.join(tmpdir(), 'fcc-shot-'));
    const out = path.join(dir, 'shot.png');
    const s = Script.parse({
      steps: [{ action: 'screenshot', output: out, numbered: true }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(true);
    const files = (await readdir(dir)).sort();
    expect(files).toEqual(['shot_0.png', 'shot_1.png']);
  });

  it('screenshot step defaults to raw path for index 0 + _N for the rest', async () => {
    class MultiViewConnector extends FakeConnector {
      override takeScreenshots() {
        return Promise.resolve({
          status: 'Success',
          screenshots: [
            Buffer.from('A').toString('base64'),
            Buffer.from('B').toString('base64'),
          ],
        }) as ReturnType<FakeConnector['takeScreenshots']>;
      }
    }
    const fake = new MultiViewConnector();
    const dir = await mkdtemp(path.join(tmpdir(), 'fcc-shot-'));
    const out = path.join(dir, 'shot.png');
    const s = Script.parse({
      steps: [{ action: 'screenshot', output: out }],
    });
    const r = await runScript(fake as unknown as FlutterCopilotConnector, s);
    expect(r[0]?.ok).toBe(true);
    const files = (await readdir(dir)).sort();
    expect(files).toEqual(['shot.png', 'shot_1.png']);
  });
});
