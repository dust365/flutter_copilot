import { promises as fs } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

export interface InstanceInfo {
  name: string;
  uri: string;
  registeredAt: string; // ISO-8601
}

const NAME_RE = /^[A-Za-z0-9_-]+$/;

export class InvalidInstanceNameError extends Error {
  constructor(name: string) {
    super(`Invalid instance name "${name}". Names must match [A-Za-z0-9_-]+.`);
    this.name = 'InvalidInstanceNameError';
  }
}

/**
 * File-based registry for named Flutter app instances.
 * Defaults to `~/.flutter-copilot/instances/<name>.json`.
 *
 * Write is atomic: a `.tmp` file is renamed over the destination.
 */
export class InstanceRegistry {
  constructor(public readonly baseDir: string = defaultBaseDir()) {}

  static validateName(name: string): void {
    if (!NAME_RE.test(name)) throw new InvalidInstanceNameError(name);
  }

  private filePath(name: string): string {
    return path.join(this.baseDir, `${name}.json`);
  }

  /** Returns true if an existing instance was overwritten. */
  async register(name: string, uri: string): Promise<boolean> {
    InstanceRegistry.validateName(name);
    await fs.mkdir(this.baseDir, { recursive: true });

    const dest = this.filePath(name);
    let existed = false;
    try {
      await fs.access(dest);
      existed = true;
    } catch {
      /* not existed */
    }

    const info: InstanceInfo = {
      name,
      uri,
      registeredAt: new Date().toISOString(),
    };
    const tmp = `${dest}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(info, null, 2));
    await fs.rename(tmp, dest);
    return existed;
  }

  async unregister(name: string): Promise<boolean> {
    InstanceRegistry.validateName(name);
    try {
      await fs.unlink(this.filePath(name));
      return true;
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return false;
      throw err;
    }
  }

  async get(name: string): Promise<InstanceInfo | null> {
    InstanceRegistry.validateName(name);
    try {
      const buf = await fs.readFile(this.filePath(name), 'utf8');
      return JSON.parse(buf) as InstanceInfo;
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw err;
    }
  }

  async listAll(): Promise<InstanceInfo[]> {
    let entries: string[];
    try {
      entries = await fs.readdir(this.baseDir);
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return [];
      throw err;
    }
    const out: InstanceInfo[] = [];
    for (const f of entries) {
      if (!f.endsWith('.json') || f.endsWith('.tmp')) continue;
      try {
        const buf = await fs.readFile(path.join(this.baseDir, f), 'utf8');
        out.push(JSON.parse(buf) as InstanceInfo);
      } catch {
        // skip corrupt entries
      }
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
  }
}

function defaultBaseDir(): string {
  return path.join(
    process.env['HOME'] ?? process.env['USERPROFILE'] ?? '.',
    '.flutter-copilot',
    'instances',
  );
}
