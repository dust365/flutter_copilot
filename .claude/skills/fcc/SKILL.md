---
name: fcc
description: 使用 flutter_copilot_cli (fcc) 命令行工具连接并驱动一个运行中的 Flutter debug 应用：自动发现 URI、截图、元素检查、手势交互、日志、热重载、YAML 脚本回放
---

# Flutter Copilot CLI (fcc) Skill

通过 `fcc` 命令行直接驱动运行中的 Flutter debug 应用，无需 MCP 中间层。

当前 `fcc` 是单实例目标模型：每次命令只解析一个 VM Service URI，不再使用 registry / 多实例命名实例。

## When to Use

- 需要从终端直接操控 Flutter 应用：点击、输入、滑动、截图等
- 需要检查 Flutter Copilot 扩展是否连通：`fcc doctor`
- 需要读取当前页面可交互元素树：`fcc --json get-interactive-elements`
- 需要读取应用日志或 rebuild 热点：`fcc get-logs` / `fcc get-rebuild-snapshot`
- 需要触发热重载：`fcc hot-reload`
- 需要运行 YAML 脚本做自动化冒烟测试：`fcc run`

## Prerequisites

确认 `fcc` 可用：

```bash
fcc --version
fcc help-ai
```

本项目通常通过 `scripts/flutter_run.sh` 启动 Flutter，并自动写入项目根目录的 `.vm_service_uri`：

```bash
./scripts/flutter_run.sh -d <device-id>
```

如果 `.vm_service_uri` 不存在或过期，先重新启动 Flutter debug 会话。

## Target Resolution

目标 URI 解析优先级从高到低：

1. `--uri ws://...`：本次命令显式指定
2. `FLUTTER_COPILOT_URI`：环境变量
3. `.vm_service_uri`：从当前目录或父目录查找最近的 URI 文件

常用检查：

```bash
test -s .vm_service_uri && cat .vm_service_uri
fcc doctor
```

也可以显式指定：

```bash
fcc --uri "$(cat .vm_service_uri)" doctor
```

## Connection Commands

`connect` 会校验 URI 并写入当前工作目录的 `.vm_service_uri`。

以下写法均应可用：

```bash
fcc connect --uri ws://127.0.0.1:8181/abc/ws
fcc connect --uri=ws://127.0.0.1:8181/abc/ws
fcc --uri ws://127.0.0.1:8181/abc/ws connect
```

断开当前项目连接文件：

```bash
fcc disconnect
```

注意：`disconnect` 只删除最近的 `.vm_service_uri` 文件；CLI 没有常驻 socket。

## Commands Reference

### 连接与健康检查

| 命令                      | 说明                                                        |
| ------------------------- | ----------------------------------------------------------- |
| `fcc doctor`              | 检查解析到的目标是否可连接，并确认 Flutter Copilot 扩展可用 |
| `fcc connect --uri <uri>` | 校验 URI 并写入 `.vm_service_uri`                           |
| `fcc disconnect`          | 删除最近的 `.vm_service_uri`                                |
| `fcc help-ai`             | 输出机器可读命令表面，优先以它为准                          |

### 查询与诊断

| 命令                                               | 说明                     |
| -------------------------------------------------- | ------------------------ |
| `fcc --json get-interactive-elements`              | 输出当前屏幕可交互元素树 |
| `fcc get-logs --limit 50`                          | 读取应用日志缓冲区       |
| `fcc get-rebuild-snapshot --top-limit 10`          | 读取 rebuild 热点快照    |
| `fcc take-screenshots -o /tmp/shot.png --numbered` | 截图保存为 PNG           |

### 手势与输入

所有手势命令共享 matcher：`--key`、`--text`、`--type`、`--x/--y`、`--focused`。

| 命令             | 说明       | 示例                                                 |
| ---------------- | ---------- | ---------------------------------------------------- |
| `fcc tap`        | 点击       | `fcc tap --text "提交"`                              |
| `fcc double-tap` | 双击       | `fcc double-tap --key LikeButton`                    |
| `fcc long-press` | 长按       | `fcc long-press --key ItemCard --duration 800`       |
| `fcc enter-text` | 输入文本   | `fcc enter-text --key UsernameField --input demo`    |
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
```

### 实时监听

```bash
fcc --json watch --logs --rebuilds --interval 500
fcc --watch-uri repl
```

`--watch-uri` 仅用于 `watch` / `repl`，用于 `.vm_service_uri` 变化时自动重连。

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
5. `--focused`：当前焦点元素

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

- **`No VM Service URI`**：确认 `.vm_service_uri` 存在且非空，或使用 `--uri` 显式指定。
- **`ECONNREFUSED`**：URI 对应的 Flutter debug 会话已退出，重新启动 App 获取新 URI。
- **`EPERM 127.0.0.1`**：当前执行环境不允许连接本机 VM Service，需要在允许本机 socket 的环境执行。
- **`doctor` 成功但元素为空**：确认 App 侧已集成并注册 `flutter_copilot_claw` 扩展。
- **`enter-text` 无效**：确认目标是 TextField，并且 matcher 命中了正确输入框。
- **`get-rebuild-snapshot` 为空**：Flutter 侧需要启用 `FlutterCopilotConfiguration(enableGlobalRebuildHook: true)`；Web 平台不支持该 hook。

始终优先以当前环境的 `fcc help-ai` 输出为准。
