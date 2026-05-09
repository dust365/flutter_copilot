# Flutter Copilot

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)
[![flutter_copilot_claw pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_claw)](https://pub.dev/packages/flutter_copilot_claw)
[![flutter_copilot_cli npm badge](https://img.shields.io/npm/v/flutter_copilot_cli)](https://www.npmjs.com/package/flutter_copilot_cli)

**Flutter Copilot 是一个面向运行中 Flutter 应用的 MCP 方案，让 Claude Code、Cursor 等 AI Agent 能够直接连接、观察、操作和诊断 App。**

它通过 `MCP + VM Service` 把 AI 工具和 Flutter 运行时连接起来，让 Agent 不只停留在代码层面，还能进入真实应用状态完成页面验证、交互调试、日志排查和运行时诊断。

## Demo

<a href="docs/video/演示视频.mp4">
  <img src="docs/images/demo-preview.gif" alt="Flutter Copilot Demo" width="360" />
</a>

Flutter Copilot 包含三个已发布的包：

- [`flutter_copilot_mcp`](https://pub.dev/packages/flutter_copilot_mcp)：MCP Server，负责让 Claude Code、Cursor 等 AI Client 连接并调用 Flutter 能力
- [`flutter_copilot_claw`](https://pub.dev/packages/flutter_copilot_claw)：Flutter 侧挂载插件，负责在 App 内注册运行时能力
- [`flutter_copilot_cli`](https://www.npmjs.com/package/flutter_copilot_cli)：面向终端用户与 CI 的命令行工具，不依赖 MCP 协议即可直接驱动 Flutter App

更多演示功能请查看[演示视频](docs/video/演示视频.mp4)。

## 项目概述

Flutter Copilot 由三部分组成：

- [`flutter_copilot_mcp`](https://pub.dev/packages/flutter_copilot_mcp)：运行在 App 外部的 MCP Server，对 AI Client 暴露标准工具能力（已发布到 pub.dev）
- [`flutter_copilot_claw`](https://pub.dev/packages/flutter_copilot_claw)：集成在 Flutter App 内的运行时挂载插件，负责注册 VM Service 扩展（已发布到 pub.dev）
- [`flutter_copilot_cli`](https://www.npmjs.com/package/flutter_copilot_cli)：基于 Node.js 的命令行工具，直连 VM Service 执行交互、截图、脚本化测试，适用于终端调试与 CI 流水线（已发布到 npm）

![Flutter Copilot 整体架构](docs/images/svg/【3-1-1】FlutterCopilot整体架构.svg)

一句话理解：

> `flutter_copilot_claw` 在 App 内提供能力，`flutter_copilot_mcp` 在 App 外桥接 AI Agent，`flutter_copilot_cli` 则在终端/CI 中直接驱动 App，最终让人类与 AI 都能操作运行中的 Flutter 应用。

## 适用场景

Flutter Copilot 适合这些典型场景：

- 页面交互验证
- 冒烟测试与流程回归
- UI 问题复现与调试
- 运行时日志采集
- 热重载后的快速确认
- Widget 重建热点排查

## 核心能力

![Flutter Copilot 能力总览](docs/images/svg/【3-4-1】FlutterCopilot能力总览.svg)

### 连接与观察

- 连接 Flutter App 的 VM Service
- 获取当前页面可交互元素
- 截图与日志获取

### 交互与导航

- 点击、输入、滚动
- 拖拽、滑动、长按、双击
- 页面导航控制
- Hot Reload

### 诊断能力

- Rebuild Snapshot / 重建热点分析

### 元素定位方式

- `ValueKey<String>`
- 文本内容
- Widget 类型
- 坐标

其中 `ValueKey<String>` 是最稳定、最推荐的方式。

## 工作原理

![MCP 协议与 VM Service 调用链路](docs/images/svg/【3-3-1】MCP协议与VMService调用链路.svg)

Flutter Copilot 的调用链路可以概括为：

1. AI Client 发起工具调用
2. `flutter_copilot_mcp` 将调用转换为 Flutter 可执行的操作
3. `flutter_copilot_claw` 在运行中的 App 内通过 VM Service 扩展执行操作
4. 结果以截图、日志、状态或结构化文本返回给 AI Client

这使得 AI 可以直接基于 Flutter 运行时状态进行判断，而不是只依赖源码或屏幕像素猜测。

## Quick Start

如果你是第一次接触这个项目，建议从 [`flutter_copilot_mcp`](https://pub.dev/packages/flutter_copilot_mcp) 开始；它是主要入口，包含安装、快速开始、工具列表和 Agent 配置方式。`flutter_copilot_claw` 则负责 Flutter 侧运行时挂载。

### 1. Add `flutter_copilot_claw` to your Flutter app

```bash
flutter pub add flutter_copilot_claw
```

在 `main.dart` 中初始化 Flutter Copilot。一行搞定，debug/profile/release 都安全 —— release 下 `captureLogs` 和 `ensureInitialized` 自动短路为 no-op，零开销，无需 `kDebugMode` 分支：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  FlutterCopilotBinding.captureLogs(() async {
    FlutterCopilotBinding.ensureInitialized();
    // 任何 async 初始化（SystemChrome / 插件 / 远端配置等）都可以放在这里，
    // 它们的 print() 和未捕获异常都会进入 get_logs。
    runApp(const MyApp());
  });
}
```

如果你只需要 UI 交互、不在意 `print()` 捕获，可以省掉外层 `captureLogs`：

```dart
void main() {
  FlutterCopilotBinding.ensureInitialized();
  runApp(const MyApp());
}
```

#### 日志三路：`captureLogs` vs `addLog` vs 自动捕获

`get_logs` 的内容来自三个互相独立的来源，分别对应不同的入口：

| 来源 | 捕获什么 | 怎么开 |
|---|---|---|
| 框架错误 | `FlutterError.onError` + `PlatformDispatcher.onError` | 自动 —— `ensureInitialized()` 内部已挂好。 |
| 环境输出 | 所有 `print()` / `debugPrint()` 输出 + 未捕获的 async 异常 | 用 `captureLogs(body)` 包住要监听的代码块。 |
| 显式打点 | 你主动写的字符串 | 在调用点写 `FlutterCopilotBinding.addLog(message, isError: false)`。 |

`addLog` 和 `captureLogs` **完全独立**：只要 `ensureInitialized()` 跑过，不管外面有没有 zone，都能直接 `addLog`。它更适合打"业务事件标记"（`login:attempt` / `payment:step:confirm`），在 MCP 日志流里一眼能 grep 到，不用跟散落的 `print()` 混在一起。

**什么时候用哪个**

- **只用 `captureLogs`**：零改动迁移。现有代码里所有 `print()` 自动进 `get_logs`。
- **只用 `addLog`**：不想多套一层 zone，想完全控制哪些事件进日志。
- **两个都用**：信息量最全。`captureLogs` 兜底一切，`addLog` 负责高信号标记。

**两者都用的示例**

```dart
void main() {
  FlutterCopilotBinding.captureLogs(() async {
    FlutterCopilotBinding.ensureInitialized();
    FlutterCopilotBinding.addLog('app:boot:start');
    await SomePlugin.init();
    FlutterCopilotBinding.addLog('app:boot:plugins-ready');
    runApp(const MyApp());
  });
}

// 业务页面中任何位置都能直接调
Future<void> _login() async {
  FlutterCopilotBinding.addLog('login:attempt');
  try {
    await AuthService.signIn();
    FlutterCopilotBinding.addLog('login:success');
  } catch (e) {
    FlutterCopilotBinding.addLog('login:error: $e', isError: true);
    rethrow; // 未捕获异常也会被外层 captureLogs 兜住
  }
}
```

**release 行为**：三个入口都 release-safe —— `captureLogs` 退化为直接 `body()`，`addLog` 变 no-op，`ensureInitialized` 退化为 `WidgetsFlutterBinding.ensureInitialized()`。所以上面所有写法都可以不加 `kDebugMode` 保护就直接留在生产代码里。

### 2. Install `flutter_copilot_mcp`

全局安装：

```bash
dart pub global activate flutter_copilot_mcp
```

或者作为开发依赖安装：

```bash
dart pub add dev:flutter_copilot_mcp
```

### 3. Run your Flutter app in debug mode

```bash
flutter run
```

从控制台拿到 VM Service URI，例如：

```text
ws://127.0.0.1:12345/ws
```

### 4. Configure the MCP server in your Agent

#### Claude Code

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- flutter_copilot_mcp
```

如果你是在当前仓库里直接调试源码：

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

#### Cursor

Cursor 通过 `.cursor/mcp.json` 读取 MCP 配置：

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "type": "stdio",
      "command": "flutter_copilot_mcp"
    }
  }
}
```

### 5. Connect and use the app

完成配置后，推荐按下面的顺序使用：

1. 调用 `connect`，传入 VM Service URI
2. 调用 `get_interactive_elements`、`take_screenshots`、`get_logs` 了解当前页面状态
3. 再调用交互工具，例如：
   - `tap`
   - `enter_text`
   - `scroll_to`
   - `flutter_copilot_drag`
   - `swipe`
   - `long_press`
   - `double_tap`
   - `navigate`
4. 在需要时调用：
   - `hot_reload`
   - `get_rebuild_snapshot`

为了让 Agent 更稳定地操作 Flutter App，建议：

- 优先给关键元素添加 `ValueKey<String>`
- 先从核心路径开始接入，例如登录、表单、详情页
- 调试阶段优先使用 Debug 模式
- 在需要日志和异常信息时用 `FlutterCopilotBinding.captureLogs(...)` 包裹 `main()`

### 6. Use the `flutter-copilot` skill for auto-connect

如果你在觉得上面手动链接的方案，不方便，请使用项目使用本仓库内置的 `flutter-copilot` skill，可以使用更自动化的连接方案。

这个 skill 会优先从项目根目录的 `.vm_service_uri` 文件读取当前 Flutter App 的 VM Service URI，再完成 Flutter Copilot MCP 连接。相比手动复制 URI，这种方式更适合持续调试、截图验证和热重载后的重复连接。

推荐流程：

1. 通过项目里的启动方式运行 Flutter App，例如 `scripts/flutter_run.sh` 或对应的 VS Code 启动配置
2. 确认项目根目录下已经生成 `.vm_service_uri`
3. 在 Claude Code 中使用 `flutter-copilot` skill，让它自动读取 URI 并连接
4. 后续继续使用截图、点击、输入、滚动、热重载等能力

这种方式特别适合：

- 频繁重启 App 后重新连接
- 需要快速截图或验证 UI 修改结果
- 把 Flutter Copilot 作为其他 skill 的前置能力

如果应用重启后 URI 变化，只需要重新使用 `flutter-copilot` skill，它会按新的 `.vm_service_uri` 重新连接。

## Flutter Copilot CLI

[`flutter_copilot_cli`](https://www.npmjs.com/package/flutter_copilot_cli)（命令名 `fcc` 或 `flutter_copilot_cli`，npm 地址：<https://www.npmjs.com/package/flutter_copilot_cli>）是与 MCP Server 并列的另一条使用路径。它直接通过 `ext.flutter.flutter_copilot.*` VM Service 扩展驱动 App，不依赖 MCP 协议，也不依赖任何 AI Client。

### 为什么需要 CLI？

- **给人用**：在终端里直接截图、点击、热重载，免去打开 AI Client 的链路
- **给 CI 用**：在 GitHub Actions、Jenkins 等流水线中以 YAML playbook 运行冒烟测试
- **给受限 AI 用**：对于不支持 MCP 协议的 Agent（或只能执行 shell 命令的小模型），通过 `fcc help-ai` 输出的 JSON 规范即可让它们驱动 App

能力对照：

| 能力                                          | `flutter_copilot_mcp` | `flutter_copilot_cli`         |
| --------------------------------------------- | :-------------------: | ----------------------------- |
| tap / drag / scroll / navigate / 日志 / 截图 |          ✅           | ✅                            |
| 当前 App 连接管理                             |      `connect` 工具   | ✅ `.vm_service_uri` / `connect` |
| 交互式 REPL                                   |          ❌           | ✅ `repl`                     |
| 日志 / Rebuild 实时流                         |          ❌           | ✅ `watch --logs --rebuilds`  |
| YAML playbook(CI/冒烟测试)                    |          ❌           | ✅ `run script.yaml`          |
| 面向 AI 的自描述                              |      经由 MCP         | ✅ `help-ai`(JSON)            |

### 安装

要求 Node.js **>= 18**。

```bash
# 全局安装(三选一)
npm install -g flutter_copilot_cli
pnpm add -g flutter_copilot_cli
yarn global add flutter_copilot_cli

# 校验
fcc --version
fcc --help
```

安装后会在 PATH 中注册两个等价命令：`flutter_copilot_cli`(全名) 与 `fcc`(别名)。

### 快速上手

先确保 Flutter App 已经初始化 `flutter_copilot_claw`:

```dart
void main() {
  FlutterCopilotBinding.captureLogs(() {
    FlutterCopilotBinding.ensureInitialized();
    runApp(const MyApp());
  });
}
```

CLI 按如下顺序解析 VM Service URI,通常无需手动传入：

1. `--uri <ws://...>` — 显式指定
2. `FLUTTER_COPILOT_URI` 环境变量
3. 当前目录或任一祖先目录下的 `.vm_service_uri` 文件

推荐配合仓库内的 `scripts/flutter_run.sh` 使用,它会把 URI 写入 `.vm_service_uri`:

```bash
./scripts/flutter_run.sh -d macos       # 启动 App,自动写入 .vm_service_uri
fcc doctor                              # 自动读取 URI 进行健康检查
fcc --uri "$(cat .vm_service_uri)" doctor # 只检查显式传入的 URI
fcc get-interactive-elements            # 列出当前可交互元素
fcc tap --text "Increment"              # 按文本点击
fcc take-screenshots -o /tmp/shot.png   # 截图
fcc hot-reload                          # 热重载
```

或者手动保存当前项目连接：

```bash
fcc connect --uri ws://127.0.0.1:8181/abc/ws
fcc tap --text "Increment"
fcc enter-text --key UsernameField --input "demo user"
```

### 实时流与自动重连

```bash
# 同时订阅日志与 rebuild 事件
fcc watch --logs --rebuilds --interval 500

# 配合 --watch-uri 可在 flutter 重启后自动重连
fcc --watch-uri watch --rebuilds
```

### YAML Playbook(CI 场景)

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
  - action: take-screenshots
    output: /tmp/after-login.png
  - action: assert-element
    text: Welcome
```

```bash
fcc run smoke.yaml
```

每个步骤可附带 `retry: { attempts, delay }` 做自动重试。

### 给 AI Agent 使用

```bash
fcc help-ai                        # 输出完整命令表与脚本 schema 的 JSON
fcc --json get-interactive-elements # 所有命令都支持 --json,便于管道消费
```

更多命令、参数与示例参见 [packages/flutter_copilot_cli/README.md](packages/flutter_copilot_cli/README.md)。

## 平台支持

| Platform | Support | Notes                    |
| -------- | ------- | ------------------------ |
| Android  | ✅      | Debug mode               |
| iOS      | ✅      | Debug mode               |
| Web      | ✅      | 部分诊断能力存在平台差异 |
| macOS    | ✅      | Debug mode               |
| Windows  | ✅      | Debug mode               |
| Linux    | ✅      | Debug mode               |

实际能力依赖 Flutter 调试能力与 VM Service，可用性以调试模式下的运行环境为准。

## 仓库结构

- [packages/flutter_copilot_mcp/](packages/flutter_copilot_mcp/) — MCP Server 与工具桥接层
- [packages/flutter_copilot_claw/](packages/flutter_copilot_claw/) — Flutter 侧运行时绑定与 VM Service 扩展
- [packages/flutter_copilot_cli/](packages/flutter_copilot_cli/) — TypeScript/Node.js 命令行工具
- [example/](example/) — 示例应用
- [tool/](tool/) — 仓库工具脚本
- [docs/](docs/) — 补充文档

## 相关文档

- [项目说明](docs/项目说明.md)
- [VM Service 连接原理与实现](docs/VM_Service连接原理与实现.md)
- [Claude Code 调试本地 MCP 教程](docs/ClaudeCode调试本地MCP教程.md)
- [flutter_copilot_mcp README](packages/flutter_copilot_mcp/README.md)
- [flutter_copilot_claw README](packages/flutter_copilot_claw/README.md)
- [flutter_copilot_cli README](packages/flutter_copilot_cli/README.md)

## License

Apache License 2.0
