## 三、技术揭秘

效果看完了，接下来聊聊它是怎么做到的。我尽量讲得所有人都能听懂。

### 1. 整体架构：三层，各管一件事

<image token="UcFJbjxKHoiAuqxnhrRc2Epun2b" width="1200" height="784" align="center"/>

简单讲就是三句话：

- **最上层**：AI 决定要做什么（比如"点击登录按钮"、"跑一遍下单流程"）
- **中间层**：`flutter_copilot_mcp` 把 AI 的意图翻译成 Flutter 能理解的指令
- **最下层**：`flutter_copilot_claw` 在 App 内注册运行时能力，真正执行操作并把结果返回

如果拿大家熟悉的概念类比：中间层就像一个 **API 网关**，上面对接 AI 客户端，下面对接 Flutter 运行时。

### 2. 两个关键协议

这里面有两个协议比较关键，我分开讲。

#### 2.1 MCP（Model Context Protocol）

**先讲 MCP 解决了什么。** 让 AI 调用外部工具不是新问题，但每家 AI 客户端原本都有自己的私有调用方式：Claude 有 tool use、OpenAI 有 function calling、国内各家又是另一套协议。如果你做了一个工具想给所有 Agent 用，就得为每家写一套桩代码——这和早期 Web 服务百花齐放的私有 RPC 是一个味道。

MCP（Model Context Protocol）干的就是把这件事**标准化**：它定义了一份开放协议，让 AI 客户端（Host）、协议层（Client）、工具服务（Server）三方按统一约定握手、调用、返回。简单说，它在 AI 世界里扮演的角色，和 **RESTful + OpenAPI** 在 Web 世界扮演的角色完全一样。

它统一了三件事：

- **Discover（发现）**：Agent 启动时自动列出 Server 提供的工具、参数 schema、说明文字，不用人肉配置
- **Invoke（调用）**：用统一的 JSON-RPC 形式调用工具，底层走 stdio 还是 SSE 对调用方透明
- **Stream（流式）**：长任务可以边执行边把进度返回，Agent 不用一直阻塞等待

<image token="H9DibBXSeouRdvxlP2qc6vjKnFx" width="1200" height="656" align="center"/>

**对 Flutter Copilot 的意义**：我们只写一个 `flutter_copilot_mcp`，Claude Code、Cursor、Continue 以及任何遵循 MCP 的 Agent 都能直接接入，不用为每家客户端单独适配。如果你自己的技术栈也想接 AI 能力，把工具包成 MCP Server 同样能吃到这层红利。

源码入口在 `packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_context.dart`，核心是一条 `注册工具 → 处理调用 → 经 VM Service 执行 → 返回结果` 的流水线。

#### 2.2 VM Service

**先讲它解决了什么。** App 外面的进程要跟 App 里面的运行时讲话，如果没有官方入口，你就只能在"野路子"里挑：抓屏 + OCR、Accessibility API、自己起 socket……这些要么慢、要么脆弱、要么受系统权限限制，更不要说做长期维护。

VM Service 是 Dart VM 在 **Debug / Profile 模式**下默认开启的官方调试服务。我们平时用的**热重载、DevTools、IDE 断点调试**，底层走的全是它——也就是说，这是 Flutter 团队自己维护、有版本承诺、配套工具链一直在更新的入口。选它接入意味着稳定性直接继承自 Flutter 工具链本身。

它给外部进程提供两类核心能力：

- **观察类**：读取 isolate 状态、Widget 树、性能数据、运行日志
- **干预类**：触发热重载、调用 **Service Extension**（开发者自己在 App 里注册的扩展点）

最后这个 Service Extension 是 Flutter Copilot 的关键齿轮。`flutter_copilot_claw` 在 App 启动时，通过 `registerExtension('ext.flutter.copilot.tap', ...)` 这类调用，把点击、输入、截图、拿日志等能力注册成自定义 Service Extension；MCP Server 拿到一个 VM Service URI 之后，就能像调 RPC 一样调这些扩展。

<image token="WhbmburS8otqUExXgUsce17nnuc" width="1200" height="784" align="center"/>

一句话：**Flutter Copilot 不是绕过 Flutter 去 hack App，而是站在 Flutter 自己的 Debug 通道上正式接入运行时能力。**

Flutter Copilot 这一套能力最终对外体现为 15 个 MCP 工具，覆盖连接、观察、交互、导航、诊断等几个核心方向；底层则通过 App 内部能力和 VM Service 调用链路把这些动作真正执行起来。

### 3. 一条真实的调用链路

**所以整个链路是这样的：AI 说话 → MCP 翻译 → VM Service 传达 → Flutter App 执行。**

<image token="LUTvbLvKAoInshxLgGecoOL8n3f" width="1200" height="864" align="center"/>

这条链路把前面讲到的 MCP 和 VM Service 连了起来：MCP 负责标准化工具调用，VM Service 负责把调用送进正在运行的 Flutter App。

这里最关键的一点是：**AI 不是在模拟"点击屏幕坐标 (200, 350)"，而是在 Flutter 的 Widget 树里找到语义化的目标元素，然后派发手势。**

打个比方：坐标点击就像闭着眼睛用手指戳屏幕，界面稍微变一下就点错了；而 Flutter Copilot 是拿着遥控器，按的是"登录按钮"这个名字，不管按钮移到哪里都能点中。

### 4. 它到底有多少能力

给大家看一张总览图：

<image token="R706bIawqoRf57xJwy8cVOL9ngc" width="1200" height="824" align="center"/>

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

### 5. 还有一条终端入口：fcc CLI

前面讲的都是 AI Agent 通过 MCP 接入 Flutter Copilot。但同一套能力还有第二条入口 —— 直接在终端里用，这就是 `flutter_copilot_cli`，日常命令叫 `fcc`。

它和 MCP 共用同一套 VM Service 扩展（参见 3.3 节调用链路图，左右两条 lane 最终汇聚到同一个 callServiceExtension），区别只是入口形式：

- **MCP 入口**：供 Claude Code、Cursor 这类 Agent 调用，适合自然语言探索
- **CLI 入口**：供工程师 / 脚本 / CI 直接调用，适合终端调试和稳定流程沉淀

<image token="IoohbuS3NoB8RYxAZ8vcAMi0nWe" width="1200" height="720" align="center"/>

它最常被用在四个地方：

- **手动调试**：不想打开 AI Client，直接在终端 `fcc tap`、`fcc get-logs`、`fcc take-screenshots`
- **链路诊断**：Agent 调用失败时 `fcc doctor` 一键确认是 VM Service 还是 Copilot 扩展的问题
- **脚本沉淀**：把 AI 跑通的流程写成 shell / yaml，放进 CI 或本地 task，可重试、可版本化
- **团队复用**：没装 AI Client 的同学(QA / 产品)拉一份脚本也能跑，门槛只是装一个 npm 包

具体安装和参数细节放在第四节「接入指南」里讲。

---
