import { promises as fs } from 'node:fs';
import path from 'node:path';

export interface AutoUriResult {
  uri: string;
  source: 'env' | 'file';
  /** For `source === 'file'`, the absolute path of the `.vm_service_uri` file. */
  path?: string;
}

/** Filename convention shared with `scripts/flutter_run.sh`. */
export const VM_SERVICE_URI_FILENAME = '.vm_service_uri';

/** Env var a caller can set to pin a URI without passing `--uri`. */
export const VM_SERVICE_URI_ENV = 'FLUTTER_COPILOT_URI';

/**
 * Looks for a VM Service URI without explicit CLI args.
 *
 * Resolution order:
 *   1. `FLUTTER_COPILOT_URI` environment variable.
 *   2. Nearest `.vm_service_uri` file, walking up from `cwd` to filesystem root.
 *      This file is written by `scripts/flutter_run.sh` when it wraps `flutter run`.
 *
 * Returns `null` if neither is set. The file is accepted only when it has a
 * non-blank line; trailing whitespace and surrounding quotes are trimmed.
 */
export async function autoDetectVmServiceUri(
  cwd: string = process.cwd(),
  env: NodeJS.ProcessEnv = process.env,
): Promise<AutoUriResult | null> {
  const fromEnv = env[VM_SERVICE_URI_ENV];
  if (fromEnv && fromEnv.trim().length > 0) {
    return { uri: fromEnv.trim(), source: 'env' };
  }

  const filePath = await findAncestorFile(cwd, VM_SERVICE_URI_FILENAME);
  if (!filePath) return null;

  let raw: string;
  try {
    raw = await fs.readFile(filePath, 'utf8');
  } catch {
    return null;
  }
  const uri = raw.trim().replace(/^["']|["']$/g, '');
  if (uri.length === 0) return null;
  return { uri, source: 'file', path: filePath };
}

/**
 * Walks up from [start] looking for a file named [name]. Returns the absolute
 * path of the first hit, or null if none is found up to the filesystem root.
 */
export async function findAncestorFile(
  start: string,
  name: string,
): Promise<string | null> {
  let dir = path.resolve(start);
  // A zero-length `path.dirname` plateau signals we've reached the root.
  while (true) {
    const candidate = path.join(dir, name);
    try {
      const stat = await fs.stat(candidate);
      if (stat.isFile()) return candidate;
    } catch {
      /* not there, continue up */
    }
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}
