import { VmServiceClient, VmRpcError } from './client.js';
import { findFlutterCopilotIsolate } from './discover.js';

/** Widget matcher accepted by `flutter_copilot_claw` (see WidgetMatcher.fromJson). */
export interface Matcher {
  key?: string;
  text?: string;
  type?: string;
  x?: number;
  y?: number;
  focused?: boolean;
}

export interface ExtensionSuccess {
  status: 'Success';
  [k: string]: unknown;
}

export class ExtensionError extends Error {
  public readonly extension: string;
  public readonly reason: string | undefined;
  public readonly traceback: string | undefined;
  constructor(extension: string, reason: string | undefined, traceback?: string) {
    super(`Extension ${extension} failed${reason ? `: ${reason}` : ''}`);
    this.name = 'ExtensionError';
    this.extension = extension;
    this.reason = reason;
    this.traceback = traceback;
  }
}

/**
 * High-level wrapper around the `ext.flutter.flutter_copilot.*` surface.
 *
 * Mirrors the Dart `VmServiceConnector` in `flutter_copilot_mcp` so both CLIs
 * behave identically on the protocol layer.
 */
export class FlutterCopilotConnector {
  private isolateId: string | null = null;
  /** Streams the caller asked to receive events on. Replayed on reconnect. */
  private subscribedStreams = new Set<string>();

  constructor(public readonly client: VmServiceClient) {}

  get connectedIsolateId(): string | null {
    return this.isolateId;
  }

  async connect(uri: string, timeoutMs = 5000): Promise<void> {
    await this.client.connect(uri, timeoutMs);
    // Subscribe to Service events early so we catch DDS service-registration
    // announcements (`s0.reloadSources`, etc.) before `hotReload` is called.
    await this.streamListen('Service');
    this.isolateId = await findFlutterCopilotIsolate(this.client);
  }

  async disconnect(): Promise<void> {
    await this.client.disconnect();
    this.isolateId = null;
    this.subscribedStreams.clear();
  }

  /**
   * Track a VM Service stream subscription so `reconnect()` can replay it.
   *
   * Prefer this over `client.streamListen` directly when the subscription
   * should survive a transparent reconnect — notably the `watch` command's
   * Stdout/Stderr/Extension streams.
   */
  async streamListen(streamId: string): Promise<void> {
    await this.client.streamListen(streamId);
    this.subscribedStreams.add(streamId);
  }

  /**
   * Swaps the underlying WS connection to [newUri] while keeping the same
   * [client] object (so any `client.on('event', ...)` listeners installed
   * by commands remain live), and re-subscribes to every stream that was
   * active on the old connection.
   *
   * Throws if the new URI cannot be reached within [timeoutMs] — callers are
   * expected to implement their own retry/backoff.
   */
  async reconnect(newUri: string, timeoutMs = 5000): Promise<void> {
    const streams = Array.from(this.subscribedStreams);
    try {
      await this.client.disconnect();
    } catch {
      /* best-effort */
    }
    this.isolateId = null;
    this.subscribedStreams.clear();

    await this.client.connect(newUri, timeoutMs);
    for (const s of streams) {
      await this.streamListen(s);
    }
    if (!streams.includes('Service')) {
      await this.streamListen('Service');
    }
    this.isolateId = await findFlutterCopilotIsolate(this.client);
  }

  private requireIsolate(): string {
    if (!this.isolateId) throw new Error('Not connected to a Flutter Copilot isolate');
    return this.isolateId;
  }

  private async call<T extends Record<string, unknown> = Record<string, unknown>>(
    extension: string,
    args: Record<string, unknown> = {},
  ): Promise<T> {
    const isolateId = this.requireIsolate();
    let result: Record<string, unknown>;
    try {
      result = await this.client.callServiceExtension<Record<string, unknown>>(
        `ext.flutter.${extension}`,
        isolateId,
        args,
      );
    } catch (err) {
      if (err instanceof VmRpcError) {
        throw new ExtensionError(extension, err.message);
      }
      throw err;
    }
    if (result['status'] === 'Error') {
      throw new ExtensionError(
        extension,
        result['error'] as string | undefined,
        result['stackTrace'] as string | undefined,
      );
    }
    return result as T;
  }

  // --- flutter_copilot.* extensions (1:1 with claw bindings) ---

  getInteractiveElements() {
    return this.call('flutter_copilot.interactiveElements');
  }

  tap(matcher: Matcher) {
    return this.call('flutter_copilot.tap', matcher as Record<string, unknown>);
  }

  doubleTap(matcher: Matcher) {
    return this.call('flutter_copilot.doubleTap', matcher as Record<string, unknown>);
  }

  longPress(matcher: Matcher, durationMs?: number) {
    const args: Record<string, unknown> = { ...matcher };
    if (durationMs !== undefined) args['duration'] = durationMs;
    return this.call('flutter_copilot.longPress', args);
  }

  enterText(matcher: Matcher, input: string) {
    return this.call('flutter_copilot.enterText', {
      ...(matcher as Record<string, unknown>),
      input,
    });
  }

  scrollTo(matcher: Matcher) {
    return this.call('flutter_copilot.scrollTo', matcher as Record<string, unknown>);
  }

  drag(
    matcher: Matcher,
    opts: { deltaX?: number; deltaY?: number; fromX?: number; fromY?: number; toX?: number; toY?: number },
  ) {
    return this.call('flutter_copilot.drag', {
      ...(matcher as Record<string, unknown>),
      ...opts,
    });
  }

  swipe(matcher: Matcher, direction: 'up' | 'down' | 'left' | 'right', distance?: number) {
    const args: Record<string, unknown> = { ...matcher, direction };
    if (distance !== undefined) args['distance'] = distance;
    return this.call('flutter_copilot.swipe', args);
  }

  navigate(
    action: 'push' | 'pop' | 'replace' | 'pushReplacement' | 'popUntil',
    route?: string,
    args?: Record<string, unknown>,
  ) {
    const params: Record<string, unknown> = { action };
    if (route !== undefined) params['route'] = route;
    if (args !== undefined) params['arguments'] = args;
    return this.call('flutter_copilot.navigate', params);
  }

  getLogs() {
    return this.call<{ status: string; logs: unknown[]; count: number }>(
      'flutter_copilot.getLogs',
    );
  }

  takeScreenshots() {
    return this.call<{ status: string; screenshots: string[] }>(
      'flutter_copilot.takeScreenshots',
    );
  }

  getRebuildSnapshot(topLimit = 20) {
    return this.call<{ status: string; enabled: boolean; [k: string]: unknown }>(
      'flutter_copilot.rebuild.snapshot',
      { topLimit },
    );
  }

  async hotReload(): Promise<boolean> {
    const isolateId = this.requireIsolate();
    // Under DDS (the usual `flutter run` case), `reloadSources` is re-registered
    // by flutter_tools as e.g. `s0.reloadSources`. The plain `reloadSources`
    // call bypasses flutter_tools and fails with "Error while starting Kernel
    // isolate task". Prefer the registered method when available.
    const registered = await this.client.waitForServiceRegistration(
      'reloadSources',
    );
    if (registered) {
      const res = await this.client.call<{ type?: string }>(registered, {
        isolateId,
      });
      return res.type === 'Success';
    }
    const res = await this.client.reloadSources(isolateId);
    return res.success === true || res.type === 'Success';
  }
}
