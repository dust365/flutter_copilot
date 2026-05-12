@.agents/skills/feishu_sync/cache/v3_top_and_intro.md
---

## 二、效果演示
### 场景 A：AI 帮你跑一遍 Demo 的核心交互
> 以前的做法：改完代码 → 热重载 → 自己挨个点页面、输入文本、滑动列表、触发手势 → 出问题再翻控制台日志 → 手工截图贴给同事。一次完整回归少说 5-10 分钟。
> 现在的做法：一句话告诉 AI "帮我把 Demo 的点击、输入、滚动、手势、日志走一遍"，它自己连 App、自动定位元素、依次完成操作，最后把每一步的截图和日志都交到你面前。
**[AI 一次性走完 点击 → 文本输入 → 滚动 → 手势 → 日志获取 的全流程]**
*预期效果：观众看到的不是一段事先剪好的 demo，而是 AI 真的在和 App 实时对话——每一步点完、输完、划完之后，都有截图和状态变化可以验证。全程人没动鼠标，也没切应用。*
<view type="2">

  <file token="JmDXbeHjDo7srtxevWNcOyCqnQf" name="场景1.mp4"/>

</view>


---

### 场景 B：AI 自动发现并修复一个 UI Bug
> 以前的做法：写完代码 → 自己跑一遍 App → 发现按钮颜色不对 → 改颜色 → 热重载 → 再跑一遍 → 截图对比 → 发现间距也有问题 → 再改 → 再跑 → 反复 3-5 轮才能收敛。
> 现在的做法：告诉 AI "帮我检查一下 Demo 首页的 UI 细节，发现问题直接改"，AI 自动连接 App、截图、识别偏差、修改代码、热重载、再次截图验证，直到问题消失。全程人只需要最后验收那一下。
**[AI 用 flutter_copilot skill 自动连接 → 截图发现 UI 问题 → 改代码 → hot reload → 再截图验证]**
<view type="2">

  <file token="Pp9ubrQifoXAdixo4c9cz6Wlnbg" name="场景2.mp4"/>

</view>


### 场景 C：AI*自动操作，添加自选股到下单演示*
> AI 自动点击“添加自选股”→“自选股列表”→“下单”→“确认”→截图和日志反馈现在的做法：AI 直接从运行中的 App 抓日志，拿到错误信息后立
**[AI*****自动跑流程*****]**
<view type="2">

  <file token="LTZcbtPqjotRbgxrrGYcH7uMn9b" name="场景3.mp4"/>

</view>

提示词：
<quote-container>
帮我使用flutter-copilot skills 找到自选股BILI并添加自选 ，然后下单100股，购买后在底下下单记录里面找到订单，然后去订单详情，查看这笔交易信息。
</quote-container>


---

大家可以感受到，这三个场景有一个共同点：**AI 不再只是读你的代码，它在读你的 App。**
它看到的不是源码文本，而是运行中的真实状态——页面上有什么元素、点击后发生了什么、日志里输出了什么、哪些组件在反复重建。
这就是从"代码助手"到"应用助手"的区别。
---

@.agents/skills/feishu_sync/cache/v3_section_3.md
@.agents/skills/feishu_sync/cache/v3_section_4.md
@.agents/skills/feishu_sync/cache/v3_section_5.md
@.agents/skills/feishu_sync/cache/v3_section_6.md
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
---

## 结尾
最后一句话总结：
**过去的 AI 是一个写代码的助手，Flutter Copilot 想做的，是让 AI 成为一个能看到应用、操作应用、理解应用的协作者。**
谢谢大家，欢迎会后交流。

