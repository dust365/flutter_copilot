---
name: flutter-copilot
description: 连接 Flutter Copilot MCP，支持通过 DTD 发现多台设备、冷启动、截图、交互和热重载
---

# Flutter Copilot MCP 连接 Skill

通过 Flutter Copilot MCP 发现、启动并操作一台或多台正在 debug 运行的 Flutter 应用。连接状态在 MCP 进程里，不读 `.vm_service_uri`。

## When to Use

- 需要查看或操作一台正在运行的 Flutter 应用
- 同一个对话里要同时操作多台设备
- 应用还没启动，需要 MCP 自己拉起
- 应用从 IDE 重新 Run 之后要继续操作
- 需要热重载后验证 UI

## Instructions

### 1. 接上已经在跑的 App

1. 调用 `list_dtds`。
2. 从结果里选本机的 `ws://` DTD 地址，调用 `connect_dtd`。IDE 启动的 App 通常在 IDE 那个长期 DTD 上；终端里的 `flutter run` 各自带一个 DTD。
3. 调用 `list_apps`。只有一台时，后面的工具可以不传 `app`。有多台时，每次操作都传 `app`（id、设备 id 或 URI）。

`connect` 只在已经拿到 DDS 的 `ws://` 地址、周围没有 DTD 时使用。它是往表里追加一台，不会拆掉别的会话。

### 2. 一台都没跑

1. 调用 `list_devices`。
2. 对每台设备调用一次 `launch_app`，传入 `deviceId`、Flutter 工程 `directory`，以及一个稳定的 `name`。不同系统可以并行调用。同一系统（两台安卓、两台 iOS，或两个相同的桌面系统）要等上一次 `launch_app` 返回后再调下一次。服务端也会按系统排队，避免两台设备同时改同一个安装包；调用方自己排队，是为了不让还在排队的调用被客户端超时掐掉。
3. 返回时该设备已经在表里，直接用 `name` 作为 `app` 操作。

`stop_app` 只结束电脑上的 `flutter run`。手机上的 App 还在前台。

### 3. 重启之后

- 从 IDE 重新 Run：不要再连接。原来的 `app` 名字会接到新的 DDS。直接截图或点击。
- 热重启之后同样直接操作。
- 在终端里重新 `flutter run`：旧 DTD 消失。工具报错里会带上当前 DTD 列表，再 `connect_dtd` 一次。

### 4. 常用操作

| 操作 | MCP 工具 | 说明 |
|------|----------|------|
| 列出 DTD | `list_dtds` | 发现本机有哪些 DTD |
| 连接 DTD | `connect_dtd` | 接上该 DTD 上所有已初始化 Copilot 的 App |
| 列出会话 | `list_apps` | 拿到 `app` 参数 |
| 列出设备 | `list_devices` | 冷启动前选择 deviceId |
| 启动 | `launch_app` | 拉起一台并连上。同一系统排队，不同系统可并行 |
| 停止 | `stop_app` | 结束对应的 flutter run |
| 截图 | `take_screenshots` | 多台时传 `app` |
| 点击 | `tap` | 优先用 key |
| 滚动到 | `scroll_to` | 滚动到文本或 key |
| 输入文字 | `enter_text` | 写入输入框 |
| 获取元素 | `get_interactive_elements` | 列出可交互元素 |
| 热重载 | `hot_reload` | 代码修改后热重载，保留状态 |
| 热重启 | `hot_restart` | 热重载看不到改动时，重新跑 main() |
| 导航 | `navigate` | push/pop/replace |
| 应用内日志 | `get_logs` | App 里截获的日志 |
| 启动日志 | `get_app_logs` | launch_app 拉起的 flutter run 输出 |

## Key Files

- `packages/flutter_copilot_mcp` — 连接表、DTD 订阅和 `launch_app` 都在这个进程里
- `scripts/flutter_run.sh` 和 `.vm_service_uri` — 仍给单次 `fcc` 命令用，MCP 不读这个文件
