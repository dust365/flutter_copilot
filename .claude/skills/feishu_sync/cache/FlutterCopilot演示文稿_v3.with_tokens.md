# 让 AI 真正上手操作 App

**Flutter Copilot 项目实践分享**

<image token="NXeDbyXycoVSXdxPelFcUrCvnAh" width="1200" height="675" align="center"/>

> 演讲时长：约 60 分钟（含 QA） | 受众：产品、研发、Flutter、后端、设计

---

## 一、开场：我为什么要做这件事

大家好，今天想和大家分享一个我最近做的开源项目，叫 Flutter Copilot。

我做它的起点其实很简单。去年看到一些 AI 操作浏览器的案例时，我当时就在想：既然 AI 已经可以打开页面、点按钮、填表单、截图、读日志，**为什么 Flutter 不行？**

因为我们今天说 AI 提效，很多时候还停留在代码层面。但真正耗时间的，往往是写完代码之后的验证和排查：

- 要自己点页面确认结果
- 要自己复现问题、截图录屏
- 要自己获取日志贴给 AI
- 要再把上下文转述给 AI
- 还要自己一点点把流程重新操作一遍

<image token="WpiibsIhoowi57xUzaQcTYdRn9J" width="1200" height="675" align="center"/>

问题不是 AI 写代码不够快，而是它**看不到**你的 App。

所以我想做的事情很明确：给 AI 装一双眼睛和一双手，让它不只是帮我写代码，还能直接进入一个运行中的 Flutter App，去看、去点、去验证。

Flutter Copilot 就是从这里开始的。

**一句话说清楚：它是一个桥接层，让 Claude Code、Cursor 这样的 AI，能够直接连接并操作运行中的 Flutter 应用。**

接下来我先让大家看看它实际能做什么，然后再聊技术实现。

---

## 二、效果演示

### 场景 A：AI 帮你跑一遍 Demo 的核心交互

> 以前的做法：改完代码 → 热重载 → 自己挨个点页面、输入文本、滑动列表、触发手势 → 出问题再翻控制台日志 → 手工截图贴给同事。一次完整回归少说 5-10 分钟。
>
> 现在的做法：一句话告诉 AI "帮我把 Demo 的点击、输入、滚动、手势、日志走一遍"，它自己连 App、自动定位元素、依次完成操作，最后把每一步的截图和日志都交到你面前。

**[演示视频：AI 一次性走完 点击 → 文本输入 → 滚动 → 手势 → 日志获取 的全流程]**

_预期效果：观众看到的不是一段事先剪好的 demo，而是 AI 真的在和 App 实时对话——每一步点完、输完、划完之后，都有截图和状态变化可以验证。全程人没动鼠标，也没切应用。_

<view type="2">
  <file token="JmDXbeHjDo7srtxevWNcOyCqnQf" name="场景1.mp4"/>
</view>

---

### 场景 B：AI 自动发现并修复一个 UI Bug

> 以前的做法：写完代码 → 自己跑一遍 App → 发现按钮颜色不对 → 改颜色 → 热重载 → 再跑一遍 → 截图对比 → 发现间距也有问题 → 再改 → 再跑 → 反复 3-5 轮才能收敛。
>
> 现在的做法：告诉 AI "帮我检查一下 Demo 首页的 UI 细节，发现问题直接改"，AI 自动连接 App、截图、识别偏差、修改代码、热重载、再次截图验证，直到问题消失。全程人只需要最后验收那一下。

**[演示视频：AI 用 flutter_copilot skill 自动连接 → 截图发现 UI 问题 → 改代码 → hot reload → 再截图验证]**

<view type="2">
  <file token="Pp9ubrQifoXAdixo4c9cz6Wlnbg" name="场景2.mp4"/>
</view>

### 场景 C：AI 自动跑一段真实业务流程

> 以前的做法：业务同学或测试同学给一个流程描述，开发需要自己打开 App，找到入口，输入条件，点到目标页面，再把截图、日志、结果整理出来。
>
> 现在的做法：把流程直接交给 AI。比如“找到自选股 BILI 并添加自选，然后下单 100 股，购买后在下单记录里找到订单，再进入订单详情查看交易信息”。AI 会按当前页面结构逐步定位元素、执行点击和输入、截图确认结果，并在失败时把日志一起带回来。

**[演示视频：AI 根据自然语言提示完成 添加自选股 → 下单 → 查订单 → 看详情 的完整流程]**

<view type="2">
  <file token="LTZcbtPqjotRbgxrrGYcH7uMn9b" name="场景3.mp4"/>
</view>

这个场景不是单个按钮的自动化，而是一个跨页面、带业务语义的流程验证。它最能说明 Flutter Copilot 的价值不是“能点一下”，而是能把多个运行时动作串成一个可复用的工作流。

这里的输入不是脚本命令，而是一句业务语言：

> 帮我使用 flutter-copilot skills 找到自选股 BILI 并添加自选，然后下单 100 股，购买后在底下下单记录里面找到订单，然后去订单详情，查看这笔交易信息。

---

大家可以感受到，这三个场景有一个共同点：**AI 不再只是读你的代码，它在读你的 App。**

它看到的不是源码文本，而是运行中的真实状态——页面上有什么元素、点击后发生了什么、日志里输出了什么、哪些组件在反复重建。

这就是从"代码助手"到"应用助手"的区别。

---

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

## 四、接入指南

前面讲了这么多，大家最自然的一个问题就是：**这个东西到底怎么接？复杂不复杂？**

我把它总结成三步，核心原则就是：**App 内挂能力，App 外按场景选择 MCP 或 CLI，再把高频流程沉淀下来。**

<image token="OXFhbPQ4aoazYSxmhbcceCEsnzg" width="1200" height="736" align="center"/>

接入路径可以拆成三块：App 内接入 `claw`，App 外根据使用场景选择 `mcp` 或 `cli`，后续再把高频操作沉淀成可复用流程。

#### 跨平台支持

**Flutter 跑得到的地方，Flutter Copilot 就能跑。**

<image token="M6bXbkQTootBKvx2nc0cwsaLnzb" width="1200" height="624" align="center"/>

唯一一个边界要记住：claw 接入代码是 release-safe 的，但操作能力依赖 VM Service，所以连接和驱动 App 只发生在 debug / profile 构建里 —— release 下初始化会自动退化成普通 `WidgetsFlutterBinding.ensureInitialized()`，不注册扩展、不占开销。

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

<image token="Yo1obrOg3ovJOgxKpsdck04in7e" width="1200" height="608" align="center"/>

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

## 五、接入前后数据对比：它到底带来了多少提效

我觉得一场分享如果只讲“能做什么”，说服力还不够，最好还要回答一个问题：

**接入前和接入后，到底差了多少？**

这一部分我先给一个你后续可以替换真实数据的框架，重点是把“提效”讲具体，而不是只讲感觉。

### 1. 可以从这几个指标去看

建议重点看四类指标：

- **单次验证耗时**：一次页面验证从开始到拿到结果需要多久
- **问题定位耗时**：从发现异常到拿到有效线索需要多久
- **人工参与次数**：一个流程里需要人工点几次、切换几次工具
- **反馈闭环时长**：产品 / 测试 / 开发从提出问题到确认结果需要多久

### 2. 接入前后对比

<image token="UYO7bkIjxodtMLxvO8Dcao4CnDb" width="1200" height="720" align="center"/>

> 下面这组数字你后面可以替换成真实数据，我先帮你把表达方式搭好。

| 指标                 | 接入前                             | 接入后                          | 预期变化         |
| -------------------- | ---------------------------------- | ------------------------------- | ---------------- |
| 单次表单验证耗时     | 2~3 分钟                           | 20~40 秒                        | 缩短 60%~80%     |
| 一次日志排查耗时     | 5~10 分钟                          | 1~3 分钟                        | 缩短 50%~70%     |
| 问题复现准备动作     | 手工打开页面、输入、截图、复制日志 | Agent 自动执行 + 自动拿日志截图 | 大幅减少人工操作 |
| 产品确认一个核心流程 | 需要开发或测试配合回放             | Agent 可直接执行并反馈结果      | 反馈链路明显缩短 |
| 重绘热点定位         | 手工看 DevTools + 自己分析         | 一次快照 + Agent 辅助解释       | 分析门槛下降     |

**综合来看：多角色协作效率整体提升 30%~40%。**

### 3. 欢迎 Flutter 技术栈团队试用

如果你的团队正在使用 Flutter，并且日常开发里有大量页面验证、流程回归、日志排查、UI 调试工作，Flutter Copilot 很适合从一个小场景开始试用。

不需要一开始覆盖整个 App，可以先选一个高频、重复、结果容易验证的流程，比如登录、表单提交、详情页确认、核心业务链路回放。只要这个点跑通，后面就可以逐步把经验沉淀成团队自己的 Skill、MCP 配置或 CLI 命令。

### 4. 全链路解决方案，开发闭环

<image token="N89tbtc4SokfKlxdF3zcdh7bnYg" width="1200" height="840" align="center"/>

Flutter Copilot 带来的不只是“操作更自动化”，而是让“代码生成 → 运行验证 → 页面观察 → 问题定位 → 结果反馈”第一次变成了一条可以被 AI 串起来的完整闭环。

---

## 六、价值升华

前面我讲了这个项目怎么做、能做什么、能带来多少提效。最后我想再往上收一层，讲讲这件事真正值得我们关注的价值到底是什么。

### 1. AI 的价值，不只是写代码，而是进入工作流

我觉得这件事最重要的，不是“我做了一个 Flutter MCP”，而是它背后代表了一种新的方法论：

**不要只让 AI 参与写代码，而要让 AI 进入完整工作流。**

过去我们的研发流程往往是割裂的：人写代码、人跑应用、人点页面、人看日志、人描述问题，AI 再基于这些文字给建议。

而 Flutter Copilot 做的一件事，就是把这条链路重新串起来：

**代码生成 → 运行验证 → 页面观察 → 问题定位 → 结果反馈**

<image token="ZIonbpYqZornrHxCPzTcZhFmnLe" width="1200" height="760" align="center"/>

左边是传统形态的 AI：”代码助手”只在第一环发挥，剩下四环都靠人手工补。右边是 Flutter Copilot 形态：”应用助手”把 5 环连成闭环，AI 全程在场。

一旦这条链路打通，AI 就不再只是一个”回答问题的助手”，而开始变成一个真正参与执行的协作者。

### 2. 真正适合 AI 切入的，是高频、重复、可验证的问题

真正能在工作里落地的，往往不是最炫的能力，而是那些最具体的问题。

比如流程验证、日志排查、UI 对比、结果确认，这些事情都有几个共同点：高频、重复，而且结果可验证。

所以让 AI 赋能，不是先问“AI 能做什么”，而是先问：**我们工作里最值得被 AI 接管的重复动作是什么。**

### 3. 给大家真正的启发：从自己的工作场景出发

<image token="IixabUsTPoS54SxwAaOcekaynJg" width="1200" height="1011" align="center"/>

如果回头看这个项目，它并不是从“我要做个平台”开始的，而是从一句很具体的话开始的：

**这件事为什么还要我手工做？**

很多有价值的工具，往往就是这样长出来的：先发现真实痛点，再把高频动作沉淀成可复用的能力，最后慢慢长成自己的工作流。

如果今天这场分享最后只能让大家带走一件事，我希望不是“Flutter Copilot 这个项目挺有意思”，而是：

**你完全可以基于自己的工作场景，去探索属于你自己的 AI 工作流。**

不一定非要是 Flutter，也不一定非要从一个完整项目开始。

你可以从自己的痛点出发，反过来想：

- 有没有一件事是你每天都在重复做的？
- 有没有一类问题总要靠你手工排查、手工验证、手工整理？
- 有没有一些流程，本来很机械，却一直占着你的注意力？

如果有，那你就可以开始做四件事：

- **把流程沉淀成 skills**：把常用步骤变成可复用的操作模板
- **把能力封装成 MCP**：把原来只能手工完成的动作，变成 AI 可调用的工具
- **把经验固化成 CLI 工具**：把团队里重复出现的问题，做成自己随时可用的小工具
- **把上下文蒸馏成自己的 AI 记忆**：把你的习惯、方法、判断标准慢慢沉淀下来，最终发展成属于每个人自己的“claw bot”和“Hermes”

### 4. 最后的落点：不是做一个酷项目，而是解决真实问题

这件事最现实的价值，不是“做一个很酷的 AI 项目”，而是：

**解决自己的真实痛点，解放双手，把注意力从重复劳动里拿回来，放到更重要的问题上。**

比如：

- 更重要的架构判断
- 更重要的产品决策
- 更重要的异常分析
- 更重要的跨团队协作

所以我想表达的不是“大家都来用我这个项目”，而是：

**希望这个项目能给大家一个启发：你也可以为自己的工作流，做一套自己的 skills、自己的 MCP、自己的工具链。**

当你开始这样做的时候，AI 才真正不是一个聊天窗口，而是开始变成你工作系统里的一部分。

### 项目地址

| 资源                                   | 链接                                          |
| -------------------------------------- | --------------------------------------------- |
| **GitHub（源码 + 文档）**              | https://github.com/dust365/flutter_copilot       |
| **flutter_copilot_mcp**（MCP Server）  | https://pub.dev/packages/flutter_copilot_mcp     |
| **flutter_copilot_claw**（Flutter 端） | https://pub.dev/packages/flutter_copilot_claw    |
| **flutter_copilot_cli / fcc**（CLI）   | https://www.npmjs.com/package/flutter_copilot_cli |

`flutter_copilot_mcp` 和 `flutter_copilot_claw` 已发布到 pub.dev；`flutter_copilot_cli` 已发布到 npm，可以直接安装使用。
欢迎 Star、提 Issue、提 PR，一起把这个东西做得更好。

---

## 七、QA

<image token="Ik4qbmpNSozrA1x8r4sc9TXTnsg" width="1200" height="720" align="center"/>

最后留一点时间交流。前面讲的是一个具体项目，但真正值得讨论的是：这类能力怎么放进每个团队自己的研发流程里。

可以重点围绕这几类问题展开：

- **接入成本**：老项目怎么接？会不会影响 release？哪些页面最适合先试？
- **能力边界**：Web、复杂手势、重建快照、稳定定位分别有哪些限制？
- **工程化落地**：MCP 和 CLI 怎么选？哪些流程适合沉淀成 Skill？
- **场景延展**：除了 Flutter，类似思路能不能迁移到其他技术栈？
- **团队协作**：产品、测试、研发各自能怎样利用运行时可操作能力？

如果现场问题不多，可以反过来问大家一个问题：

> 你们现在工作里，有没有哪一类验证、排查或整理动作，是每天都在重复做，但一直没人把它工具化的？

---

## 附录

### 附录 A：MCP 官方资源与开发指引

官方资源：

- **官网**：https://modelcontextprotocol.io/
- **快速开始**：https://modelcontextprotocol.io/quickstart
- **协议规范**：https://spec.modelcontextprotocol.io/specification/

各语言 SDK / 开发指引：

- **TypeScript**：https://github.com/modelcontextprotocol/typescript-sdk
- **Python**：https://github.com/modelcontextprotocol/python-sdk
- **Java**：参考协议规范，用 JSON-RPC 库自行实现
- **Go / Rust / 其他**：只要实现 JSON-RPC over stdio + MCP 格式即可

### 附录 B：本地源码定位

如果现场有人想继续看实现，可以直接从这几处开始：

| 问题 | 入口文件 |
| ---- | -------- |
| Flutter 端如何注册 VM Service 扩展 | `packages/flutter_copilot_claw/lib/src/binding/flutter_copilot_binding.dart` |
| MCP Server 如何注册 15 个工具 | `packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_context.dart` |
| MCP Server 如何连接 VM Service 并调用扩展 | `packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_connector.dart` |
| 元素定位 Key / Text / Type / Coordinates 如何匹配 | `packages/flutter_copilot_claw/lib/src/services/widget_matcher.dart` |
| CLI 如何直连同一套扩展 | `packages/flutter_copilot_cli/src/vm/connector.ts` |
| 本地自动捕获 VM Service URI | `scripts/flutter_run.sh` |

---

## 结尾

最后一句话总结：

**过去的 AI 是一个写代码的助手，Flutter Copilot 想做的，是让 AI 成为一个能看到应用、操作应用、理解应用的协作者。**

谢谢大家，欢迎会后交流。
