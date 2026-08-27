# flutter_copilot_claw

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_claw pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_claw)](https://pub.dev/packages/flutter_copilot_claw)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)
[![flutter_copilot_cli npm badge](https://img.shields.io/npm/v/flutter_copilot_cli)](https://www.npmjs.com/package/flutter_copilot_cli)

**`flutter_copilot_claw` is the Flutter-side mounting plugin for Flutter Copilot.**

It runs inside your Flutter app and registers the VM Service extensions used by `flutter_copilot_mcp`.

## Start with flutter_copilot_mcp

**The core product is [`flutter_copilot_mcp`](https://pub.dev/packages/flutter_copilot_mcp).**

- **pub.dev:** [flutter_copilot_mcp](https://pub.dev/packages/flutter_copilot_mcp)
- **GitHub:** [flutter_copilot](https://github.com/dust365/flutter_copilot)

**Complete documentation, installation steps, MCP tool list, Cursor setup, and Claude Code setup are all in `flutter_copilot_mcp`.**

## What this package does

`flutter_copilot_claw` only handles the in-app side:

- mounts Flutter Copilot inside your Flutter app
- registers Flutter Copilot VM Service extensions
- exposes runtime hooks used by the MCP server

If you want the full workflow, quick start, and tool overview, use `flutter_copilot_mcp`.

## Recommended setup

One snippet, works for debug, profile, and release — no `kDebugMode`
branching needed. Both `captureLogs` and `ensureInitialized` collapse
to no-ops in release mode (zero overhead, no VM extensions installed):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  FlutterCopilotBinding.captureLogs(() async {
    FlutterCopilotBinding.ensureInitialized();
    // Any async setup (SystemChrome, plugin init, remote config, …) goes
    // here — its print() output and uncaught errors land in `get_logs`.
    runApp(const MyApp());
  });
}
```

If you don't care about ambient `print()` capture you can drop the outer
wrapper:

```dart
void main() {
  FlutterCopilotBinding.ensureInitialized();
  runApp(const MyApp());
}
```

`captureLogs` is a thin `runZonedGuarded` wrapper — it does not call
`runApp` for you and composes cleanly with other zone-based tooling
(Sentry, Crashlytics, Firebase).

## Logging: `captureLogs` vs `addLog`

Three independent sources feed `get_logs`, each controlled by a
different entry point:

| Source | What gets captured | Enabled by |
|---|---|---|
| Framework errors | `FlutterError.onError` + `PlatformDispatcher.onError` | Automatic — wired inside `ensureInitialized()`. |
| Ambient output | Everything that goes through `print()` / `debugPrint()` and uncaught async errors | `captureLogs(body)` wrapping the block you care about. |
| Explicit markers | Exactly the strings you choose to emit | `FlutterCopilotBinding.addLog(message, isError: false)` at the call site. |

`addLog` is **independent of `captureLogs`** — it writes directly into
the log buffer as soon as `ensureInitialized()` has run, with or without
a surrounding zone. Use it when you want a specific, easy-to-grep marker
in the MCP log stream instead of relying on ambient `print()`.

### When to use which

- **Only `captureLogs`** — zero-touch migration: existing `print()`
  calls across the codebase start showing up in `get_logs` with no
  source changes.
- **Only `addLog`** — you don't want a zone wrapper (minimum footprint,
  easier to reason about) and you're happy to annotate the exact
  lifecycle / business events you care about.
- **Both** — most informative. `captureLogs` catches everything that
  happens to fly by, `addLog` gives you clear high-signal markers
  ("login succeeded", "payment step entered").

### Example: both together

```dart
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  FlutterCopilotBinding.captureLogs(() async {
    FlutterCopilotBinding.ensureInitialized();
    FlutterCopilotBinding.addLog('app:boot:start');
    await SomePlugin.init();
    FlutterCopilotBinding.addLog('app:boot:plugins-ready');
    runApp(const MyApp());
  });
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _login() async {
    FlutterCopilotBinding.addLog('login:attempt');
    try {
      await AuthService.signIn();
      FlutterCopilotBinding.addLog('login:success');
    } catch (e) {
      FlutterCopilotBinding.addLog('login:error: $e', isError: true);
      rethrow; // will also be captured by the outer captureLogs zone
    }
  }
  // …
}
```

### Release behavior

All three entry points are release-safe:
- `captureLogs(body)` → calls `body()` directly, no zone installed.
- `addLog(...)` → no-op.
- `ensureInitialized()` → delegates to `WidgetsFlutterBinding.ensureInitialized()`.

So the same call sites can stay in shipping builds with no `kDebugMode`
guards and no runtime cost.

## Looking for the real docs?

- [flutter_copilot_mcp on pub.dev](https://pub.dev/packages/flutter_copilot_mcp) — MCP server for Cursor / Claude Code / other AI clients
- [flutter_copilot_cli on npm](https://www.npmjs.com/package/flutter_copilot_cli) — terminal / CI CLI (`fcc`), drives the same VM Service extensions without MCP
- [flutter_copilot on GitHub](https://github.com/dust365/flutter_copilot)

**All complete docs, installation, and MCP tools are documented in `flutter_copilot_mcp`.**

## License

Apache License 2.0
