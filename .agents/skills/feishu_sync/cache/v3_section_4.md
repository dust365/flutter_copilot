## 四、接入指南

前面讲了这么多，大家最自然的一个问题就是：**这个东西到底怎么接？复杂不复杂？**

我把它总结成三步，核心原则就是：**App 内挂能力，App 外按场景选择 MCP 或 CLI，再把高频流程沉淀下来。**

<image token="T2tobSFIvoGLmOxaKkWcl2gpnHh" width="1200" height="720" align="center"/>

接入路径可以拆成三块：App 内接入 `claw`，App 外根据使用场景选择 `mcp` 或 `cli`，后续再把高频操作沉淀成可复用流程。

这套能力支持 Android、iOS、Web、macOS、Windows、Linux 的调试构建。需要注意的是：`flutter_copilot_claw` 的接入代码是 release-safe 的，但真正连接和操作 App 依赖 VM Service，所以实际使用场景仍然发生在 debug/profile 这类可调试构建里。Web 侧截图、元素、日志等主要交互能力可用，重建热点快照为空，因为 Web 无法注入 `BuildOwner` hook。

### 第一步：Flutter App 内接入 `flutter_copilot_claw`

业务 App 侧的接入其实很轻量，核心就是初始化 Binding。

大多数业务 App 的第一步接入成本非常低，通常只需要改入口初始化。

推荐的 `main()` 写法是这样：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

void main() {
  FlutterCopilotBinding.captureLogs(() async {
    FlutterCopilotBinding.ensureInitialized();
    runApp(const MyApp());
  });
}
```

这个写法有两个好处：

- `ensureInitialized()` 在 debug/profile 下安装 Copilot Binding 并注册 VM Service 扩展；在 release 下自动退化成普通 Flutter Binding。
- `captureLogs()` 会把 `print()`、`debugPrint()` 和未捕获的异步异常收进 `get_logs`，方便 AI 在操作失败时直接拿到上下文。

如果你希望日志里出现更高信号的业务标记，可以在关键流程里加：

```dart
FlutterCopilotBinding.addLog('order:submit:tap');
FlutterCopilotBinding.addLog('order:submit:error: $error', isError: true);
```

如果业务里有大量自定义组件，还可以通过 `FlutterCopilotConfiguration` 扩展识别规则，比如告诉 Copilot 哪些自定义 Widget 算可交互、如何从自定义 Widget 提取显示文本、截图最大尺寸是多少、是否开启重建热点统计。

所以这一部分最想传达给大家的感觉不是“接入很复杂”，而是：**它真的就是从 App 入口多改几行代码开始的，并且可以逐步增强。**

### 第二步：接入 MCP or CLI

App 内接入完成之后，App 外有两条入口可以选：如果要让 Agent 操作 App，就接 MCP；如果要在终端或脚本里操作 App，就接 CLI。

<image token="EUqybe8ARoVlDFxA5jbcaOsLnFf" width="1200" height="720" align="center"/>

选择原则很简单：

- **MCP**：适合 Claude Code、Cursor 这类 Agent 做探索、排查、修复和复杂流程验证。
- **CLI**：适合开发者在终端调试、固化命令、接入本地脚本或自动化流程。

#### A. 接入 `flutter_copilot_mcp`

如果目标是让 Claude Code、Cursor 这样的 Agent 直接操作 App，就接入 `flutter_copilot_mcp`。

它的作用不是运行在 App 里，而是运行在 App 外，负责：

- 连接 VM Service
- 查找暴露 Copilot 扩展的 isolate
- 把 Flutter 运行时能力转换成 MCP 工具

安装方式可以选一种：

```bash
dart pub global activate flutter_copilot_mcp
```

或者在当前仓库调试源码：

```bash
dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

然后在 Agent 侧完成 MCP 配置。

Cursor 侧配置 `.cursor/mcp.json`：

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

Claude Code 可以用项目级配置：

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- flutter_copilot_mcp
```

当这一步完成之后，Agent 才真正知道：

- 它有哪些工具可以调
- 每个工具的名字是什么
- 应该怎么传参数

如果是在这个仓库里调试 MCP Server 自身，可以把 command 换成 `dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST`，这样日志更细。

#### B. 接入 `flutter_copilot_cli`

如果目标是终端调试、脚本化操作，或者想排查 MCP 链路问题，就接入 `flutter_copilot_cli`，日常命令叫 `fcc`。

安装方式：

```bash
npm install -g flutter_copilot_cli
fcc --version
```

它适合这些场景：

- **开发者手动调试**：不打开 AI Client，也能在终端里 `fcc tap`、`fcc get-logs`、`fcc take-screenshots`
- **后续自动化**：通过命令行把稳定动作沉淀到本地脚本或自动化流程里
- **MCP 问题排查**：当 Agent 调用失败时，可以用 `fcc doctor` 先确认 VM Service 和 Copilot 扩展是否正常
- **稳定流程沉淀**：把已经跑通的自然语言流程逐步固化成命令，便于版本管理、重试和复用

这个 CLI 会自动读取当前目录或父目录里的 `.vm_service_uri`。本地仓库里的 `scripts/flutter_run.sh` 会在启动 Flutter App 时自动捕获 VM Service URI 并写入这个文件，所以终端调试可以变成：

```bash
./scripts/flutter_run.sh -d macos
fcc doctor
fcc get-interactive-elements
fcc tap --text "点击"
fcc take-screenshots -o /tmp/flutter-copilot.png
```

### 第三步：把常用操作沉淀成可复用流程

MCP 解决的是“AI 能调用哪些工具”，Skill 解决的是“AI 应该按什么流程使用这些工具”。如果团队里经常需要连接 App、截图、交互、热重载、重启后重连，就应该把这些动作写成一份可复用的 `flutter-copilot` skill。

这个项目已经沉淀过一份示例 skill：

```yaml
name: flutter-copilot
description: 连接 Flutter Copilot MCP，支持自动读取 VM Service URI、截图、交互、热重载，以及需要重启时自动调用脚本重连
```

参考地址：

```text
https://github.com/dust365/flutter_copilot/tree/v1.0.0/.claude/skills
```

这里有一个很重要的落地经验：**工具只是能力入口，流程沉淀才是团队复用的关键。**如果没有 Skill，每次都要重新教 AI 怎么连接、怎么重启、怎么截图；如果没有后续的脚本化沉淀，稳定流程也很难被长期复用。

### 接入后的最佳实践

如果想让接入效果更稳定，重点是五件事：

1. **关键元素加 `ValueKey<String>`**
   - 这是最稳定的定位方式
   - 比按文本、按类型都更可靠

2. **优先从示例页面或核心流程开始接入**
   - 不要一上来追求覆盖整个业务 App
   - 先从登录、表单、详情页这种路径最容易体现价值

3. **把它定位成开发阶段的效率工具**
   - 它特别适合调试、验证、排查
   - 但不要一开始就把它当成对测试框架或线上监控的替代品

4. **自定义组件要补充识别规则**
   - 标准 Flutter 组件已经内置支持
   - 业务封装组件建议通过 `FlutterCopilotConfiguration` 暴露交互性和文本提取规则

5. **把高频流程沉淀下来**
   - 面向 AI 的流程可以沉淀成 skill
   - 面向终端的稳定操作后续可以沉淀到脚本和自动化流程

换句话说，这个项目最好的落地方式不是“大而全”，而是先找到一个高频、重复、适合被 AI 接管的小场景，把价值打出来。

---
