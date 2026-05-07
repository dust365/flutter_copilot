# Changelog

## 1.0.5

### Breaking

- Short alias renamed from `fcl` to `fcc` (original was a typo). The full `flutter_copilot_cli` name is unchanged. If you globally installed 1.0.3, re-install (`npm uninstall -g flutter_copilot_cli && npm install -g flutter_copilot_cli`) so `fcc` is registered and `fcl` is removed.

### New features

- `screenshot --numbered`: always append `_0/_1/…` to every output file, including when only one view is captured. Prevents single-view → multi-view runs from overwriting the first file on rerun. YAML playbooks: add `numbered: true` to a `screenshot` step for the same effect.
- `watch` now emits structured NDJSON when invoked with `--json`. Each log event becomes one line with stable keys (`ts`, `stream`, `kind`, `text`, `extensionKind`, `extensionData`); rebuild ticks become `{ts, kind:"rebuild", snapshot}`. Pipe to `jq` directly.

### Bug fixes

- `register` help: documented registry path was wrong. Real path is `~/.flutter-copilot/instances/<name>.json` (one file per instance, atomic writes), not `~/.flutter_copilot/instances.json`. Only the help text was inaccurate; the runtime path was always correct.
- YAML `screenshot` step silently dropped extra views when the app had multiple live views. Now all views are written, following the same suffixing rules as the CLI command.
- YAML `assert-element` silently returned `false` when the only matcher was `focused: true`. It now correctly walks the tree for focused nodes, and rejects `x`/`y` coordinate matchers with a clear error (coordinates are a gesture concept, not a static-tree concept).
- `navigate --op pushReplacement` was supported by the runtime and schema but missing from the command help, REPL help, README command reference, and `help-ai` JSON surface. All four are now consistent, and `--route` is correctly documented as required for `push / replace / pushReplacement / popUntil`.

### Tooling (workspace)

- New unified `tool/version.dart` replaces `tool/generate_version.dart` + the (internal-only) `tool/bump_version.sh`. Four modes: default (verify + regenerate), `--set X.Y.Z` (atomic bump across all 3 packages), `--check` (CI drift gate), `--print`. Runs from any cwd — auto-locates the workspace root.
- New publish orchestrator `tool/publish.sh`: `--cli / --mcp / --claw / --all` plus optional `--version X.Y.Z` to bump first, `--force` to actually upload (default is dry-run).
- `tool/publish_cli.sh` hardened: preflight `npm whoami`, remote-duplicate version guard, `--check` drift gate, `--version` shortcut for bump-then-publish.

## 1.0.3

- Initial public release of `flutter_copilot_cli` on npm.
- Commands: `doctor`, `register / unregister / list`, `elements`, `tap / double-tap / long-press / enter-text / scroll-to / drag / swipe / navigate`, `hot-reload`, `logs`, `rebuild`, `screenshot`, `watch`, `repl`, `run <script.yaml>`, `adb-reverse`, `help-ai`.
- URI auto-detection: `--uri` → `-i <instance>` → `$FLUTTER_COPILOT_URI` → nearest `.vm_service_uri`.
- `--watch-uri`: `repl` and `watch` transparently reconnect when `.vm_service_uri` changes (100 ms → 1.6 s exponential backoff).
- YAML playbook runner with per-step `retry: { attempts, delay }` and `stopOnFailure` flag.
- `--json` global flag and `help-ai` JSON surface for scripting / LLM consumption.
