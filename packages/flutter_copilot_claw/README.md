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

## One-line minimal setup

```dart
FlutterCopilotBinding.ensureInitialized();
```

Typical usage in `main.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  if (kDebugMode) {
    FlutterCopilotBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const MyApp());
}
```

If you also want log capture and uncaught error capture:

```dart
FlutterCopilotBinding.runAppWithConfig(const MyApp());
```

## Looking for the real docs?

- [flutter_copilot_mcp on pub.dev](https://pub.dev/packages/flutter_copilot_mcp) — MCP server for Cursor / Claude Code / other AI clients
- [flutter_copilot_cli on npm](https://www.npmjs.com/package/flutter_copilot_cli) — terminal / CI CLI (`fcc`), drives the same VM Service extensions without MCP
- [flutter_copilot on GitHub](https://github.com/dust365/flutter_copilot)

**All complete docs, installation, and MCP tools are documented in `flutter_copilot_mcp`.**

## License

Apache License 2.0
