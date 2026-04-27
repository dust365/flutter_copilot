# flutter_copilot_mcp

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)
[![flutter_copilot_claw pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_claw)](https://pub.dev/packages/flutter_copilot_claw)

**Flutter MCP for Cursor, Claude Code, and AI agents. Inspect, control, test, and debug a running Flutter app through VM Service.**

Flutter Copilot MCP is an MCP server for Flutter app automation. It gives AI agents Playwright-like control over a live Flutter app: connect to the app, inspect interactive widgets, tap elements, enter text, scroll, take screenshots, read logs, navigate, hot reload, and inspect rebuild hotspots.

<a href="https://github.com/dust365/flutter_copilot/blob/main/docs/video/%E6%BC%94%E7%A4%BA%E8%A7%86%E9%A2%91.mp4">
  <img src="https://github.com/dust365/flutter_copilot/blob/v1.0.0/docs/images/demo-preview.gif" alt="Flutter Copilot Demo" width="360" />
</a>

See the full demo video in the repository: [演示视频](https://github.com/dust365/flutter_copilot/blob/main/docs/video/%E6%BC%94%E7%A4%BA%E8%A7%86%E9%A2%91.mp4).

If you are searching for **Flutter MCP**, **Flutter AI automation**, **Cursor Flutter MCP**, **Claude Code Flutter**, **Flutter app inspection**, or **Flutter UI testing with AI**, this package is the main entry.

## What is Flutter Copilot MCP

Flutter Copilot MCP is the main package of the Flutter Copilot project.

It is designed for runtime interaction instead of static analysis:

- connect directly to a running Flutter app through VM Service
- inspect the current UI before taking action
- let AI agents drive smoke tests and manual validation flows
- capture screenshots and logs without switching tools
- debug rebuild hotspots and interaction failures faster

## Package layout

Flutter Copilot has two packages:

- [`flutter_copilot_mcp`](https://pub.dev/packages/flutter_copilot_mcp): the MCP server used by Cursor, Claude Code, and other MCP clients
- [`flutter_copilot_claw`](https://pub.dev/packages/flutter_copilot_claw): the Flutter-side mounting plugin added inside your app

In one sentence:

> `flutter_copilot_claw` runs inside the app, and `flutter_copilot_mcp` runs outside the app so an AI agent can inspect and operate the running UI.

## Quick start

### 1. Add the Flutter runtime plugin

```bash
flutter pub add flutter_copilot_claw
```

### 2. Initialize Flutter Copilot in `main.dart`

For UI interaction only:

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

If you also want `get_logs` to capture `print()` output and uncaught errors:

```dart
void main() {
  if (kDebugMode) {
    FlutterCopilotBinding.runAppWithConfig(const MyApp());
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  }
}
```

### 3. Install the MCP server

Global install:

```bash
dart pub global activate flutter_copilot_mcp
```

Or as a dev dependency:

```bash
dart pub add dev:flutter_copilot_mcp
```

### 4. Start your Flutter app

```bash
flutter run
```

Copy the VM Service URI from the console, for example:

```text
ws://127.0.0.1:12345/ws
```

### 5. Connect from your MCP client

#### Claude Code

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- flutter_copilot_mcp
```

For local source debugging in this repository:

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

#### Cursor

Cursor reads `.cursor/mcp.json`.

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "type": "stdio",
      "command": "flutter_copilot_mcp"
    }
  }
}
```

## MCP tool list

After calling `connect`, an agent can use these MCP tools:

- `connect`
- `disconnect`
- `get_interactive_elements`
- `tap`
- `enter_text`
- `scroll_to`
- `get_logs`
- `get_rebuild_snapshot`
- `take_screenshots`
- `hot_reload`
- `flutter_copilot_drag`
- `swipe`
- `long_press`
- `double_tap`
- `navigate`

## Typical workflows

### Smoke testing

- open a screen
- inspect interactive elements
- tap buttons and enter text
- verify the UI with screenshots
- capture logs when a flow fails

### UI debugging

- connect to a running debug build
- inspect the current page without guessing selectors
- reproduce issues with tap, swipe, drag, and navigation
- read logs and hot reload changes quickly

### Performance investigation

- use `get_rebuild_snapshot`
- find rebuild hotspots
- trace unstable widgets and noisy `setState` usage

## Why this is easier to automate than generic UI tools

- uses Flutter runtime data instead of guessing from pixels alone
- works well with `ValueKey<String>` targeting
- keeps interaction and diagnostics in one MCP server
- fits Cursor and Claude Code workflows naturally

## Best practices

- use `ValueKey<String>` for stable targeting
- run the app in **Debug** or **Profile** mode, not Release
- use `FlutterCopilotBinding.runAppWithConfig` when logs matter
- if a flow is hard to automate, add explicit keys in the app

## Limitations

- Release mode is not supported
- `get_rebuild_snapshot` requires `enableGlobalRebuildHook: true`
- on Web, rebuild snapshots remain empty because BuildOwner hook injection is unavailable

## Local development

Run the example app:

```bash
cd example && flutter run
```

Run the MCP server from source:

```bash
cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart -l FINEST
```

Useful checks:

```bash
cd packages/flutter_copilot_mcp && dart analyze --fatal-infos lib bin
cd packages/flutter_copilot_claw && flutter analyze --fatal-infos lib
cd packages/flutter_copilot_claw && flutter test
cd example && flutter analyze
cd example && flutter test
dart tool/generate_version.dart
```

## More documentation

- [Repository home](https://github.com/dust365/flutter_copilot)
- [项目说明](https://github.com/dust365/flutter_copilot/blob/main/docs/项目说明.md)
- [VM Service 连接原理与实现](https://github.com/dust365/flutter_copilot/blob/main/docs/VM_Service连接原理与实现.md)
- [Claude Code 调试本地 MCP 教程](https://github.com/dust365/flutter_copilot/blob/main/docs/ClaudeCode调试本地MCP教程.md)

## License

Apache License 2.0
