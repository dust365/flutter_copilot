# Flutter Copilot MCP

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)

**"Flutter 应用的 Playwright MCP/Cursor Browser"**

Flutter Copilot 是一个 MCP（Model Context Protocol）服务器，让 AI 智能体（如 Cursor、Claude Code 等）能够检查和交互运行中的 Flutter 应用程序。它直接将你的智能体连接到运行中的应用，使其能够查看组件树、点击元素、输入文本、滚动和截图，实现自动化冒烟测试和交互。

Flutter Copilot 保持简洁的设计理念，只暴露少量高价值操作，返回最小可操作数据，有助于保持提示词聚焦并控制上下文大小。

---

## 📋 目录

- [Flutter Copilot vs Flutter MCP](#flutter-copilot-vs-flutter-mcp)
- [快速开始](#快速开始)
- [安装](#安装)
- [Flutter 应用集成](#flutter-应用集成)
- [工具配置](#工具配置)
- [可用工具](#可用工具)
- [使用示例](#使用示例)
- [工作原理](#工作原理)
- [实际项目：包体积与仅 Debug 使用](#实际项目包体积与仅-debug-使用)
- [假设与限制](#假设与限制)
- [故障排除](#故障排除)

---

## Flutter Copilot vs Flutter MCP

官方的 [Dart & Flutter MCP 服务器](https://docs.flutter.dev/ai/mcp-server) 专注于**开发时**任务：搜索 pub.dev、管理依赖、分析代码和检查运行时错误。它也可以通过 Flutter Driver 驱动 UI，但这需要在应用中引入额外的工具。Flutter Copilot 专注于（以更简洁的方式）**运行时交互**：点击按钮、输入文本、滚动和截图，同时只需要对应用进行最小改动。使用 Flutter MCP 来构建你的应用，使用 Flutter Copilot 以最小代码改动来测试和交互。

---

## 🚀 快速开始

> **注意：** 你的 Flutter 应用必须准备好与此 MCP 兼容。

1. **准备 Flutter 应用** - 添加 `flutter_copilot_claw` 包并在 `main.dart` 中初始化 `FlutterCopilotBinding`。
2. **安装 MCP 服务器** - 将 `flutter_copilot_mcp` 添加到项目的 `dev_dependencies`。
3. **配置 AI 工具** - 将 MCP 服务器命令（`dart run flutter_copilot_mcp`）添加到工具的配置中（Cursor、Claude 等）。
4. **以调试模式运行应用** - 在控制台中查找 VM service URI（例如：`ws://127.0.0.1:12345/ws`）。
5. **连接并交互** - 让 AI 智能体使用 URI 连接到你的应用并开始交互。

---

## 📦 安装

### 1. 添加 MCP 服务器包

运行以下命令激活 `flutter_copilot_mcp` [全局工具](https://dart.dev/tools/pub/cmd/pub-global)：

```bash
dart pub global activate flutter_copilot_mcp
```

> [!NOTE]
> 你也可以使用 dev-dependency 方式安装：
>
> ```bash
> dart pub add dev:flutter_copilot_mcp
> ```
>
> 然后以 `dart run flutter_copilot_mcp` 方式调用 MCP 服务器。
> 可能需要更改工作目录，以便 `dart run` 能够找到 `flutter_copilot_mcp`。
> 可以这样做：`cd ${workspaceFolder}/packages/mypackage && dart run flutter_copilot_mcp`（不同工具可能有所不同）。
>
> 如果不起作用，我们建议使用全局工具方法。

### 2. 添加 Flutter 包

在 Flutter 应用目录中运行以下命令：

```bash
flutter pub add flutter_copilot_claw
```

---

## 🔧 Flutter 应用集成

你需要在应用中初始化 `FlutterCopilotBinding`。这个绑定注册了 MCP 服务器通信所需的 VM service 扩展。

### 基础设置

如果你的应用使用标准的 Flutter 组件（如 `ElevatedButton`、`TextField`、`Text` 等），默认配置即可开箱即用。

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  if (kDebugMode) {
    // 需要 get_logs 时用 runAppWithConfig（内部在同一 Zone 完成 ensureInitialized + runApp，勿在外部先 ensureInitialized）
    FlutterCopilotBinding.runAppWithConfig(const MyApp());
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  }
}
```

- 仅做 UI 交互、不需要日志：`FlutterCopilotBinding.ensureInitialized(); runApp(const MyApp());`
- 需要 `get_logs` 收集 print/错误：使用 **`FlutterCopilotBinding.runAppWithConfig(const MyApp())`**，且**不要**在外部先调用 `ensureInitialized()`（否则会 Zone 不匹配报错）；需自定义配置时传第二参数：`runAppWithConfig(const MyApp(), FlutterCopilotConfiguration(...))`。

### FlutterCopilotConfiguration 配置项

通过 `FlutterCopilotConfiguration` 可以控制 MCP 如何识别可交互元素、如何从组件提取文本，以及截屏尺寸。传入方式：`ensureInitialized(FlutterCopilotConfiguration(...))` 或 `runAppWithConfig(const MyApp(), FlutterCopilotConfiguration(...))`。

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| **isInteractiveWidget** | `bool Function(Type type)?` | 无 | 将**自定义组件类型**标记为「可交互」。返回 `true` 的类型会出现在 `get_interactive_elements` 中，并可被 `tap`、`enter_text`、`scroll_to` 等工具按类型或文本定位。仅在未命中内置 Flutter 组件（如 `ElevatedButton`、`TextField`）时才会调用。 |
| **shouldStopTraversal** | `bool Function(Type type)?` | 无 | 遍历组件树时，若遇到该类型则**不再向下遍历**。用于封装型组件（如自定义卡片、弹窗内容）：避免把内部大量子节点都暴露给智能体，只把该组件本身当作一个单元。仅在未命中内置“停止类型”（如 `Text`、`ElevatedButton`）时才会调用。 |
| **extractText** | `String? Function(Widget widget)?` | 无 | 从**自定义 Widget 实例**中提取用于显示的文本。该文本会出现在 `get_interactive_elements` 的 `text` 字段中，并用于按 `text` 匹配（如 `tap(text: '提交')`）。仅在未命中内置文本提取（如 `Text`、`TextField`）时才会调用。 |
| **maxScreenshotSize** | `Size?` | `Size(2000, 2000)` | 截屏的**最大物理像素尺寸**（宽×高）。超过时会按比例缩小以适配，保持宽高比。设为 `null` 表示不限制尺寸（原图输出，可能较大）。 |

**内置支持**：未配置上述回调时，Flutter Copilot 已内置识别常见 Flutter 组件（如 `ElevatedButton`、`TextField`、`Switch`、`InkWell`、`GestureDetector` 等）为可交互，并从 `Text`/`TextField` 等提取文本；`shouldStopTraversal` 对上述可交互类型和 `Text` 会默认停止遍历。

### 日志收集 (`get_logs`)

**不依赖 `logging` 包。** 日志通过以下方式收集：

1. **`runAppWithConfig`**：用 `FlutterCopilotBinding.runAppWithConfig(MyApp())` 替代 `runApp` 时，会收集 **`print()`** 输出以及 **Zone 内未捕获错误**。
2. **Binding 内建监控**：binding 初始化时注册 **FlutterError.onError** 和 **PlatformDispatcher.instance.onError**，自动收集 Flutter 框架错误和未捕获的异步错误。
3. **自定义日志**：在应用运行后任意位置调用 **`FlutterCopilotBinding.addLog(message, { isError: false })`**，该条会进入 `get_logs` 的返回结果。

```dart
// 自定义日志示例（会被 get_logs 拉取）
FlutterCopilotBinding.addLog('Application ready for VM Service connection');
FlutterCopilotBinding.addLog('Something went wrong', isError: true);
```

总结：希望 `get_logs` 有内容时，使用 `runAppWithConfig` 并视需使用 `addLog`；无需引入 `logging` 包。

### 自定义设计系统

如果你在设计系统中使用自定义组件，通过 [FlutterCopilotConfiguration 配置项](#fluttercopilotconfiguration-配置项) 中的 `isInteractiveWidget` 和 `extractText` 让 MCP 识别它们为可交互元素并提取文本。

**为什么需要 `isInteractiveWidget`？** 典型屏幕的组件树中有大量 `Padding`、`Container`、`Column` 等。`get_interactive_elements` 会过滤为可操作目标（按钮、输入框、开关等），便于智能体操作。默认已识别 `ElevatedButton`、`TextField`、`Switch` 等；若你使用自定义按钮/输入框（如 `MyPrimaryButton`、`MyTextField`），需在配置中把这些类型标记为可交互，它们才会出现在元素列表中并被 `tap`、`enter_text` 等定位。若某些自定义组件内部结构复杂、不希望暴露子节点，可用 `shouldStopTraversal` 在该类型处停止遍历。

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';
import 'package:my_app/design_system/buttons.dart';
import 'package:my_app/design_system/inputs.dart';

void main() {
  if (kDebugMode) {
    FlutterCopilotBinding.runAppWithConfig(
      const MyApp(),
      FlutterCopilotConfiguration(
        // 识别自定义交互组件，使其出现在 get_interactive_elements 中
        isInteractiveWidget: (type) =>
            type == MyPrimaryButton ||
            type == MyTextField ||
            type == MyCheckbox,

        // 在封装组件处停止遍历，不暴露内部子节点
        shouldStopTraversal: (type) => type == MyCard,

        // 从自定义组件中提取文本，供按 text 匹配使用
        extractText: (widget) {
          if (widget is MyText) return widget.data;
          if (widget is MyTextField) return widget.controller?.text;
          return null;
        },

        // 可选：截屏尺寸限制（默认 2000×2000，null 表示不限制）
        maxScreenshotSize: const Size(2000, 2000),
      ),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  }
}
```

---

## ⚙️ 工具配置

将 MCP 服务器添加到你的 AI 编程助手的配置中。

### Cursor

[![Install MCP Server](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/en-US/install-mcp?name=flutter_copilot&config=eyJlbnYiOnt9LCJjb21tYW5kIjoiZmx1dHRlcl9jb3BpbG90X21jcCJ9)

或手动添加到项目的 `.cursor/mcp.json` 或全局 `~/.cursor/mcp.json`：

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

### Google Antigravity

打开 MCP 商店，点击 "Manage MCP Servers"，然后 "View raw config" 并添加到打开的 `mcp_config.json`：

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

### Gemini CLI

添加到 `~/.gemini/settings.json`：

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

### Claude Code

你可以运行以下命令添加：

```bash
claude mcp add --transport stdio flutter_copilot -- flutter_copilot_mcp
```

### Copilot

添加到 `mcp.json`：

```json
{
  "servers": {
    "flutter_copilot": {
      "command": "flutter_copilot_mcp",
      "args": []
    }
  }
}
```

---

## 🛠️ 可用工具

连接后，AI 智能体可以访问以下工具：

### 连接管理

| 工具 | 描述 | 参数 |
|------|------|------|
| `connect` | 通过 VM service URI 连接到 Flutter 应用（例如：`ws://127.0.0.1:54321/ws`）。必须先调用此工具才能使用其他工具。 | `uri` (必需): VM service URI |
| `disconnect` | 断开当前连接的应用。断开后，必须再次调用 `connect` 才能使用其他工具。 | 无 |

### UI 元素检测

| 工具 | 描述 | 参数 |
|------|------|------|
| `get_interactive_elements` | 返回屏幕上所有可交互 UI 元素的列表（按钮、输入框等）。每个元素包括其类型、文本内容（如果有）、key（如果有）和其他识别属性。 | 无 |

### 用户交互

| 工具 | 描述 | 参数 |
|------|------|------|
| `tap` | 点击匹配指定条件的元素。可以通过 key、文本、类型或坐标匹配。优先使用 key，因为它更可靠。 | `key` (可选): 元素的 key<br>`text` (可选): 可见文本内容<br>`type` (可选): 组件类型名称<br>`coordinates` (可选): 屏幕坐标 `{x, y}` |
| `enter_text` | 在匹配 key 的文本框中输入文本。模拟在字段中键入文本。 | `input` (必需): 要输入的文本<br>`key` (必需): 文本框的 key |
| `scroll_to` | 滚动视图直到匹配 key 或文本的元素可见。当需要与当前不可见的元素交互时很有用。 | `key` (可选): 元素的 key<br>`text` (可选): 可见文本内容 |

### 手势操作

| 工具 | 描述 | 参数 |
|------|------|------|
| `flutter_copilot_drag` | 在元素上模拟拖拽手势。可以通过 key、文本、类型或坐标匹配。支持相对拖拽（deltaX/deltaY）或绝对拖拽（from/to 坐标）。 | `key/text/type/coordinates` (可选): 匹配元素<br>`deltaX` (可选): 水平拖拽距离<br>`deltaY` (可选): 垂直拖拽距离<br>`from` (可选): 起始坐标 `{x, y}`<br>`to` (可选): 结束坐标 `{x, y}` |
| `swipe` | 在元素上模拟滑动手势。可以通过 key、文本、类型或坐标匹配。滑动方向可以是 left、right、up 或 down。 | `key/text/type/coordinates` (可选): 匹配元素<br>`direction` (必需): 滑动方向 (left/right/up/down)<br>`distance` (可选): 滑动距离（像素，默认 200） |
| `long_press` | 在元素上模拟长按手势。可以通过 key、文本、类型或坐标匹配。长按持续时间可自定义。 | `key/text/type/coordinates` (可选): 匹配元素<br>`duration` (可选): 长按持续时间（毫秒，默认 500） |
| `double_tap` | 在元素上模拟双击手势。可以通过 key、文本、类型或坐标匹配。 | `key/text/type/coordinates` (可选): 匹配元素 |

### 导航控制

| 工具 | 描述 | 参数 |
|------|------|------|
| `navigate` | 控制应用导航。支持 push（导航到新路由）、pop（返回）、replace（替换当前路由）、pushReplacement（推送并替换）和 popUntil（弹出直到特定路由）。 | `action` (必需): 导航操作 (push/pop/replace/pushReplacement/popUntil)<br>`route` (可选): 路由名称<br>`arguments` (可选): 传递给路由的参数 |

### 调试与监控

| 工具 | 描述 | 参数 |
|------|------|------|
| `get_logs` | 检索自连接或上次日志检索以来从 Flutter 应用收集的日志。需应用使用 `runAppWithConfig` 以收集 `print()` 与未捕获错误，或通过 `FlutterCopilotBinding.addLog` 添加自定义日志；Binding 会自动收集 FlutterError 与异步错误。 | 无 |
| `take_screenshots` | 捕获 Flutter 应用中所有视图的截图。返回 base64 编码的 PNG 图像，可以解码和保存。这捕获应用的当前视觉状态。 | 无 |
| `hot_reload` | 执行 Flutter 应用的热重载。重新加载 Dart 代码而不重启应用，保留当前状态。在代码更改后很有用，可以在运行的应用中看到更改。 | 无 |

### 元素匹配优先级

当使用交互工具（如 `tap`、`enter_text` 等）时，元素匹配的优先级为：

1. **坐标 (x, y)** - 最高优先级，直接点击指定位置
2. **key** - 最可靠，通过 `ValueKey<String>` 精确匹配
3. **text** - 通过可见文本内容匹配
4. **type** - 通过组件类型名称匹配

> **提示：** 优先使用 `key` 进行匹配，因为它最可靠且不受 UI 文本变化影响。如果无法定位组件，可能需要在 Flutter 源代码中为其添加 `ValueKey`。例如：`ElevatedButton(key: ValueKey('submit_button'), ...)`

---

## 💡 使用示例

Flutter Copilot 在用于验证工作或探索应用时表现出色。以下是一些结合代码和功能的实际场景：

### 1. 完整表单填写与提交流程测试

**场景：** 你刚实现了一个用户注册表单，需要验证整个填写和提交流程。

**代码示例：**
```dart
// 你的注册表单代码
TextField(
  key: const ValueKey('email_field'),
  controller: _emailController,
  decoration: const InputDecoration(labelText: '邮箱'),
),
TextField(
  key: const ValueKey('password_field'),
  controller: _passwordController,
  obscureText: true,
  decoration: const InputDecoration(labelText: '密码'),
),
ElevatedButton(
  key: const ValueKey('submit_button'),
  onPressed: _handleSubmit,
  child: const Text('注册'),
)
```

**AI 提示：**
> "请测试用户注册表单的完整流程：
> 1. 连接到应用（VM Service URI: `ws://127.0.0.1:54321/ws`）
> 2. 使用 `get_interactive_elements` 查看表单元素
> 3. 在邮箱字段（key: `email_field`）输入 `test@example.com`
> 4. 在密码字段（key: `password_field`）输入 `SecurePass123!`
> 5. 点击提交按钮（key: `submit_button`）
> 6. 使用 `get_logs` 检查是否有错误，并确认提交成功日志
> 7. 使用 `take_screenshots` 验证提交后的界面状态"

**验证要点：**
- ✅ 所有字段正确填写
- ✅ 提交按钮可点击
- ✅ 日志显示提交成功
- ✅ 界面状态正确更新

---

### 2. 复杂手势操作与状态验证

**场景：** 你实现了一个可拖拽的滑块和可滑动的列表，需要测试手势交互是否正常工作。

**代码示例：**
```dart
// 滑块组件
Slider(
  key: const ValueKey('volume_slider'),
  value: _volume,
  min: 0.0,
  max: 100.0,
  onChanged: (value) {
    setState(() => _volume = value);
    _logger.info('Volume changed to: $value');
  },
)

// 可滑动列表
PageView(
  key: const ValueKey('image_carousel'),
  children: _images.map((img) => Image.network(img)).toList(),
)
```

**AI 提示：**
> "请测试手势交互功能：
> 1. 连接到应用并导航到手势演示页面
> 2. 使用 `get_interactive_elements` 找到滑块（key: `demo_slider`）
> 3. 使用 `flutter_copilot_drag` 将滑块从当前位置向右拖拽 100 像素（deltaX: 100）
> 4. 检查日志确认滑块值已更新
> 5. 找到图片轮播（key: `image_carousel`），使用 `swipe` 向左滑动（direction: left）
> 6. 使用 `take_screenshots` 验证图片已切换
> 7. 使用 `get_logs` 确认所有手势操作都记录了日志"

**验证要点：**
- ✅ 滑块值正确更新
- ✅ 滑动操作成功执行
- ✅ 界面状态同步更新
- ✅ 日志记录完整

---

### 3. 导航流程与页面状态验证

**场景：** 你重构了应用的导航系统，需要验证路由跳转和页面状态管理。

**代码示例：**
```dart
// 导航路由配置
MaterialApp(
  routes: {
    '/home': (context) => const HomePage(),
    '/profile': (context) => const ProfilePage(),
    '/settings': (context) => const SettingsPage(),
  },
)

// 导航按钮
ElevatedButton(
  key: const ValueKey('nav_to_profile'),
  onPressed: () => Navigator.pushNamed(context, '/profile'),
  child: const Text('查看个人资料'),
)
```

**AI 提示：**
> "请测试应用的导航流程：
> 1. 连接到应用，使用 `get_interactive_elements` 查看首页元素
> 2. 使用 `navigate` 工具导航到个人资料页面（action: push, route: `/profile`）
> 3. 使用 `take_screenshots` 验证页面已切换
> 4. 在个人资料页面，使用 `get_interactive_elements` 查看该页面的元素
> 5. 使用 `navigate` 导航到设置页面（action: push, route: `/settings`）
> 6. 使用 `navigate` 返回上一页（action: pop）
> 7. 使用 `navigate` 返回到根页面（action: popUntil）
> 8. 使用 `get_logs` 检查导航过程中是否有错误
> 9. 最后使用 `take_screenshots` 确认已回到首页"

**验证要点：**
- ✅ 路由跳转正常
- ✅ 页面状态正确
- ✅ 返回功能正常
- ✅ 导航栈管理正确

---

## 🔍 工作原理

1. **初始化**：你的 Flutter 应用初始化 `FlutterCopilotBinding`，它注册自定义 VM service 扩展（`ext.flutter.flutter_copilot.*`）。
2. **连接**：MCP 服务器连接到应用的 VM Service URL。
3. **交互**：当 AI 智能体调用工具（如 `tap`）时，MCP 服务器将其转换为对应用中相应 VM service 扩展的调用。
4. **执行**：Flutter 应用执行操作（例如，模拟点击手势）并返回结果。

---

## 📦 实际项目：包体积与仅 Debug 使用

### 会影响发布包体积吗？

- **依赖**：`flutter_copilot_claw` 仅依赖 Flutter SDK（无第三方包），无原生插件，不会引入额外 so/aar 等。
- **Tree-shaking**：若你**仅在 debug 分支里**引用该包（例如 `if (kDebugMode) { FlutterCopilotBinding.runAppWithConfig(...) } else { runApp(...) }`），`kDebugMode` 在 release 下是编译时常量 `false`，Dart 在 release 构建时会做 tree-shaking，**未走到的分支及其引用可被移除**，因此理论上 **release 包不会包含 Flutter Copilot 的代码**，对发布包体积无影响。
- **建议**：集成时始终用 `kDebugMode` 包裹初始化与 `runAppWithConfig`，避免在 release 路径里引用 `FlutterCopilotBinding`；若需确认，可用 `flutter build apk --release`（或 ios）对比加/不加该依赖的产物大小。

### 可以只在 Debug 模式下打开吗？

**可以，且推荐。** 使用方式就是「仅在 debug 时初始化」：

- 在 **debug**：执行 `FlutterCopilotBinding.runAppWithConfig(...)` 或 `ensureInitialized()` + `runApp(...)`，MCP 可连接 VM Service 使用。
- 在 **release**：走 `WidgetsFlutterBinding.ensureInitialized(); runApp(const MyApp());`，不引用 Flutter Copilot，且 VM Service 在 release 下本身也不存在，即使带了相关代码也无法连接。

这样既满足「仅 debug 打开」，又利于 tree-shaking 避免增加发布包体积。

---

## ⚠️ 假设与限制

- **建议手动粘贴 VM Service URI**：虽然某些工具有时可以发现或推断 VM Service 端点，但最可靠的工作流程是从 `flutter run` 输出（或 DevTools 链接）复制 `ws://.../ws` URI，并在调用 `connect` 时将其粘贴给智能体。

- **智能体可能不了解你的应用**：Flutter Copilot 可以"看到"组件树并与 UI 元素交互，但它不会自动理解你的产品流程、命名约定或边缘情况。如果你想要可靠的导航和断言，请在提示中提供额外的上下文（要到达的屏幕、预期的标签/keys、前提条件和交互目标）。

- **"你的体验可能有所不同"的交互**：某些操作是通过尽力模拟用户行为（手势、焦点、文本输入、滚动）实现的。根据平台、自定义组件、覆盖层或应用特定的手势处理，结果可能有所不同。如果流程不稳定，请考虑暴露更清晰的组件 keys、简化点击目标，或为你的设计系统添加自定义 `FlutterCopilotConfiguration` 钩子。如果你遇到持续不符合预期的行为，在 issue 中提供小的复现示例有助于我们改进。

---

## 🔧 故障排除

- **"未连接到任何应用"**：确保 AI 智能体在使用其他工具之前已使用有效的 VM Service URI 调用 `connect`。

- **查找 URI**：以调试模式运行 Flutter 应用（`flutter run`）。查找类似这样的行：`The Flutter DevTools debugger and profiler on iPhone 15 Pro is available at: http://127.0.0.1:9101?uri=ws://127.0.0.1:9101/ws`。使用 `ws://...` 部分。

- **发布模式**：Flutter Copilot 仅在调试（和分析）模式下工作，因为它依赖于 VM Service。它不会在发布构建中工作。

- **找不到元素**：确保你的组件可见。如果使用自定义组件，请确保它们在 `FlutterCopilotConfiguration` 中配置。