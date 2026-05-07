---
name: fcc
description: 使用 flutter_copilot_cli (fcc) 命令行工具连接并驱动运行中的 Flutter 应用：自动发现 URI、手势交互、截图、日志、热重载、YAML 脚本回放
---

# Flutter Copilot CLI (fcc) Skill

通过 `fcc` 命令行直接驱动运行中的 debug Flutter 应用，无需 MCP 中间层。

## When to Use

- 需要从终端直接操控 Flutter 应用（点击、输入、滑动、截图等）
- 需要检查 Flutter 应用连通性（`fcc doctor`）
- 需要实时监听应用日志或 rebuild 事件（`fcc watch`）
- 需要运行 YAML 脚本做自动化冒烟测试（`fcc run`）
- 需要注册/管理多个 Flutter 应用实例
- 需要在 Android 真机上建立 adb reverse 端口映射

## Prerequisites

确保 `fcc` 已构建并可用：

```bash
cd packages/flutter_copilot_cli && pnpm install && pnpm build
```

可通过 `npx fcc --version` 或全局 link 后直接使用 `fcc`。

## Connection Flow

### URI 自动发现（优先级从高到低）

1. `--uri ws://...` — 显式指定
2. `-i <name>` — 从注册表查找已命名实例
3. `$FLUTTER_COPILOT_URI` — 环境变量
4. `.vm_service_uri` — 从 cwd 向上遍历查找该文件

### 典型连接步骤

```bash
# 1. 启动 Flutter 应用（会写入 .vm_service_uri）
./scripts/flutter_run.sh -d macos

# 2. 验证连通性
fcc doctor

# 3. 开始交互
fcc elements
fcc tap --text "Increment"
fcc screenshot -o /tmp/shot.png
```

### 多实例管理

```bash
# 注册
fcc register demo ws://127.0.0.1:8181/abc/ws
fcc register staging ws://127.0.0.1:8182/def/ws

# 列出所有实例
fcc list

# 针对特定实例操作
fcc -i demo tap --key LoginBtn
fcc -i staging screenshot -o /tmp/staging.png

# 注销
fcc unregister demo
```

## Commands Reference

### 连接与健康检查

| 命令 | 说明 |
|------|------|
| `fcc doctor` | 检查连通性（自动发现或已注册实例） |
| `fcc register <name> <uri>` | 注册命名实例 |
| `fcc unregister <name>` | 注销实例 |
| `fcc list` | 列出所有注册实例 |

### 手势交互

所有手势命令共享 **matcher 选项**：`--key`、`--text`、`--type`、`--x`/`--y`、`--focused`

| 命令 | 说明 | 示例 |
|------|------|------|
| `fcc tap` | 点击 | `fcc tap --text "Submit"` |
| `fcc double-tap` | 双击 | `fcc double-tap --key Avatar` |
| `fcc long-press` | 长按 | `fcc long-press --key Card --duration 800` |
| `fcc enter-text` | 输入文本 | `fcc enter-text --key Username --input demo` |
| `fcc scroll-to` | 滚动至可见 | `fcc scroll-to --text "Bottom Item"` |
| `fcc drag` | 拖拽 | `fcc drag --key Card1 --dx -100` |
| `fcc swipe` | 滑动 | `fcc swipe --key Feed --direction up --distance 500` |
| `fcc navigate` | 路由导航 | `fcc navigate --op push --route /settings` |

### 查询与诊断

| 命令 | 说明 |
|------|------|
| `fcc elements` | 列出当前屏幕可交互元素树 |
| `fcc logs` | 获取应用日志缓冲区 |
| `fcc rebuild` | 获取 widget rebuild 计数快照 |
| `fcc screenshot -o <path>` | 截图保存为 PNG |

### 热重载

```bash
fcc hot-reload
```

### 实时监听

```bash
# 监听日志 + rebuild，支持 --watch-uri 自动重连
fcc --watch-uri watch --logs --rebuilds
```

### YAML 脚本回放

```bash
fcc run smoke.yaml
```

### REPL 交互模式

```bash
fcc repl
fcc -i demo repl
fcc --watch-uri repl   # URI 变化时自动重连
```

### ADB 端口映射（Android 真机）

```bash
fcc adb-reverse 8181        # 建立映射
fcc adb-reverse-remove 8181 # 移除映射
```

### AI 辅助

```bash
fcc help-ai   # 输出机器可读的命令表面，供 AI agent 消费
```

## Global Options

| 选项 | 说明 |
|------|------|
| `--uri <uri>` | 显式指定 VM Service URI |
| `-i, --instance <name>` | 使用已注册实例名 |
| `--no-auto-uri` | 禁用自动 URI 发现 |
| `--watch-uri` | URI 文件变化时自动重连 |
| `--timeout <sec>` | 连接超时秒数（默认 5） |
| `--json` | JSON 输出模式（可 pipe 给 jq） |

## Widget Matcher 说明

matcher 是定位目标元素的核心机制，按可靠度排序：

1. **`--key <k>`** — `ValueKey<String>`，最可靠
2. **`--text <t>`** — 可见文本匹配
3. **`--type <n>`** — widget 类型名（如 `ElevatedButton`）
4. **`--x <n> --y <n>`** — 逻辑像素坐标
5. **`--focused`** — 当前焦点元素

如果目标元素难以定位，推荐在 Flutter 代码中添加 `ValueKey<String>` 作为稳定锚点。

## Troubleshooting

- **doctor 报连接失败**：确认 Flutter 应用正在运行且 `.vm_service_uri` 文件存在且非空
- **URI 过期**：应用重启后 URI 会变，重新读取或使用 `--watch-uri`
- **Android 真机连不上**：先执行 `fcc adb-reverse <port>`
- **enter-text 无效**：确认目标是 TextField 且 matcher 正确定位到了输入框
- **rebuild 为空**：需要 Flutter 侧开启 `FlutterCopilotConfiguration(enableGlobalRebuildHook: true)`，且不支持 Web

## Key Files

- `packages/flutter_copilot_cli/src/index.ts` — CLI 入口与命令注册
- `packages/flutter_copilot_cli/src/vm/connector.ts` — VM Service 连接器
- `packages/flutter_copilot_cli/src/vm/discover.ts` — isolate 发现逻辑
- `packages/flutter_copilot_cli/src/registry/auto_uri.ts` — URI 自动发现
- `packages/flutter_copilot_cli/src/registry/instance_registry.ts` — 多实例注册表
- `packages/flutter_copilot_cli/src/commands/gestures.ts` — 手势命令
- `packages/flutter_copilot_cli/src/commands/misc.ts` — 截图/日志/热重载等
- `packages/flutter_copilot_cli/src/commands/watch.ts` — 实时监听
- `packages/flutter_copilot_cli/src/commands/run.ts` — YAML 脚本执行
- `packages/flutter_copilot_cli/src/commands/repl.ts` — REPL 模式
