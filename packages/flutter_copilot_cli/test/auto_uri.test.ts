import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtemp, rm, writeFile, mkdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  autoDetectVmServiceUri,
  findAncestorFile,
  VM_SERVICE_URI_ENV,
  VM_SERVICE_URI_FILENAME,
} from '../src/registry/auto_uri.js';

describe('autoDetectVmServiceUri', () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(path.join(os.tmpdir(), 'fc-auto-'));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it('returns null when nothing is set', async () => {
    const res = await autoDetectVmServiceUri(root, {});
    expect(res).toBeNull();
  });

  it('prefers the env var over a file', async () => {
    await writeFile(path.join(root, VM_SERVICE_URI_FILENAME), 'ws://file/ws\n');
    const res = await autoDetectVmServiceUri(root, {
      [VM_SERVICE_URI_ENV]: 'ws://env/ws',
    });
    expect(res?.source).toBe('env');
    expect(res?.uri).toBe('ws://env/ws');
  });

  it('finds .vm_service_uri in the exact dir', async () => {
    await writeFile(path.join(root, VM_SERVICE_URI_FILENAME), 'ws://x/ws\n');
    const res = await autoDetectVmServiceUri(root, {});
    expect(res?.source).toBe('file');
    expect(res?.uri).toBe('ws://x/ws');
    expect(res?.path).toBe(path.join(root, VM_SERVICE_URI_FILENAME));
  });

  it('walks up to find the file from a nested cwd', async () => {
    const deep = path.join(root, 'a', 'b', 'c');
    await mkdir(deep, { recursive: true });
    await writeFile(path.join(root, VM_SERVICE_URI_FILENAME), 'ws://deep/ws\n');
    const res = await autoDetectVmServiceUri(deep, {});
    expect(res?.uri).toBe('ws://deep/ws');
  });

  it('trims whitespace and surrounding quotes', async () => {
    await writeFile(path.join(root, VM_SERVICE_URI_FILENAME), '  "ws://trim/ws"  \n');
    const res = await autoDetectVmServiceUri(root, {});
    expect(res?.uri).toBe('ws://trim/ws');
  });

  it('returns null for an empty file', async () => {
    await writeFile(path.join(root, VM_SERVICE_URI_FILENAME), '\n\n');
    const res = await autoDetectVmServiceUri(root, {});
    expect(res).toBeNull();
  });
});

describe('findAncestorFile', () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(path.join(os.tmpdir(), 'fc-find-'));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it('returns null when the file is nowhere', async () => {
    expect(await findAncestorFile(root, 'nope.txt')).toBeNull();
  });

  it('stops at the first hit', async () => {
    await writeFile(path.join(root, 'marker'), 'top');
    await mkdir(path.join(root, 'nested'));
    await writeFile(path.join(root, 'nested', 'marker'), 'nested');
    const hit = await findAncestorFile(path.join(root, 'nested'), 'marker');
    expect(hit).toBe(path.join(root, 'nested', 'marker'));
  });
});
