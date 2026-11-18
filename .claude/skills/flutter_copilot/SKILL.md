---
name: flutter-copilot
description: 连接 Flutter Copilot MCP，支持通过 DTD 发现多台设备、冷启动、截图、交互和热重载
---

# Flutter Copilot MCP 连接 Skill

通过 Flutter Copilot MCP 发现、启动并操作一台或多台正在 debug 运行的 Flutter 应用。

## When to Use

- 需要查看或操作一台正在运行的 Flutter 应用
- 同一个对话里要同时操作多台设备
- 应用还没启动，需要 MCP 自己拉起
- 应用从 IDE 重新 Run 之后要继续操作
- 需要热重载后验证 UI

## Instructions

### 1. 发现或启动 App

1. 调用 `list_apps(directory)`，其中 `directory` 是 Flutter 工程目录。本仓库用 `example` 的绝对路径。DTD 会自动发现已有 debug 会话。
2. 没有合适的会话时调用 `ensure_apps(directory)`。如果返回 `selection_required`，请用户从候选中选一台或多台，再传入 `deviceIds` 或 `appIds`。
3. 有 `operationId` 时轮询 `operation_status`，直到 `state=completed`。启动结果按设备返回；一台失败时可继续使用其他已连接的设备。
4. 截图、点击等操作传 `app` 为所选会话 ID。重新运行后若原 ID 不可用，重新列出会话并确认目标。只有自动发现不可用时才用 `connect(uri)` 显式连接。

### 2. 会话生命周期

MCP 和 `fcc` 共用会话，退出任一客户端不会停止 App。`disconnect` 只断开连接；`stop_app` 关闭本工具启动的 App，`detach_app` 结束其调试会话但保留 App。外部 `flutter run` 或 IDE 会话需由原启动方停止。

### 3. 常用操作

| 操作 | MCP 工具 | 说明 |
|------|----------|------|
| 列出会话 | `list_apps` | 拿到 `app` 参数 |
| 列出设备 | `list_devices` | 冷启动前选择 deviceId |
| 启动 | `ensure_apps` | 复用已有会话或启动所选设备 |
| 停止 | `stop_app` | 退出本工具启动的 App |
| 截图 | `take_screenshots` | 多台时传 `app` |
| 点击 | `tap` | 优先用 key |
| 滚动到 | `scroll_to` | 滚动到文本或 key |
| 输入文字 | `enter_text` | 写入输入框 |
| 获取元素 | `get_interactive_elements` | 列出可交互元素 |
| 热重载 | `hot_reload` | 代码修改后热重载，保留状态 |
| 热重启 | `hot_restart` | 热重载看不到改动时，重新跑 main() |
| 导航 | `navigate` | push/pop/replace |
| 应用内日志 | `get_logs` | App 里截获的日志 |
| 启动日志 | `get_app_logs` | 本工具启动的 flutter run 输出 |

## Key Files

- `packages/flutter_copilot_mcp/lib/src/session` — 共享会话、发现和启动管理
