import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { UriFileWatcher } from '../src/vm/uri_watcher.js';

describe('UriFileWatcher', () => {
  let dir: string;
  let file: string;

  beforeEach(async () => {
    dir = await mkdtemp(path.join(os.tmpdir(), 'fc-watch-'));
    file = path.join(dir, '.vm_service_uri');
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('returns null and waits when file does not exist yet', async () => {
    const w = new UriFileWatcher(file, 20);
    const initial = await w.start();
    expect(initial).toBeNull();

    const changes: string[] = [];
    w.on('change', (uri: string) => changes.push(uri));

    await writeFile(file, 'ws://late/ws\n');
    // Debounce (20ms) + small fs.watch latency budget
    await sleep(150);
    w.stop();

    expect(changes).toEqual(['ws://late/ws']);
  });

  it('returns current value at start() when file already exists', async () => {
    await writeFile(file, 'ws://init/ws\n');
    const w = new UriFileWatcher(file, 20);
    const initial = await w.start();
    expect(initial).toBe('ws://init/ws');
    w.stop();
  });

  it('emits only on content change, not on same-content rewrites', async () => {
    await writeFile(file, 'ws://same/ws');
    const w = new UriFileWatcher(file, 20);
    await w.start();

    const changes: string[] = [];
    w.on('change', (uri: string) => changes.push(uri));

    // Touch the file with the same content.
    await writeFile(file, 'ws://same/ws');
    await sleep(120);
    // Now actually change it.
    await writeFile(file, 'ws://new/ws');
    await sleep(120);

    w.stop();
    expect(changes).toEqual(['ws://new/ws']);
  });

  it('handles multiple distinct changes', async () => {
    await writeFile(file, 'ws://a/ws');
    const w = new UriFileWatcher(file, 20);
    await w.start();

    const changes: string[] = [];
    w.on('change', (uri: string) => changes.push(uri));

    await writeFile(file, 'ws://b/ws');
    await sleep(120);
    await writeFile(file, 'ws://c/ws');
    await sleep(120);

    w.stop();
    expect(changes).toEqual(['ws://b/ws', 'ws://c/ws']);
  });
});

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
