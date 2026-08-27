import { EventEmitter } from 'node:events';
import { promises as fs, watch, type FSWatcher } from 'node:fs';
import path from 'node:path';

/**
 * Watches a `.vm_service_uri` file for **content** changes.
 *
 * `fs.watch` fires for every mtime touch; we re-read on each event and only
 * emit `change(newUri, path)` when the normalised content differs from the
 * last value we handed out. That way tools like `tee`/`cp` that rewrite the
 * same URI (e.g. while flutter just hot-reloaded, same VM port) stay quiet.
 *
 * To be robust against editors that replace-via-rename and against the file
 * not existing yet, the watcher observes the *parent directory* and filters
 * by basename. When the file appears/disappears/reappears, the watcher keeps
 * running.
 *
 * Emits:
 *   - `change` (newUri, filePath) — once per unique value
 *   - `error` (err)
 */
export class UriFileWatcher extends EventEmitter {
  private watcher: FSWatcher | null = null;
  private lastUri: string | null = null;
  /** Debounces mtime bursts from editors that write in several syscalls. */
  private debounceTimer: NodeJS.Timeout | null = null;

  constructor(
    public readonly filePath: string,
    public readonly debounceMs = 100,
  ) {
    super();
  }

  /** Starts watching the file's parent dir. Returns the initial URI if the
   *  file already exists with content; null otherwise. */
  async start(): Promise<string | null> {
    const dir = path.dirname(this.filePath);
    const base = path.basename(this.filePath);

    const initial = await this.readOnce();
    if (initial) this.lastUri = initial;

    this.watcher = watch(dir, (_ev, filename) => {
      // macOS 的 fsevents 偶尔会把 filename 传成 null (尤其是文件刚被 create 时)。
      // 此时不要基于 basename 过滤 — check() 里会重新读文件, 内容没变就 no-op,
      // 宁可多跑一次 readFile 也不能漏掉创建事件。
      if (filename != null && filename !== base) return;
      this.schedule();
    });
    this.watcher.on('error', (err) => this.emit('error', err));

    return initial;
  }

  stop(): void {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
    }
  }

  private schedule(): void {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.check();
    }, this.debounceMs);
  }

  private async check(): Promise<void> {
    const current = await this.readOnce();
    if (!current) return;
    if (current === this.lastUri) return;
    this.lastUri = current;
    this.emit('change', current, this.filePath);
  }

  private async readOnce(): Promise<string | null> {
    try {
      const raw = await fs.readFile(this.filePath, 'utf8');
      const uri = raw.trim().replace(/^["']|["']$/g, '');
      return uri.length === 0 ? null : uri;
    } catch {
      return null;
    }
  }
}
