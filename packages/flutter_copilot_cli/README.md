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

Use `--project <directory>` to select a Flutter project and `--app <id>` to select a session when more than one is running. Run `fcc <command> --help` for details or `fcc help-ai` for the machine-readable command surface.

### Target & session

| Command               | Description                                                       |
| --------------------- | ----------------------------------------------------------------- |
| `apps` / `devices` | Discover Apps through DTD or list available devices. |
| `up [-d <id>]` | Reuse or launch. Repeat `-d` for multiple devices. |
| `status <operation-id>` | Check a launch started with `up --no-wait`. |
| `connect --uri <uri>` | Attach an explicit address to the project session backend. |
| `disconnect` | Disconnect the selected App and leave it running. |
| `stop` / `detach` | Stop an owned App or leave it running without Flutter tooling. |
| `doctor`              | Probe the current VM Service URI and the Copilot extensions.      |
| `repl`                | Open an interactive shell for the selected App. |

### Inspect & capture

| Command                    | Description                                                                 |
| -------------------------- | --------------------------------------------------------------------------- |
| `get-interactive-elements` | List the interactive element tree on the current screen.                    |
| `get-logs`                 | Dump logs captured since the app started (requires `captureLogs` wrapper).  |
| `get-rebuild-snapshot`     | Fetch the latest rebuild snapshot / hot-spot analysis.                      |
| `take-screenshots`         | Take screenshots (`-o <path>` to save; `--numbered` to always suffix `_N`). |
| `watch`                    | Stream logs / rebuild events; `--logs --rebuilds --interval <ms>`.          |

### Gestures & input

| Command      | Description                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `tap`        | Tap by `--key` / `--text` / `--type` / `--x --y` / `--focused`.                                     |
| `double-tap` | Double-tap using the same matchers as `tap`.                                                        |
| `long-press` | Long-press using the same matchers; `--duration <ms>` is optional.                                  |
| `enter-text` | Focus a field and enter text. `--input <string>` is required.                                       |
| `scroll-to`  | Scroll until a matcher becomes visible.                                                             |
| `drag`       | Drag by `--delta-x --delta-y` from a matcher, or `--from-x/--from-y/--to-x/--to-y`.                 |
| `swipe`      | Swipe `--direction <up/down/left/right>` with `--distance`.                                         |
| `navigate`   | Route control: `--action push/pop/replace/pushReplacement/popUntil` with `--route` / `--arguments`. |

### App lifecycle & automation

| Command        | Description                                                                |
| -------------- | -------------------------------------------------------------------------- |
| `hot-reload`   | Trigger a Flutter hot reload.                                              |
| `hot-restart`  | Trigger a Flutter hot restart. Re-runs `main()` and drops app state.      |
| `run <script>` | Execute a YAML playbook; each step may carry `retry: { attempts, delay }`. |
| `help-ai`      | Print the entire command surface + script schema as JSON, for AI agents.   |

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

`fcc apps` discovers running debug Apps through DTD. If no suitable App is running, `fcc up` launches one. Choose one or several listed devices in an interactive terminal, or repeat `-d <device-id>` in scripts. With `--json`, handle `selection_required` on stderr and pass the selected IDs. Successful Apps stay connected if another device fails or the client exits.

Use `--uri <uri>` to bypass discovery, or `FLUTTER_COPILOT_URI` as a default when `--app` is absent.

```bash
fcc --project example up
fcc --project example apps
fcc --project example --app <id> doctor
```

#### Manual connection

```bash
fcc connect --uri ws://127.0.0.1:8181/abc/ws
fcc doctor
fcc get-interactive-elements
fcc tap --text "点击"
fcc take-screenshots -o /tmp/shot.png
fcc disconnect
```

### Real-time stream

```bash
fcc watch --logs --rebuilds --interval 500
```

`watch` and `repl` reconnect when discovery can identify the same session. If an external App restarts without a verified device identity, use `fcc apps` to choose its new session.

### Interactive REPL

```bash
fcc repl
fc[app-id]> tap text="点击"
fc[app-id]> enter-text focused input="demo user"
fc[app-id]> take-screenshots output=/tmp/s.png
fc[app-id]> hot-reload
```

### YAML playbook

```yaml
# smoke.yaml
name: smoke-home
stopOnFailure: true
steps:
  - action: assert-element
    text: Flutter Copilot 功能演示
  - action: tap
    text: 点击
  - action: wait
    ms: 300
  - action: take-screenshots
    output: /tmp/fcc-smoke.png
  - action: assert-element
    text: 点击
```

```bash
fcc run smoke.yaml
```

Each step may carry a `retry: { attempts, delay }` block.

### JSON output for scripting

```bash
fcc --json get-interactive-elements | jq '.elements'
```

### Help for AI agents

```bash
fcc help-ai
```

Outputs the full command surface and script schema as JSON.
