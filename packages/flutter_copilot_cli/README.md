# flutter_copilot_cli

[![npm version](https://img.shields.io/npm/v/flutter_copilot_cli)](https://www.npmjs.com/package/flutter_copilot_cli)
[![npm downloads](https://img.shields.io/npm/dm/flutter_copilot_cli)](https://www.npmjs.com/package/flutter_copilot_cli)

> npm package: <https://www.npmjs.com/package/flutter_copilot_cli>

TypeScript CLI that drives a running Flutter app via the
`ext.flutter.flutter_copilot.*` VM service extensions registered by
[`flutter_copilot_claw`](../flutter_copilot_claw).

Think of it as an alternative to `flutter_copilot_mcp` that is designed for
**humans at a terminal** and **CI pipelines**, not just for LLM tool-use.

## Command reference

All commands accept the global flags `-i <instance>` / `--uri <ws://...>` for
target resolution, plus `--json` to emit machine-readable output. Run
`fcc <command> --help` for per-command details, or `fcc help-ai` for the full
machine-readable surface.

### Target & session

| Command                  | Description                                                            |
| ------------------------ | ---------------------------------------------------------------------- |
| `doctor`                 | Probe the resolved VM Service URI and the Copilot extensions.          |
| `register <name> <uri>`  | Register a VM Service URI under a short name.                          |
| `unregister <name>`      | Remove a registered instance.                                          |
| `list`                   | List all registered instances.                                         |
| `repl`                   | Open an interactive shell; supports `--watch-uri` auto-reconnect.      |
| `adb-reverse <port>`     | `adb reverse tcp:<port> tcp:<port>`; `--remove` to undo.               |

### Inspect & capture

| Command        | Description                                                                   |
| -------------- | ----------------------------------------------------------------------------- |
| `elements`     | List the interactive element tree on the current screen.                      |
| `logs`         | Dump logs captured since the app started (requires `captureLogs` wrapper).    |
| `rebuild`      | Fetch the latest rebuild snapshot / hot-spot analysis.                        |
| `screenshot`   | Take a screenshot of each live view (`-o <path>` to save; `--numbered` to always suffix `_N`). |
| `watch`        | Stream logs / rebuild events; `--logs --rebuilds --interval <ms>`.            |

### Gestures & input

| Command       | Description                                                                    |
| ------------- | ------------------------------------------------------------------------------ |
| `tap`         | Tap by `--key` / `--text` / `--type` / `--x --y` / `--focused`.                |
| `double-tap`  | Double-tap using the same matchers as `tap`.                                   |
| `long-press`  | Long-press using the same matchers; `--duration <ms>` is optional.             |
| `enter-text`  | Focus a field and enter text. `--input <string>` is required.                  |
| `scroll-to`   | Scroll until a matcher becomes visible.                                        |
| `drag`        | Drag by `--dx --dy` from a matcher, or `--from-x/--from-y/--to-x/--to-y`.      |
| `swipe`       | Swipe `--direction <up/down/left/right>` with `--distance`.                    |
| `navigate`    | Route control: `--op push/pop/replace/pushReplacement/popUntil` with `--route` / `--args`.     |

### App lifecycle & automation

| Command         | Description                                                                  |
| --------------- | ---------------------------------------------------------------------------- |
| `hot-reload`    | Trigger a Flutter hot reload.                                                |
| `run <script>`  | Execute a YAML playbook; each step may carry `retry: { attempts, delay }`.   |
| `help-ai`       | Print the entire command surface + script schema as JSON, for AI agents.     |

## Install

Requires Node.js **>= 18**.

### From npm (recommended)

```bash
# npm
npm install -g flutter_copilot_cli

# pnpm
pnpm add -g flutter_copilot_cli

# yarn
yarn global add flutter_copilot_cli
```

Verify the install:

```bash
fcc --version          # 1.0.3
fcc --help
flutter_copilot_cli --help    # same binary, full name
```

The package exposes two bin names that point at the same binary:

- `flutter_copilot_cli` — full name, matches the package identifier
- `fcc` — short alias used throughout the docs and examples

Help output reflects whichever name you invoke.

### From source (for contributors)

```bash
git clone https://github.com/dust365/flutter_copilot.git
cd flutter_copilot/packages/flutter_copilot_cli
pnpm install
pnpm build
pnpm link --global    # adds both `flutter_copilot_cli` and `fcc` to your PATH
```

## Upgrade

```bash
# npm
npm update -g flutter_copilot_cli
# or pin a specific version
npm install -g flutter_copilot_cli@latest

# pnpm
pnpm update -g flutter_copilot_cli
# or
pnpm add -g flutter_copilot_cli@latest

# yarn
yarn global upgrade flutter_copilot_cli
```

Check the installed version against the latest on npm:

```bash
fcc --version
npm view flutter_copilot_cli version
```

## Uninstall

```bash
# npm
npm uninstall -g flutter_copilot_cli

# pnpm
pnpm remove -g flutter_copilot_cli

# yarn
yarn global remove flutter_copilot_cli
```

If you installed from source via `pnpm link --global`, unlink it instead:

```bash
cd packages/flutter_copilot_cli
pnpm unlink --global
```

## Usage

Start an app with `flutter_copilot_claw` initialised:

```dart
void main() {
  FlutterCopilotBinding.captureLogs(() {
    FlutterCopilotBinding.ensureInitialized();
    runApp(const MyApp());
  });
}
```

### Target resolution — no `--uri` needed

The CLI picks a VM Service URI from the first source that matches:

1. `--uri <ws://...>` — explicit
2. `-i <name>` — from the instance registry
3. `FLUTTER_COPILOT_URI` env var
4. `.vm_service_uri` in the current directory or any ancestor

Use `--no-auto-uri` to disable #3/#4 if needed.

#### Recommended: `scripts/flutter_run.sh`

The repo ships a helper that wraps `flutter run` and writes the detected URI to
`<repo_root>/.vm_service_uri`:

```bash
./scripts/flutter_run.sh -d macos          # starts the app; writes .vm_service_uri
fcc doctor                                 # auto-picks the URI from that file
fcc tap --text Counter
```

#### Alternative: manual registry

```bash
fcc register demo ws://127.0.0.1:8181/abc/ws
fcc -i demo doctor
fcc -i demo elements
fcc -i demo tap --text "Increment"
fcc -i demo screenshot -o /tmp/shot.png
```

### Real-time stream

```bash
fcc -i demo watch --logs --rebuilds --interval 500
```

Add `--watch-uri` to survive `flutter run` restarts — the CLI tails
`.vm_service_uri` and transparently reconnects (with 100ms→1.6s backoff):

```bash
fcc --watch-uri watch --rebuilds
# in another terminal: ctrl-c flutter, restart it → CLI auto-reconnects
```

The same flag works for `repl` too. It's a no-op for one-shot commands and
requires URI auto-detection (it refuses when `--uri` / `-i` was used).

### Interactive REPL

```bash
fcc -i demo repl
fc[demo]> tap text="Increment"
fc[demo]> enter-text key=UsernameField input="demo user"
fc[demo]> screenshot output=/tmp/s.png
fc[demo]> reload
```

### YAML playbook

```yaml
# smoke.yaml
name: smoke-login
stopOnFailure: true
steps:
  - action: tap
    key: LoginBtn
  - action: enter-text
    key: UsernameField
    input: demo
  - action: wait
    ms: 300
  - action: screenshot
    output: /tmp/after-login.png
  - action: assert-element
    text: Welcome
```

```bash
fcc -i demo run smoke.yaml
```

Each step may carry a `retry: { attempts, delay }` block.

### Android: bridge VM Service over `adb reverse`

When the app runs on an Android device but the VM Service is bound to the host's
loopback, expose it to the device with:

```bash
fcc adb-reverse 8181
# ... later
fcc adb-reverse 8181 --remove
```

Fails fast if `adb` is not on `PATH`.

### JSON output for scripting

```bash
fcc --json -i demo elements | jq '.elements'
```

### Help for AI agents

```bash
fcc help-ai
```

Outputs the full command surface and script schema as JSON.

## Roadmap (not in v1)

- `record-video` — needs a screencast extension on the `flutter_copilot_claw` side.
- `pinch-zoom`, `press-back-button` — also need claw additions.
- Process / DDS auto-discovery of VM Service URI.
- Embedded MCP server subcommand.
