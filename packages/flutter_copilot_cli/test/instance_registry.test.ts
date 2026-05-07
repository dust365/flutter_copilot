import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  InstanceRegistry,
  InvalidInstanceNameError,
} from '../src/registry/instance_registry.js';

describe('InstanceRegistry', () => {
  let dir: string;
  let reg: InstanceRegistry;

  beforeEach(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'fc-reg-'));
    reg = new InstanceRegistry(dir);
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('round-trips register/get/list', async () => {
    const overwritten = await reg.register('demo', 'ws://127.0.0.1:1/ws');
    expect(overwritten).toBe(false);

    const got = await reg.get('demo');
    expect(got?.name).toBe('demo');
    expect(got?.uri).toBe('ws://127.0.0.1:1/ws');

    const all = await reg.listAll();
    expect(all).toHaveLength(1);
    expect(all[0]?.name).toBe('demo');
  });

  it('overwrites existing instances', async () => {
    await reg.register('demo', 'ws://a');
    const overwritten = await reg.register('demo', 'ws://b');
    expect(overwritten).toBe(true);
    expect((await reg.get('demo'))?.uri).toBe('ws://b');
  });

  it('unregister reports existence', async () => {
    expect(await reg.unregister('missing')).toBe(false);
    await reg.register('demo', 'ws://a');
    expect(await reg.unregister('demo')).toBe(true);
    expect(await reg.get('demo')).toBeNull();
  });

  it('rejects invalid names', async () => {
    await expect(reg.register('bad/name', 'ws://x')).rejects.toBeInstanceOf(
      InvalidInstanceNameError,
    );
  });

  it('listAll handles missing directory', async () => {
    const empty = new InstanceRegistry(path.join(dir, 'no-such'));
    expect(await empty.listAll()).toEqual([]);
  });

  it('listAll sorts by name', async () => {
    await reg.register('zeta', 'ws://z');
    await reg.register('alpha', 'ws://a');
    const names = (await reg.listAll()).map((i) => i.name);
    expect(names).toEqual(['alpha', 'zeta']);
  });
});
