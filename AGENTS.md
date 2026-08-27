# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Repository overview

This repo hosts three published packages plus supporting members:
- `packages/flutter_copilot_claw` (Dart/Flutter, pub.dev): the Flutter-side runtime binding that registers VM service extensions (`ext.flutter.flutter_copilot.*`) inside a debug Flutter app.
- `packages/flutter_copilot_mcp` (Dart, pub.dev): the MCP server/CLI that connects to a running Flutter app over `vm_service` and exposes tools like `connect`, `tap`, `enter_text`, `scroll_to`, `take_screenshots`, `get_logs`, and `hot_reload`.
- `packages/flutter_copilot_cli` (TypeScript/Node >= 18, npm): a human/CI-oriented CLI (binaries `fcc` and `flutter_copilot_cli`) that drives the same VM service extensions directly — an alternative consumer to the MCP server. Built with pnpm/tsc, tested with vitest. It is **not** a member of the Dart workspace.
- `example`: a Flutter demo app used to exercise the binding and MCP/CLI features.
- `tool`: repo utilities (version tool, publish scripts).

The root `pubspec.yaml` declares a Dart workspace with members `packages/flutter_copilot_mcp`, `packages/flutter_copilot_claw`, `example`, and `tool`.

All three published packages share one version. `dart tool/version.dart` is the only writer of the generated version files: `packages/flutter_copilot_mcp/lib/src/version.g.dart` (Dart) and `packages/flutter_copilot_cli/src/version.generated.ts` (TS), both derived from the three manifests (two pubspecs + `package.json`). CI fails if `version.g.dart` is out of sync.

## Common commands

Run commands from the repository root unless noted otherwise.

### Install dependencies
- `dart pub get`
- `cd packages/flutter_copilot_mcp && dart pub get`
- `cd packages/flutter_copilot_claw && flutter pub get`
- `cd packages/flutter_copilot_cli && pnpm install`
- `cd example && flutter pub get`
- `cd tool && dart pub get`

### Analyze / typecheck
- `cd packages/flutter_copilot_mcp && dart analyze --fatal-infos lib bin`
- `cd packages/flutter_copilot_claw && flutter analyze --fatal-infos lib`
- `cd packages/flutter_copilot_cli && pnpm typecheck`
- `cd example && flutter analyze`
- `cd tool && dart analyze .`

### Format
- `cd packages/flutter_copilot_mcp && dart format lib bin`
- `cd packages/flutter_copilot_claw && dart format lib test`
- `cd tool && dart format .`
- CI format check uses `dart format --set-exit-if-changed ...`

### Tests
- `cd packages/flutter_copilot_claw && flutter test`
- `cd packages/flutter_copilot_claw && flutter test test/screenshot_service_test.dart` (single file)
- `cd packages/flutter_copilot_cli && pnpm test`
- `cd packages/flutter_copilot_cli && pnpm vitest run test/matcher.test.ts` (single file)
- `cd example && flutter test`
- `cd packages/flutter_copilot_claw/example && flutter test`
- `cd packages/flutter_copilot_mcp/example && flutter test`

### Run the demo app
- `cd example && flutter run`
- `./scripts/flutter_run.sh -d <device>` — wraps `flutter run`, captures the VM Service URI, and writes it to `.vm_service_uri` at the repo root (also usable as a VS Code Dart extension `customTool`). The CLI auto-discovers targets from `FLUTTER_COPILOT_URI` or the nearest `.vm_service_uri`.

### Run the MCP server locally
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart`
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart --help`
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart --version`
- `cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart --sse-port 8080`

### Run the TypeScript CLI locally
- `cd packages/flutter_copilot_cli && pnpm dev -- <command>` (runs from source via tsx)
- `cd packages/flutter_copilot_cli && pnpm build` then `node dist/index.js <command>`
- `fcc help-ai` prints the full command surface + YAML script schema as JSON
- `fcc run <script.yaml>` executes a YAML playbook (see `packages/flutter_copilot_cli/examples/smoke.yaml`)

### Version management
- `dart tool/version.dart` — verify the three packages are aligned and regenerate `version.g.dart` / `version.generated.ts` (idempotent)
- `dart tool/version.dart --set 1.0.4` — bump all three packages, then regenerate
- `dart tool/version.dart --check` — CI-safe: exits 1 if regeneration would change generated files
- `dart tool/version.dart --print` — print the current shared version

### Publish helpers
`tool/publish.sh` orchestrates all three packages (default is dry-run; `--force` actually publishes):
- `./tool/publish.sh --all` — dry-run all three
- `./tool/publish.sh --version 1.0.4 --all --force` — bump version, then publish claw + mcp to pub.dev and cli to npm
- `./tool/publish.sh --cli --force --otp 123456` — publish only the npm package non-interactively (npm 2FA)
- `tool/publish_cli.sh` is the npm-only inner script invoked by the orchestrator.

## Architecture

### End-to-end flow
1. A Flutter app integrates `flutter_copilot_claw` and calls `FlutterCopilotBinding.ensureInitialized()` (typically inside `FlutterCopilotBinding.captureLogs(() async { ... })`). In release mode both calls are no-ops, so the same `main()` ships unchanged.
2. In debug/profile, `FlutterCopilotBinding` installs services and registers custom VM service extensions under `ext.flutter.flutter_copilot.*`.
3. An external driver connects to the app's Dart VM service URI. There are two drivers over the same extensions:
   - `flutter_copilot_mcp`: `VmServiceConnector` calls the extensions and wraps responses; `VmServiceContext` registers MCP tools that map almost 1:1 to connector methods and presents them to an AI client.
   - `flutter_copilot_cli` (`fcc`): a commander-based TypeScript CLI for humans and CI; `src/vm/` (client/connector/discover/uri_watcher) owns the WebSocket VM-service connection, `src/commands/` implements the commands, and `src/script/` runs YAML playbooks with per-step retry.

The key split is: `flutter_copilot_claw` runs inside the target Flutter app, while `flutter_copilot_mcp` and `flutter_copilot_cli` run outside the app as bridges.

### Flutter-side binding (`flutter_copilot_claw`)

The main entry point is `packages/flutter_copilot_claw/lib/src/binding/flutter_copilot_binding.dart`.

Important responsibilities of `FlutterCopilotBinding`:
- `ensureInitialized()` is the single init entry. In release mode it transparently delegates to `WidgetsFlutterBinding.ensureInitialized()` and returns — no copilot services, no VM extensions, no overhead. In debug/profile it installs `FlutterCopilotBinding` as the active `WidgetsBinding`.
- `captureLogs(body)` is a thin `runZonedGuarded` wrapper that forwards `print()` and uncaught async errors into the copilot log buffer. Also short-circuits to `body()` in release.
- `addLog(...)` writes a custom log entry; no-op in release.
- The recommended call site is `FlutterCopilotBinding.captureLogs(() async { FlutterCopilotBinding.ensureInitialized(); … runApp(...); });` — one snippet for debug/profile/release, no `kDebugMode` branching.
- Creates the runtime services used by the VM extensions (debug/profile only): widget finding/matching, gesture dispatch, text entry, scrolling, screenshots, navigation, log capture, and rebuild tracking.
- Registers VM service extensions for interaction and inspection (debug/profile only).
- Registers error hooks (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) inside the binding init, so framework errors are captured even without `captureLogs`.
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
4. Mirror the capability as an `fcc` command in `flutter_copilot_cli` if it should be available to humans/CI.
5. Update docs/examples if the user-facing workflow changes.

### Matching and interaction model

Element targeting is centered on widget matching. The tool layer accepts `key`, `text`, `type`, or coordinates; the Flutter side resolves that through widget finder/matcher services and then dispatches gestures or text input. Keys are the most reliable contract, so if a flow is hard to automate, adding `ValueKey<String>` in the example app or a consuming app is usually the intended fix.

### Logging and rebuild diagnostics

`FlutterCopilotBinding.captureLogs(...)` is a thin `runZonedGuarded` wrapper that forwards `print()` output and uncaught async errors into the shared log collector so they surface in `get_logs`. It is independent of `runApp` and composes with other zone-based tooling. Binding initialization also hooks `FlutterError.onError` and `PlatformDispatcher.instance.onError` directly, so framework errors are captured even without `captureLogs`.

Rebuild diagnostics are opt-in through `FlutterCopilotConfiguration(enableGlobalRebuildHook: true)`. On Web, rebuild snapshots remain empty because the custom `BuildOwner` hook is not injected there.

## CI expectations

GitHub Actions (`.github/workflows/ci.yaml`) checks the following:
- `dart tool/version.dart` must leave `packages/flutter_copilot_mcp/lib/src/version.g.dart` unchanged.
- `dart analyze --fatal-infos lib bin` for `flutter_copilot_mcp`.
- `flutter analyze --fatal-infos lib` for `flutter_copilot_claw`.
- formatting checks for `flutter_copilot_mcp`, `flutter_copilot_claw`, and `tool`.

CI does not currently build or test `flutter_copilot_cli`; run `pnpm typecheck && pnpm test` there yourself when touching it.

If you change package versions, use `dart tool/version.dart --set X.Y.Z` so all three manifests and both generated files move together in the same change.

## Known repo-specific notes

- `AGENTS.md` at the repo root mirrors this file for other agents; keep the two in sync when editing either.
- The root workspace exists, but CI still installs/analyzes package directories individually; prefer the per-package commands above when verifying changes.
- `tool/publish.sh` publishes the Dart packages from temporary copied package directories after removing `resolution: workspace` from pubspec files, so publishing logic should be kept compatible with that flow.
- The demo and package examples are useful manual verification targets when changing gesture dispatch, logging, screenshotting, navigation, or rebuild-tracking behavior.
