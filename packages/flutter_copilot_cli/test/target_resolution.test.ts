import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { resolveTargetFromOptions } from '../src/commands/base.js';

describe('resolveTargetFromOptions', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'fc-target-'));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('prefers an explicit --uri', async () => {
    const res = await resolveTargetFromOptions({
      uri: 'ws://explicit/ws',
      cwd: dir,
      env: { FLUTTER_COPILOT_URI: 'ws://env/ws' },
    });

    expect(res.uri).toBe('ws://explicit/ws');
    expect(res.displayName).toBe('ws://explicit/ws');
  });

  it('uses FLUTTER_COPILOT_URI before discovery', async () => {
    const res = await resolveTargetFromOptions({
      cwd: dir,
      env: { FLUTTER_COPILOT_URI: 'ws://env/ws' },
    });

    expect(res.uri).toBe('ws://env/ws');
    expect(res.displayName).toBe('$FLUTTER_COPILOT_URI');
  });

  it('throws when no current target exists', async () => {
    await expect(resolveTargetFromOptions({ cwd: dir, env: {} })).rejects.toThrow(
      'Flutter SDK not found',
    );
  });
});
