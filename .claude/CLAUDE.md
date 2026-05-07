# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This repo is a Dart workspace with four members declared in the root `pubspec.yaml`:
- `packages/flutter_copilot_claw`: the Flutter-side runtime binding that registers VM service extensions inside a debug Flutter app.
- `packages/flutter_copilot_mcp`: the MCP server/CLI that connects to a running Flutter app over `vm_service` and exposes tools like `connect`, `tap`, `enter_text`, `scroll_to`, `take_screenshots`, `get_logs`, and `hot_reload`.
- `example`: a Flutter demo app used to exercise the binding and MCP features.
- `tool`: repo utilities such as version file generation.

The two published packages share a version. `packages/flutter_copilot_mcp/lib/src/version.g.dart` is generated from both package pubspecs by `dart tool/version.dart`, and CI fails if it is out of sync.

## Common commands

Run commands from the repository root unless noted otherwise.

### Install dependencies
- `dart pub get`
- `cd packages/flutter_copilot_mcp && dart pub get`
- `cd packages/flutter_copilot_claw && flutter pub get`
- `cd example && flutter pub get`
- `cd tool && dart pub get`

### Analyze
- `cd packages/flutter_copilot_mcp && dart analyze --fatal-infos lib bin`
- `cd packages/flutter_copilot_claw && flutter analyze --fatal-infos lib`
- `cd example && flutter analyze`
- `cd tool && dart analyze .`

### Format
- `cd packages/flutter_copilot_mcp && dart format lib bin`
- `cd packages/flutter_copilot_claw && dart format lib test`
- `cd tool && dart format .`
- CI format check uses `dart format --set-exit-if-changed ...`

### Tests
- `cd packages/flutter_copilot_claw && flutter test`
- `cd packages/flutter_copilot_claw && flutter test test/screenshot_service_test.dart`
- `cd example && flutter test`
- `cd packages/flutter_copilot_claw/example && flutter test`
- `cd packages/flutter_copilot_mcp/example && flutter test`

### Run the demo app
- `cd example && flutter run`

### Run the MCP server locally
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart`
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart --help`
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart --version`
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart --sse-port 8080`

### Regenerate version file
- `dart tool/version.dart`

### Publish helper
- `./tool/publish.sh` for dry-run publish
- `./tool/publish.sh --force` for actual pub.dev publish

## Architecture

### End-to-end flow
1. A Flutter app integrates `flutter_copilot_claw` and initializes `FlutterCopilotBinding` in debug mode.
2. `FlutterCopilotBinding` installs services and registers custom VM service extensions under `ext.flutter.flutter_copilot.*`.
3. The `flutter_copilot_mcp` CLI connects to the app's Dart VM service URI.
4. `VmServiceConnector` calls those custom extensions and wraps the responses.
5. `VmServiceContext` registers MCP tools that map almost 1:1 to connector methods and present them to the AI client.

The key split is: `flutter_copilot_claw` runs inside the target Flutter app, while `flutter_copilot_mcp` runs outside the app as the MCP bridge.

### Flutter-side binding (`flutter_copilot_claw`)

The main entry point is `packages/flutter_copilot_claw/lib/src/binding/flutter_copilot_binding.dart`.

Important responsibilities of `FlutterCopilotBinding`:
- Acts as a drop-in replacement for `WidgetsFlutterBinding.ensureInitialized()`.
- Creates the runtime services used by the VM extensions: widget finding/matching, gesture dispatch, text entry, scrolling, screenshots, navigation, log capture, and rebuild tracking.
- Registers VM service extensions for interaction and inspection.
- Optionally captures `print`, Flutter errors, and uncaught async errors via `runAppWithConfig`.
- Optionally enables rebuild tracking through a custom `CopilotBuildOwner`.
- Optionally injects a tap-feedback overlay.

The important design point is that the binding is the composition root for all runtime capabilities; most feature work on the Flutter side either adds a new service used by the binding or a new VM extension registered from the binding.

### MCP-side server (`flutter_copilot_mcp`)

The CLI entry point is `packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart`.

Key pieces:
- `VmServiceConnector`: owns the `vm_service` connection, locates the isolate that exposes Copilot extensions, and provides typed wrapper methods for each extension.
- `VmServiceContext`: registers MCP tools and translates tool arguments/results to connector calls.
- `CopilotCompatStdioServerTransport`: wraps stdio transport and rewrites GitHub Copilot's malformed `initialize.capabilities.tasks.*` fields so the MCP handshake succeeds.

When adding a new capability, the normal path is:
1. Add a VM service extension in `FlutterCopilotBinding`.
2. Add a wrapper method in `VmServiceConnector`.
3. Register an MCP tool in `VmServiceContext`.
4. Update docs/examples if the user-facing workflow changes.

### Matching and interaction model

Element targeting is centered on widget matching. The tool layer accepts `key`, `text`, `type`, or coordinates; the Flutter side resolves that through widget finder/matcher services and then dispatches gestures or text input. Keys are the most reliable contract, so if a flow is hard to automate, adding `ValueKey<String>` in the example app or a consuming app is usually the intended fix.

### Logging and rebuild diagnostics

`runAppWithConfig` is not just a convenience wrapper around `runApp`; it is the path that captures `print()` output and zone errors for `get_logs`. Binding initialization also hooks `FlutterError.onError` and `PlatformDispatcher.instance.onError`.

Rebuild diagnostics are opt-in through `FlutterCopilotConfiguration(enableGlobalRebuildHook: true)`. On Web, rebuild snapshots remain empty because the custom `BuildOwner` hook is not injected there.

## CI expectations

GitHub Actions checks the following:
- `dart tool/version.dart` must leave `packages/flutter_copilot_mcp/lib/src/version.g.dart` unchanged.
- `dart analyze --fatal-infos lib bin` for `flutter_copilot_mcp`.
- `flutter analyze --fatal-infos lib` for `flutter_copilot_claw`.
- formatting checks for `flutter_copilot_mcp`, `flutter_copilot_claw`, and `tool`.

If you change package versions, regenerate `version.g.dart` in the same change.

## Known repo-specific notes

- The root workspace exists, but CI still installs/analyzes package directories individually; prefer the per-package commands above when verifying changes.
- `tool/publish.sh` publishes from temporary copied package directories after removing `resolution: workspace` from pubspec files, so publishing logic should be kept compatible with that flow.
- The demo and package examples are useful manual verification targets when changing gesture dispatch, logging, screenshotting, navigation, or rebuild-tracking behavior.