import type { Matcher } from './vm/connector.js';

export interface MatcherArgs {
  key?: string;
  text?: string;
  type?: string;
  x?: string | number;
  y?: string | number;
  focused?: boolean;
}

/** Builds a `Matcher` from CLI option values; returns `{}` if all empty. */
export function buildMatcher(args: MatcherArgs): Matcher {
  const m: Matcher = {};
  if (args.key) m.key = args.key;
  if (args.text !== undefined) m.text = args.text;
  if (args.type) m.type = args.type;
  if (args.x !== undefined) m.x = toNum(args.x);
  if (args.y !== undefined) m.y = toNum(args.y);
  if (args.focused) m.focused = true;
  return m;
}

export function isMatcherEmpty(m: Matcher): boolean {
  return Object.keys(m).length === 0;
}

function toNum(v: string | number): number {
  if (typeof v === 'number') return v;
  const n = Number(v);
  if (Number.isNaN(n)) throw new Error(`Not a number: ${v}`);
  return n;
}
