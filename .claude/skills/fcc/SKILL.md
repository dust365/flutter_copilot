---
name: fcc
description: 使用 flutter_copilot_cli (fcc) 命令行工具连接并驱动一个运行中的 Flutter debug 应用：自动发现 URI、截图、元素检查、手势交互、日志、热重载、YAML 脚本回放
---

# Flutter Copilot CLI (fcc) Skill

通过 `fcc` 命令行直接驱动运行中的 Flutter debug 应用，无需 MCP 中间层。

MCP 与 `fcc` 共用会话，可启动多台设备；每条 UI 操作命令只作用于一个 App。

## When to Use

- 需要从终端直接操控 Flutter 应用：点击、输入、滑动、截图等
- 需要检查 Flutter Copilot 扩展是否连通：`fcc doctor`
- 需要读取当前页面可交互元素树：`fcc --json get-interactive-elements`
- 需要读取应用日志或 rebuild 热点：`fcc get-logs` / `fcc get-rebuild-snapshot`
- 需要触发热重载：`fcc hot-reload`
- 热重载后界面没变化：`fcc hot-restart`
- 需要运行 YAML 脚本做自动化冒烟测试：`fcc run`

## Prerequisites

确认 `fcc` 可用：

```bash
fcc --version
fcc help-ai
```

### 启动和选择目标

在 Flutter 工程目录运行 `fcc apps`，它会通过 DTD 发现已运行的 debug App。也可以用 `fcc --project <目录>` 指定工程；本仓库从根目录调用时传 `--project example`。

- 没有 App 时运行 `fcc up`。一台可用真机时直接启动；有多个候选时由用户选择。终端可输入 `1,2`，脚本可重复传 `-d <device-id>`。
- 使用 `--json` 时，`selection_required` 的候选在 stderr，先让用户选择再重试。会话列表和操作结果在 stdout。
- 多个 App 可用时，操作命令用 `--app <id>` 指定目标。断线后先重新列出会话；只有能确认是同一个 App 时才自动重连。
- `--uri` 可显式直连；未指定 `--app` 时也可用环境变量 `FLUTTER_COPILOT_URI`。要把显式地址加入共享会话，使用 `fcc connect --uri <uri>`。

### 常用连接命令

| 命令 | 说明 |
| --- | --- |
| `fcc doctor` | 检查目标和 Copilot 扩展 |
| `fcc up --no-wait` / `fcc status <operation-id>` | 后台启动并查询每台设备的结果 |
| `fcc --app <id> disconnect` | 断开连接，保留 App |
| `fcc --app <id> stop` / `detach` | 仅管理 Copilot 启动的会话；分别退出 App、保留 App |
| `fcc help-ai` | 查看机器可读命令说明 |

### 查询与诊断

| 命令                                               | 说明                     |
| -------------------------------------------------- | ------------------------ |
| `fcc --json get-interactive-elements`              | 输出当前屏幕可交互元素树 |
| `fcc get-logs --limit 50`                          | 读取应用日志缓冲区       |
| `fcc get-rebuild-snapshot --top-limit 10`          | 读取 rebuild 热点快照    |
| `fcc take-screenshots -o /tmp/shot.png --numbered` | 截图保存为 PNG           |

### 手势与输入

所有手势命令共享 matcher：`--key`、`--text`、`--type`、`--x/--y`。

| 命令             | 说明       | 示例                                                 |
| ---------------- | ---------- | ---------------------------------------------------- |
| `fcc tap`        | 点击       | `fcc tap --text "提交"`                              |
| `fcc double-tap` | 双击       | `fcc double-tap --key LikeButton`                    |
| `fcc long-press` | 长按       | `fcc long-press --key ItemCard --duration 800`       |
| `fcc enter-text` | 输入文本   | `fcc enter-text --key <TextFieldKey> --input demo`   |
| `fcc scroll-to`  | 滚动至可见 | `fcc scroll-to --text "提交"`                        |
| `fcc drag`       | 拖拽       | `fcc drag --key Slider --delta-x 120`                |
| `fcc swipe`      | 滑动       | `fcc swipe --key Feed --direction up --distance 500` |
| `fcc navigate`   | 路由导航   | `fcc navigate --action push --route /settings`       |

坐标点击示例：

```bash
fcc tap --x 200 --y 205
```

### 生命周期

```bash
fcc hot-reload
fcc hot-restart
```

### 实时监听

```bash
fcc --json watch --logs --rebuilds --interval 500
fcc repl
```

`watch` 和 `repl` 只在能识别同一会话时重连。

### YAML 脚本回放

```bash
fcc --json run smoke.yaml
```

示例：

```yaml
name: smoke
stopOnFailure: true
steps:
  - action: tap
    text: "订单记录"
  - action: wait
    ms: 300
  - action: take-screenshots
    output: /tmp/order-record.png
  - action: assert-element
    text: "订单记录"
    exists: true
```

## Widget Matcher

定位优先级建议：

1. `--key <k>`：`ValueKey<String>`，最稳定
2. `--text <t>`：可见文本
3. `--type <n>`：Widget 类型名
4. `--x <n> --y <n>`：逻辑像素坐标

目标元素难以定位时，优先在 Flutter 代码里添加稳定 `ValueKey<String>`。

## Practical Workflow

1. 先确认连接：

   ```bash
   fcc doctor
   ```

2. 读取元素树：

   ```bash
   fcc --json get-interactive-elements
   ```

3. 截图：

   ```bash
   fcc take-screenshots -o /tmp/youfi.png --numbered
   ```

4. 交互后再次截图或读取元素：

   ```bash
   fcc tap --text "详情"
   fcc take-screenshots -o /tmp/youfi-detail.png --numbered
   ```

## Troubleshooting

- **`app_not_found`**：用 `fcc apps` 检查项目和调试会话，或用 `fcc up` 启动。
- **`ECONNREFUSED`**：URI 对应的 Flutter debug 会话已退出，重新启动 App 获取新 URI。
- **`EPERM 127.0.0.1`**：当前执行环境不允许连接本机 VM Service，需要在允许本机 socket 的环境执行。
- **`doctor` 成功但元素为空**：确认 App 侧已集成并注册 `flutter_copilot_claw` 扩展。
- **`enter-text` 无效**：确认目标是 TextField，并且 matcher 命中了正确输入框。
- **`get-rebuild-snapshot` 为空**：Flutter 侧需要启用 `FlutterCopilotConfiguration(enableGlobalRebuildHook: true)`；Web 平台不支持该 hook。

始终优先以当前环境的 `fcc help-ai` 输出为准。
