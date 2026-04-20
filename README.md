# Flutter Copilot

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)

**让 Claude Code、Cursor 等 AI Agent 直接操作正在运行的 Flutter App。**

Flutter Copilot 是一套面向运行时交互的 MCP 方案：

- 连接 Flutter App 的 VM Service
- 获取当前页面可交互元素
- 点击、输入、滚动、截图
- 读取日志、热重载、查看重绘热点

适合用来做：

- 冒烟测试
- 页面验证
- 交互排查
- Agent 驱动的 UI 调试

---

## 它包含什么

这个仓库有两部分：

- `flutter_copilot_claw`：集成到 Flutter App 内，注册 VM Service 扩展
- `flutter_copilot_mcp`：MCP Server，供 Claude Code / Cursor 调用

一句话理解：

> `claw` 在 App 里，`mcp` 在 App 外，Agent 通过 `mcp` 去操作运行中的 App。

---

## 3 分钟接入

### 1. 给 Flutter App 加依赖

```bash
flutter pub add flutter_copilot_claw
```

### 2. 在 `main.dart` 初始化

只需要 UI 交互：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  if (kDebugMode) {
    FlutterCopilotBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const MyApp());
}
```

如果你还希望 `get_logs` 收集 `print()` 和未捕获错误：

```dart
void main() {
  if (kDebugMode) {
    FlutterCopilotBinding.runAppWithConfig(const MyApp());
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  }
}
```

### 3. 安装 MCP Server

推荐全局安装：

```bash
dart pub global activate flutter_copilot_mcp
```

也可以作为 dev dependency：

```bash
dart pub add dev:flutter_copilot_mcp
```

---

## Agent 侧配置

### Cursor

Cursor 读取 [`.cursor/mcp.json`](.cursor/mcp.json)。

最简单的配置是：

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

### Claude Code

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- flutter_copilot_mcp
```

如果你是在这个仓库里直接调试源码：

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

Claude Code 调试本地 MCP 的详细说明见：

- [文档/ClaudeCode调试本地MCP教程.md](文档/ClaudeCode调试本地MCP教程.md)

---

## 怎么用

1. 启动 Flutter App
   ```bash
   flutter run
   ```

2. 拿到 VM Service URI，例如：
   ```text
   ws://127.0.0.1:12345/ws
   ```

3. 让 Agent 先调用 `connect`

4. 再调用：
   - `get_interactive_elements`
   - `tap`
   - `enter_text`
   - `scroll_to`
   - `take_screenshots`
   - `get_logs`
   - `hot_reload`

---

## 本仓库本地开发

运行示例：

```bash
cd example && flutter run
```

直接运行 MCP：

```bash
cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart -l FINEST
```

常用检查：

```bash
cd packages/flutter_copilot_mcp && dart analyze --fatal-infos lib bin
cd packages/flutter_copilot_claw && flutter analyze --fatal-infos lib
cd packages/flutter_copilot_claw && flutter test
cd example && flutter analyze
cd example && flutter test
dart tool/generate_version.dart
```

---

## 限制

- 只支持 **Debug / Profile**，不支持 Release
- 最稳定的元素定位方式是 `ValueKey<String>`
- 大量自定义组件时，建议补 `FlutterCopilotConfiguration`
- Web 下 `get_rebuild_snapshot` 为空是预期行为

---

## 文档

- [文档/项目说明.md](文档/项目说明.md)
- [文档/VM_Service连接原理与实现.md](文档/VM_Service连接原理与实现.md)
- [文档/ClaudeCode调试本地MCP教程.md](文档/ClaudeCode调试本地MCP教程.md)

## License

Apache License 2.0
