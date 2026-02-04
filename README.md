# Flutter Copilot MCP

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)

**"Playwright MCP/Cursor Browser, but for Flutter apps"**

Flutter Copilot enables AI agents (like Cursor, Claude Code, etc.) to inspect and interact with running Flutter applications. It connects your agent directly to a running app, so it can see the widget tree, tap elements, enter text, scroll, and capture screenshots for automated smoke testing and interaction.

Flutter Copilot keeps the surface area intentionally small. It exposes only a handful of high-signal actions and returns the minimum actionable data, which helps keep prompts focused and context sizes under control.


## Flutter Copilot vs Flutter MCP

The official [Dart & Flutter MCP server](https://docs.flutter.dev/ai/mcp-server) focuses on **development-time** tasks: searching pub.dev, managing dependencies, analyzing code, and inspecting runtime errors. It can also drive the UI, but it does so through Flutter Driver, which introduces extra instrumentation in your app. Flutter Copilot focuses solely (and in an opinionated way) on **runtime interaction**: tapping buttons, entering text, scrolling, and taking screenshots, while requiring minimal changes to your app. Use Flutter MCP to build your app, use Flutter Copilot to test and interact with it with minimal code changes.

## Quick Start

**Note: Your Flutter app must be prepared to be compatible with this MCP.**

1. **Prepare your Flutter app** - Add the `flutter_copilot_claw` package and initialize `FlutterCopilotBinding` in your `main.dart`.
2. **Install the MCP server** - Add `flutter_copilot_mcp` to your projects `dev_dependencies`.
3. **Configure your AI tool** - Add the MCP server command (`dart run flutter_copilot_mcp`) to your tool's configuration (Cursor, Claude, etc.).
4. **Run your app in debug mode** - Look for the VM service URI in the console (e.g., `ws://127.0.0.1:12345/ws`).
5. **Connect and interact** - Ask the AI agent to connect to your app using the URI and start interacting.

## Installation

### 1. Add MCP Server Package

Run the following command to activate the `flutter_copilot_mcp` [global tool](https://dart.dev/tools/pub/cmd/pub-global):

```bash
dart pub global activate flutter_copilot_mcp
```

> [!NOTE]
> You can also install the package as a dev-dependency using
>
> ```bash
> dart pub add dev:flutter_copilot_mcp
> ```
>
> Then invoke the MCP server as `dart run flutter_copilot_mcp`.
> It might be necessary to change the working directory, so that `dart run` is able to find `flutter_copilot_mcp`.
> You can do it like so: `cd ${workspaceFolder}/packages/mypackage && dart run flutter_copilot_mcp` (it will vary between tooling).
>
> If it does not work, we suggest using the global tool method.

### 2. Add Flutter Package

Run the following command in your Flutter app directory:

```bash
flutter pub add flutter_copilot_claw
```

## Flutter App Integration

You need to initialize the `FlutterCopilotBinding` in your app. This binding registers the necessary VM service extensions that the MCP server communicates with.

### Basic Setup

If your app uses standard Flutter widgets (like `ElevatedButton`, `TextField`, `Text`, etc.), the default configuration works out of the box.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  // Initialize Flutter Copilot only in debug mode
  if (kDebugMode) {
    FlutterCopilotBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const MyApp());
}
```

### Log Collection (`get_logs`)

Flutter Copilot collects application logs via Dart's [`logging`](https://pub.dev/packages/logging) package by listening to `Logger.root.onRecord`.
This means **`logging` is required for the MCP to be able to scrape logs**.

If your app doesn't use `logging` (or doesn't emit logs via `Logger(...)`), `get_logs` will likely be empty.
If you already use another logging solution, you may need to bridge it into `logging` for `get_logs` to work. If you'd like first-class support for another logging solution, please open an issue describing your setup and expectations.

### Custom Design System

If you use custom widgets in your design system, you can configure Flutter Copilot to recognize them as interactive elements or extract text from them.

**Why `isInteractiveWidget`?** A typical Flutter screen has hundreds of widgets in its tree - `Padding`, `Container`, `Column`, `SizedBox`, etc. When the AI agent calls `get_interactive_elements`, Flutter Copilot filters this down to only actionable targets: buttons, text fields, switches, sliders, etc. This gives the agent a concise, manageable list instead of an overwhelming dump of layout widgets.

By default, Flutter Copilot recognizes standard Flutter widgets like `ElevatedButton`, `TextField`, and `Switch`. If your app uses custom widgets (e.g., `MyPrimaryButton` that wraps styling around a `GestureDetector`), Flutter Copilot won't know they're tappable unless you tell it. The `isInteractiveWidget` callback lets you mark your custom widget types as interactive, so they appear in the element list and can be targeted by `tap` and other tools.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';
import 'package:my_app/design_system/buttons.dart';
import 'package:my_app/design_system/inputs.dart';

void main() {
  if (kDebugMode) {
    Flutter CopilotBinding.ensureInitialized(
      Flutter CopilotConfiguration(
        // Identify your custom interactive widgets
        isInteractiveWidget: (type) =>
            type == MyPrimaryButton ||
            type == MyTextField ||
            type == MyCheckbox,

        // Extract text from your custom widgets
        extractText: (widget) {
          if (widget is MyText) return widget.data;
          if (widget is MyTextField) return widget.controller?.text;
          return null;
        },
      ),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const MyApp());
}
```

#### Screenshot sizing

By default, Flutter Copilot will downscale screenshots to fit within 2000×2000
physical pixels. You can override this via `maxScreenshotSize` in
`FlutterCopilotConfiguration` (set it to `null` to disable resizing).

## Tool Configuration

Add the MCP server to your AI coding assistant's configuration.

### Cursor

[![Install MCP Server](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/en-US/install-mcp?name=flutter_copilot&config=eyJlbnYiOnt9LCJjb21tYW5kIjoiZmx1dHRlcl9jb3BpbG90X21jcCJ9)

Or manually add to your project's `.cursor/mcp.json` or your global `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

### Google Antigravity

Open the MCP store, click “Manage MCP Servers”, then “View raw config” and add to the opened `mcp_config.json`:

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

### Gemini CLI

Add to your `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

### Claude Code

You can run the following command to add it:

```bash
claude mcp add --transport stdio flutter_copilot -- flutter_copilot_mcp
```

### Copilot

Add to your `mcp.json`:

```json
{
  "servers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

## Available Tools

Once connected, the AI agent has access to these tools:

| Tool | Description |
|------|-------------|
| `connect` | Connect to a Flutter app via its VM service URI (e.g., `ws://127.0.0.1:54321/ws`). |
| `disconnect` | Disconnect from the currently connected app. |
| `get_interactive_elements` | Returns a list of all interactive UI elements (buttons, inputs, etc.) visible on screen. |
| `tap` | Taps an element matching a specific key or visible text. |
| `enter_text` | Enters text into a text field matching a key. |
| `scroll_to` | Scrolls the view until an element matching a key or text becomes visible. |
| `get_logs` | Retrieves application logs collected since the last check (**scraped from Dart `logging` / `Logger.root.onRecord`**). |
| `take_screenshots` | Captures screenshots of all active views and returns them as base64 images. |
| `hot_reload` | Performs a hot reload of the Flutter app, applying code changes without losing state. |

## Example Scenarios

Flutter Copilot shines when used by coding agents to verify their work or explore the app. Here are some real-world scenarios:

### 1. Verify a New Feature

**Context:** You just asked the agent to implement a "Forgot Password" flow.
**Prompt:**
> "Now that you've implemented the Forgot Password screen, let's verify it. Connect to the app, navigate to the login screen, tap 'Forgot Password', enter a valid email, and submit. Check the logs to ensure the API call was made successfully."

### 2. Post-Refactor Smoke Test

**Context:** You performed a large refactor on the navigation logic.
**Prompt:**
> "I've refactored the routing. Please run a quick smoke test: connect to the app, cycle through all tabs in the bottom navigation bar, and verify that each screen loads without throwing exceptions in the logs."

### 3. Debugging UI Issues

**Context:** Users reported a button is unresponsive on the Settings page.
**Prompt:**
> "Investigate the 'Clear Cache' button on the Settings page. Connect to the app, navigate there, find the button using `get_interactive_elements`, tap it, and analyze the logs to see if an error is occurring or if the tap is being ignored."

## How It Works

1. **Initialization**: Your Flutter app initializes `FlutterCopilotBinding`, which registers custom VM service extensions (`ext.flutter.flutter_copilot.*`).
2. **Connection**: The MCP server connects to your app's VM Service URL.
3. **Interaction**: When an AI agent calls a tool (like `tap`), the MCP server translates this into a call to the corresponding VM service extension in your app.
4. **Execution**: The Flutter app executes the action (e.g., simulates a tap gesture) and returns the result.

## Assumptions & Limitations

- **Prefer pasting the VM Service URI manually**: While some tooling can sometimes discover or infer the VM Service endpoint, the most reliable workflow is to copy the `ws://.../ws` URI from your `flutter run` output (or DevTools link) and paste it to the agent when calling `connect`.

- **The agent may not know your app**: Flutter Copilot can "see" the widget tree and interact with UI elements, but it doesn't automatically understand your product's flows, naming conventions, or edge cases. If you want reliable navigation and assertions, provide extra context in the prompt (what screen to reach, expected labels/keys, preconditions, and the goal of the interaction).

- **"Your mileage may vary" interactions**: Some actions are implemented via best-effort simulation of user behavior (gestures, focus, text entry, scrolling). Depending on platform, custom widgets, overlays, or app-specific gesture handling, results may vary. If a flow is flaky, consider exposing clearer widget keys, simplifying hit targets, or adding custom `FlutterCopilotConfiguration` hooks for your design system. And if you hit something that consistently doesn't behave as expected, a small repro in an issue helps us improve it.

## Troubleshooting

- **"Not connected to any app"**: Ensure the AI agent has called `connect` with the valid VM Service URI before using other tools.
- **Finding the URI**: Run your Flutter app in debug mode (`flutter run`). Look for a line like: `The Flutter DevTools debugger and profiler on iPhone 15 Pro is available at: http://127.0.0.1:9101?uri=ws://127.0.0.1:9101/ws`. Use the `ws://...` part.
- **Release Mode**: Flutter Copilot only works in debug (and profile) mode because it relies on the VM Service. It will not work in release builds.
- **Elements not found**: Ensure your widgets are visible. If using custom widgets, make sure they are configured in `FlutterCopilotConfiguration`.

