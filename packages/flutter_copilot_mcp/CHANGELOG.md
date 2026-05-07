# Changelog

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
