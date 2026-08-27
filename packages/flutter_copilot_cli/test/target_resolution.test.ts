import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { resolveTargetFromOptions } from '../src/commands/base.js';
import {
  VM_SERVICE_URI_ENV,
  VM_SERVICE_URI_FILENAME,
} from '../src/registry/auto_uri.js';

describe('resolveTargetFromOptions', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'fc-target-'));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('prefers an explicit --uri', async () => {
    await writeFile(path.join(dir, VM_SERVICE_URI_FILENAME), 'ws://file/ws\n');

    const res = await resolveTargetFromOptions({
      uri: 'ws://explicit/ws',
      cwd: dir,
      env: { [VM_SERVICE_URI_ENV]: 'ws://env/ws' },
    });

    expect(res.uri).toBe('ws://explicit/ws');
    expect(res.displayName).toBe('ws://explicit/ws');
  });

  it('uses FLUTTER_COPILOT_URI before .vm_service_uri', async () => {
    await writeFile(path.join(dir, VM_SERVICE_URI_FILENAME), 'ws://file/ws\n');

    const res = await resolveTargetFromOptions({
      cwd: dir,
      env: { [VM_SERVICE_URI_ENV]: 'ws://env/ws' },
    });

    expect(res.uri).toBe('ws://env/ws');
    expect(res.displayName).toBe('$FLUTTER_COPILOT_URI');
  });

  it('uses the nearest .vm_service_uri file', async () => {
    await writeFile(path.join(dir, VM_SERVICE_URI_FILENAME), 'ws://file/ws\n');

    const res = await resolveTargetFromOptions({
      cwd: dir,
      env: {},
    });

    expect(res.uri).toBe('ws://file/ws');
    expect(res.autoUriPath).toBe(path.join(dir, VM_SERVICE_URI_FILENAME));
  });

  it('throws when no current target exists', async () => {
    await expect(resolveTargetFromOptions({ cwd: dir, env: {} })).rejects.toThrow(
      'No VM Service URI',
    );
  });
});
