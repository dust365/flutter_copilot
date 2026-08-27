import path from 'node:path';

/** Pick the final file path for the i-th screenshot of a multi-view capture.
 *
 * Default (backward-compatible with pre-1.0.4 behaviour):
 *   - 1 view  → raw `output`
 *   - N views → index 0 raw, index 1..N-1 get `_N` suffix
 *
 * With `forceNumbered=true` (CLI `--numbered`, YAML `numbered: true`):
 *   - every file — including index 0 — gets `_N`
 *
 * Numbered mode is the right choice when running the same command repeatedly:
 * without it, a single-view day leaves `shot.png` which a later multi-view run
 * then overwrites.
 */
export function resolveShotPath(
  output: string,
  index: number,
  total: number,
  forceNumbered: boolean,
): string {
  if (!forceNumbered && total === 1) return output;
  if (!forceNumbered && index === 0) return output;
  const ext = path.extname(output);
  const base = output.slice(0, output.length - ext.length);
  return `${base}_${index}${ext}`;
}
