import { describe, it, expect } from 'vitest';
import { buildMatcher, isMatcherEmpty } from '../src/matcher.js';

describe('buildMatcher', () => {
  it('returns empty for no args', () => {
    const m = buildMatcher({});
    expect(isMatcherEmpty(m)).toBe(true);
  });

  it('collects defined fields', () => {
    const m = buildMatcher({ key: 'K', text: 'T', type: 'El', x: '10', y: 20, focused: true });
    expect(m).toEqual({ key: 'K', text: 'T', type: 'El', x: 10, y: 20, focused: true });
  });

  it('coerces numeric strings', () => {
    const m = buildMatcher({ x: '1.5', y: '0' });
    expect(m.x).toBe(1.5);
    expect(m.y).toBe(0);
  });

  it('throws on non-numeric x/y strings', () => {
    expect(() => buildMatcher({ x: 'abc' })).toThrow();
  });

  it('does not emit focused:false', () => {
    const m = buildMatcher({ key: 'K' });
    expect('focused' in m).toBe(false);
  });

  it('accepts empty string text (valid matcher)', () => {
    const m = buildMatcher({ text: '' });
    expect(m.text).toBe('');
    expect(isMatcherEmpty(m)).toBe(false);
  });
});
