## 三、技术揭秘

效果看完了，接下来聊聊它是怎么做到的。我尽量讲得所有人都能听懂。

### 1. 整体架构：三层，各管一件事

<image token="Ubz1bkBzUo9lG9xYYoJctVBynDf" width="1200" height="784" align="center"/>

简单讲就是三句话：

- **最上层**：AI 决定要做什么（比如"点击登录按钮"、"跑一遍下单流程"）
- **中间层**：`flutter_copilot_mcp` 把 AI 的意图翻译成 Flutter 能理解的指令
- **最下层**：`flutter_copilot_claw` 在 App 内注册运行时能力，真正执行操作并把结果返回

如果拿大家熟悉的概念类比：中间层就像一个 **API 网关**，上面对接 AI 客户端，下面对接 Flutter 运行时。

### 2. 两个关键协议

这里面有两个协议比较关键，我分开讲。

#### 2.1 MCP（Model Context Protocol）

MCP 是 AI 和工具之间的标准协议。

你可以把它理解成：AI 世界的 RESTful API 规范。它定义了“AI 怎么发现工具、怎么调用工具、怎么拿到结果”。有了这层标准，不管是 Claude Code 还是 Cursor，都能用同一套接口操作 Flutter App。

如果你想给自己的技术栈也接一个类似的 AI 能力，MCP 协议也是开放的。

<image token="QEUSb8n2ZokegyxeWgWcyJg7nTd" width="1200" height="720" align="center"/>

我们这个项目的 Dart MCP Server 源码在：

- `packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_context.dart`

核心思路就是：注册工具 → 处理调用 → 通过 VM Service 执行 → 返回结果。

#### 2.2 VM Service

VM Service 是 Dart/Flutter 在 Debug 模式下暴露的运行时调试服务。

我们平时用的热重载、DevTools 调试，底层都是 VM Service。它提供了一个正式的入口，让 App 外部的进程可以和运行中的 App 通信。

<image token="PbhFbu0aGoURrFxmkcOcVT0Tnde" width="1200" height="720" align="center"/>

Flutter Copilot 这一套能力最终对外体现为 15 个 MCP 工具，覆盖连接、观察、交互、导航、诊断等几个核心方向；底层则通过 App 内部能力和 VM Service 调用链路把这些动作真正执行起来。

### 3. 一条真实的调用链路

**所以整个链路是这样的：AI 说话 → MCP 翻译 → VM Service 传达 → Flutter App 执行。**

<image token="INefbuNjso2TOCxY9YFcIpDUnjb" width="1200" height="864" align="center"/>

这条链路把前面讲到的 MCP 和 VM Service 连了起来：MCP 负责标准化工具调用，VM Service 负责把调用送进正在运行的 Flutter App。

这里最关键的一点是：**AI 不是在模拟"点击屏幕坐标 (200, 350)"，而是在 Flutter 的 Widget 树里找到语义化的目标元素，然后派发手势。**

打个比方：坐标点击就像闭着眼睛用手指戳屏幕，界面稍微变一下就点错了；而 Flutter Copilot 是拿着遥控器，按的是"登录按钮"这个名字，不管按钮移到哪里都能点中。

### 4. 它到底有多少能力

给大家看一张总览图：

<image token="YO9QbCj5NoS2uQxm5Z3c1eSbnJd" width="1200" height="784" align="center"/>

这套能力最终对外体现为 15 个 MCP 工具，可以按连接、观察、交互、导航、诊断五类理解。

支持 4 类元素定位方式：**Key（最稳定）、文本内容、Widget 类型、屏幕坐标**。其中 `ValueKey<String>` 是最推荐的方式；坐标是兜底方案，适合快速验证，但不适合作为长期稳定脚本的主路径。

如果按用途拆开，结构是这样的：

| 类别 | 工具 | 解决的问题 |
| ---- | ---- | ---------- |
| 连接 | `connect` / `disconnect` | 建立或断开和运行中 App 的 VM Service 连接 |
| 观察 | `get_interactive_elements` / `take_screenshots` | 看当前页面有哪些可操作元素，以及页面真实长什么样 |
| 交互 | `tap` / `enter_text` / `scroll_to` / `flutter_copilot_drag` / `swipe` / `long_press` / `double_tap` | 完成点击、输入、滚动、拖拽、滑动、长按、双击等人工操作 |
| 诊断 | `get_logs` / `get_rebuild_snapshot` | 获取运行日志和组件重建热点 |
| 开发闭环 | `hot_reload` / `navigate` | 修改代码后热重载，或直接控制路由跳转 |

这些能力组合起来，就能覆盖"观察 → 操作 → 诊断"一条完整的运行时协作链路。

---
