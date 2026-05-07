import { describe, it, expect } from 'vitest';
import { resolveShotPath } from '../src/screenshot_path.js';

describe('resolveShotPath', () => {
  it('returns raw path for single view (default)', () => {
    expect(resolveShotPath('/tmp/shot.png', 0, 1, false)).toBe('/tmp/shot.png');
  });

  it('multi-view default: index 0 raw, rest numbered', () => {
    expect(resolveShotPath('/tmp/shot.png', 0, 3, false)).toBe('/tmp/shot.png');
    expect(resolveShotPath('/tmp/shot.png', 1, 3, false)).toBe('/tmp/shot_1.png');
    expect(resolveShotPath('/tmp/shot.png', 2, 3, false)).toBe('/tmp/shot_2.png');
  });

  it('--numbered forces _N on every file, including single view', () => {
    expect(resolveShotPath('/tmp/shot.png', 0, 1, true)).toBe('/tmp/shot_0.png');
    expect(resolveShotPath('/tmp/shot.png', 0, 3, true)).toBe('/tmp/shot_0.png');
    expect(resolveShotPath('/tmp/shot.png', 1, 3, true)).toBe('/tmp/shot_1.png');
  });

  it('preserves the extension and base segments regardless of depth', () => {
    expect(resolveShotPath('a/b/c.png', 1, 2, false)).toBe('a/b/c_1.png');
    expect(resolveShotPath('a/b/c.png', 0, 1, true)).toBe('a/b/c_0.png');
  });

  it('handles paths without an extension', () => {
    expect(resolveShotPath('/tmp/shot', 0, 1, true)).toBe('/tmp/shot_0');
    expect(resolveShotPath('/tmp/shot', 2, 3, false)).toBe('/tmp/shot_2');
  });
});
