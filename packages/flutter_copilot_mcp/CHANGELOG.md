# Changelog

## Unreleased

### Bug fixes

- `disconnect`, `stop_app`, `detach_app`, and `disconnect_dtd` now also drop this process's own VM service connections. Before, an App could stay reachable here after it was disconnected.
- A disconnected App or DTD is not rediscovered by the next discovery pass. An explicit `connect` or `connect_dtd` lifts the suppression.
- The session backend starts with `--packages` pinned to the entry script's `package_config.json`, so it no longer depends on the working directory.
- `enter_text` no longer requires `key`. It accepts `key`, `text`, or `type`.
- The session state file, which holds the backend's bearer token, is restricted to the owner before the token is written. Previously it was readable by other local users until `chmod` ran. A failed `chmod` now stops the backend from starting.
- The MCP process keeps at most 50 operation owners, matching the backend's retention. Before, the map grew for the whole session.
- `detach_app` no longer reports an error when `flutter run` takes more than 5 seconds to exit after a successful detach. The run is released instead of staying marked as running.

## 2.0.0

### Breaking

- Connection is DTD-based. `list_apps` discovers running debug Apps for a project directory. `ensure_apps` reuses a live session or cold-starts the selected devices. URI files are no longer the connection path.
- One local session backend is shared with `fcc`. Session IDs match across both clients, and an App keeps running when either client exits.
- `stop_app` and `detach_app` only manage Apps this backend launched. An IDE or external `flutter run` session cannot be stopped here.

### New tools

- `list_devices`, `list_dtds`, `connect_dtd`, `disconnect_dtd`, `operation_status`, `get_app_logs`, and `hot_restart`.
- When several Apps are connected, pass `app`. A launch returns an `operationId`; poll `operation_status` until it completes.

## 1.0.6

Shared release with `flutter_copilot_claw`. The MCP server itself is unchanged; this version bump ships to keep `flutter_copilot_claw` and `flutter_copilot_mcp` aligned (they share a single version line via `tool/version.dart`).

### Breaking changes (flutter_copilot_claw)

- `FlutterCopilotBinding.ensureInitialized()` now returns `void` instead of `FlutterCopilotBinding`. Callers that ignored the return value (the common pattern) need no change.
- `FlutterCopilotBinding.runAppWithConfig(...)` has been removed. Use the new `captureLogs` + `runApp` pattern (see `flutter_copilot_claw` 1.0.6 release notes).

### New API (flutter_copilot_claw)

- `FlutterCopilotBinding.captureLogs<R>(R Function() body, {void Function(Object, StackTrace)? onError})` — independent `runZonedGuarded` wrapper that forwards `print()` and uncaught async errors into `get_logs`.
- `ensureInitialized()`, `captureLogs(...)`, and `addLog(...)` all short-circuit to no-ops in release builds, so the same `main()` is safe to ship without `kDebugMode` branching.

### Migration

```dart
// Before
void main() => FlutterCopilotBinding.runAppWithConfig(const MyApp());

// After — single path, release-safe
void main() {
  FlutterCopilotBinding.captureLogs(() async {
    FlutterCopilotBinding.ensureInitialized();
    runApp(const MyApp());
  });
}
```

## 1.0.5

### Bug fixes (flutter_copilot_claw)

- `flutter_copilot.longPress`: fix `TypeError: 'String' is not a subtype of 'num?'` when a caller supplies `duration`. VM service extension params arrive as `Map<String, String>`; the previous `as num?` cast always threw for non-null values. Now uses the existing `_parseDouble` helper, matching `drag`/`swipe`/`distance` handling.
- `flutter_copilot.navigate`: fix `arguments` being silently dropped. The nested map arrives as a JSON string via the VM service extension transport, so the `params['arguments'] is Map<String, dynamic>` check was always false. Now decodes the JSON string via a new `_parseArguments` helper that accepts both direct maps and JSON-encoded strings.

### Tooling (workspace)

- Add `flutter_copilot_cli` (npm, `fcc`) as a third published package alongside `flutter_copilot_claw` and `flutter_copilot_mcp`. All three share one version line managed by the new unified `tool/version.dart` (which replaces the old `tool/generate_version.dart` + `tool/bump_version.sh`).
- New publish orchestrator `tool/publish.sh` supports single-package or one-shot three-package releases via `--cli / --mcp / --claw / --all` plus `--version X.Y.Z` to bump first.

### Tests (flutter_copilot_mcp)

- Add integration regression tests for `VmServiceConnector.longPress` / `navigate` that assert `duration` and `arguments` cross the JSON-RPC wire, and are omitted when the caller passes null. Uses a mock WebSocket VM service so the tests run without a real Flutter app.

## 1.0.3

- Add demo preview assets and updated release documentation for the published packages.
- Showcase the demo flow with GIF preview and video links in the repository and package docs.
- MCP tools: connect, disconnect, get_interactive_elements, tap, enter_text, scroll_to, get_logs, get_rebuild_snapshot, take_screenshots, hot_reload, flutter_copilot_drag, swipe, long_press, double_tap, navigate.

## 1.0.2

- Update pub.dev metadata, topics, and package descriptions for discoverability.
- MCP tools: connect, disconnect, get_interactive_elements, tap, enter_text, scroll_to, get_logs, get_rebuild_snapshot, take_screenshots, hot_reload, flutter_copilot_drag, swipe, long_press, double_tap, navigate.

## 1.0.0

- Initial stable release.
- MCP server for Flutter app interaction via VM service.
- Tools: connect, tap, enter_text, scroll_to, drag, swipe, long_press, double_tap.
- Tools: get_interactive_elements, take_screenshots, get_logs, hot_reload.
- Tools: get_rebuild_snapshot, navigate.
- VM service connector with auto-reconnect support.
