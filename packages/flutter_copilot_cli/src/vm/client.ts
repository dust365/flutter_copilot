import { EventEmitter } from 'node:events';
import WebSocket from 'ws';

/** A Dart VM Service JSON-RPC 2.0 event. */
export interface VmEvent {
  kind: string;
  [key: string]: unknown;
}

export class VmRpcError extends Error {
  constructor(
    public readonly code: number,
    message: string,
    public readonly data?: unknown,
  ) {
    super(message);
    this.name = 'VmRpcError';
  }
}

export class VmConnectionError extends Error {
  constructor(message: string, public override readonly cause?: unknown) {
    super(message);
    this.name = 'VmConnectionError';
  }
}

interface PendingCall {
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
}

/**
 * Minimal Dart VM Service client.
 *
 * Implements just the slice the CLI needs:
 *   - `getVM`, `getIsolate`
 *   - `streamListen` / streamNotify events (Stdout/Stderr/Extension/Service)
 *   - `callServiceExtension` (forwards raw to the extension method name)
 *   - `reloadSources`
 *
 * The VM Service uses JSON-RPC 2.0 over a single WebSocket. Requests carry a
 * numeric `id`; replies echo it. Notifications (server-push) come as method
 * `streamNotify` with `{ streamId, event }` params.
 */
export class VmServiceClient extends EventEmitter {
  private ws: WebSocket | null = null;
  private nextId = 1;
  private pending = new Map<number, PendingCall>();
  private closed = false;
  private registeredServices = new Map<string, string>();
  private serviceWaiters = new Map<string, Array<(method: string) => void>>();

  /** Connect to a VM Service WebSocket URI (e.g. `ws://127.0.0.1:8181/abc/ws`). */
  connect(uri: string, timeoutMs = 5000): Promise<void> {
    // Allow reuse after a prior disconnect — reset transport-scoped state.
    this.closed = false;
    this.registeredServices.clear();
    this.serviceWaiters.clear();
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(uri);
      this.ws = ws;

      const onOpenError = (err: Error) => {
        cleanup();
        reject(new VmConnectionError(`Failed to connect to ${uri}: ${err.message}`, err));
      };

      const timer = setTimeout(() => {
        cleanup();
        ws.terminate();
        reject(new VmConnectionError(`Connection to ${uri} timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      const cleanup = () => {
        clearTimeout(timer);
        ws.off('error', onOpenError);
      };

      ws.once('error', onOpenError);
      ws.once('open', () => {
        cleanup();
        ws.on('message', (data) => this.onMessage(data));
        ws.on('close', () => this.onClose());
        ws.on('error', (err) => this.emit('error', err));
        resolve();
      });
    });
  }

  async disconnect(): Promise<void> {
    this.closed = true;
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.close();
    }
    this.ws = null;
    for (const [, p] of this.pending) {
      p.reject(new VmConnectionError('Disconnected before reply'));
    }
    this.pending.clear();
    this.registeredServices.clear();
    this.serviceWaiters.clear();
  }

  /** Generic JSON-RPC call. */
  call<T = unknown>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new VmConnectionError('Not connected'));
    }
    const id = this.nextId++;
    const payload = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    return new Promise<T>((resolve, reject) => {
      this.pending.set(id, {
        resolve: (v) => resolve(v as T),
        reject,
      });
      this.ws!.send(payload, (err) => {
        if (err) {
          this.pending.delete(id);
          reject(new VmConnectionError(`Send failed: ${err.message}`, err));
        }
      });
    });
  }

  /** Call a flutter extension like `ext.flutter.flutter_copilot.tap`. */
  async callServiceExtension<T = Record<string, unknown>>(
    method: string,
    isolateId: string,
    args: Record<string, unknown> = {},
  ): Promise<T> {
    // The VM Service accepts `callServiceExtension` as a convenience wrapper,
    // but calling the extension method name directly with `isolateId` works
    // the same and avoids double-wrapping. The Dart SDK does the same.
    return this.call<T>(method, { ...args, isolateId });
  }

  async getVM(): Promise<{ isolates?: Array<{ id: string }> }> {
    return this.call('getVM');
  }

  async getIsolate(isolateId: string): Promise<{ extensionRPCs?: string[] }> {
    return this.call('getIsolate', { isolateId });
  }

  async streamListen(streamId: string): Promise<void> {
    try {
      await this.call('streamListen', { streamId });
    } catch (err) {
      // 103 "Stream already subscribed" is harmless for our use.
      if (err instanceof VmRpcError && err.code === 103) return;
      throw err;
    }
  }

  async reloadSources(isolateId: string): Promise<{ success?: boolean; type?: string }> {
    return this.call('reloadSources', { isolateId });
  }

  /**
   * Returns the RPC method name registered for a given service, or null if it
   * is not registered (yet). The caller must have already `streamListen`'d on
   * the `Service` stream — `connect()` does this automatically.
   *
   * Under DDS (`flutter run`), `hotReload`/`reloadSources` are re-registered
   * under a namespaced alias like `s0.reloadSources` and the plain call
   * bypasses flutter_tools' reload hook.
   */
  async waitForServiceRegistration(
    name: string,
    timeoutMs = 500,
  ): Promise<string | null> {
    const known = this.registeredServices.get(name);
    if (known) return known;
    return new Promise<string | null>((resolve) => {
      const arr = this.serviceWaiters.get(name) ?? [];
      const handler = (m: string) => resolve(m);
      arr.push(handler);
      this.serviceWaiters.set(name, arr);
      setTimeout(() => {
        const current = this.serviceWaiters.get(name);
        if (current) {
          const idx = current.indexOf(handler);
          if (idx >= 0) current.splice(idx, 1);
          if (current.length === 0) this.serviceWaiters.delete(name);
        }
        resolve(null);
      }, timeoutMs);
    });
  }

  private onMessage(data: WebSocket.RawData): void {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }

    // Notification: `streamNotify` server-push event.
    if (msg['method'] === 'streamNotify' && msg['params']) {
      const params = msg['params'] as { streamId: string; event: VmEvent };
      if (
        params.streamId === 'Service' &&
        typeof params.event['service'] === 'string'
      ) {
        const svc = params.event['service'] as string;
        const method = params.event['method'];
        if (params.event.kind === 'ServiceRegistered' && typeof method === 'string') {
          this.registeredServices.set(svc, method);
          const waiters = this.serviceWaiters.get(svc);
          if (waiters) {
            this.serviceWaiters.delete(svc);
            for (const w of waiters) w(method);
          }
        } else if (params.event.kind === 'ServiceUnregistered') {
          this.registeredServices.delete(svc);
        }
      }
      this.emit('event', params.streamId, params.event);
      this.emit(`event:${params.streamId}`, params.event);
      return;
    }

    // Response to a prior request.
    const id = msg['id'];
    if (typeof id !== 'number') return;
    const pending = this.pending.get(id);
    if (!pending) return;
    this.pending.delete(id);

    if (msg['error']) {
      const err = msg['error'] as { code: number; message: string; data?: unknown };
      pending.reject(new VmRpcError(err.code, err.message, err.data));
      return;
    }
    pending.resolve(msg['result']);
  }

  private onClose(): void {
    if (!this.closed) this.emit('close');
    for (const [, p] of this.pending) {
      p.reject(new VmConnectionError('Connection closed'));
    }
    this.pending.clear();
  }
}
