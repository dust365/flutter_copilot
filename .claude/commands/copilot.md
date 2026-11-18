# Flutter Copilot MCP

通过 MCP 连接已以调试模式运行的 Flutter 应用，进行 UI 检测、点击/输入/滚动、手势、导航与截图/日志等操作。

### 1. 发现或启动 App

1. 调用 `list_apps(directory)`，其中 `directory` 是 Flutter 工程目录。本仓库用 `example` 的绝对路径。DTD 会自动发现已有 debug 会话。
2. 没有合适的会话时调用 `ensure_apps(directory)`。如果返回 `selection_required`，请用户从候选中选一台或多台，再传入 `deviceIds` 或 `appIds`。
3. 有 `operationId` 时轮询 `operation_status`，直到 `state=completed`。启动结果按设备返回；一台失败时可继续使用其他已连接的设备。
4. 截图、点击等操作传 `app` 为所选会话 ID。重新运行后若原 ID 不可用，重新列出会话并确认目标。只有自动发现不可用时才用 `connect(uri)` 显式连接。

### 2. 会话生命周期

MCP 和 `fcc` 共用会话，退出任一客户端不会停止 App。`disconnect` 只断开连接；`stop_app` 关闭本工具启动的 App，`detach_app` 结束其调试会话但保留 App。外部 `flutter run` 或 IDE 会话需由原启动方停止。

## UI 元素检测

| 工具 | 描述 | 参数 |
|------|------|------|
| **get_interactive_elements** | 返回当前屏幕上所有可交互 UI 元素列表（按钮、输入框等） | 无 |

**使用建议：** 在执行 tap / enter_text / scroll_to 等前，可先调用此工具确认目标元素的 key 或 text。

---

## 用户交互

| 工具 | 描述 | 参数 |
|------|------|------|
| **tap** | 点击匹配条件的元素。可通过 key、文本、类型或坐标匹配；**优先使用 key** | **key**、**text**、**type**、**coordinates**（可选） |
| **enter_text** | 在匹配 **key** 的文本框中输入文本 | **input**（必需）、**key**（必需） |
| **scroll_to** | 滚动视图直到匹配 key 或 text 的元素可见 | **key**、**text**（可选） |

---

## 手势操作

| 工具 | 描述 | 参数 |
|------|------|------|
| **flutter_copilot_drag** | 在元素上模拟拖拽 | **key**、**deltaX**、**deltaY**、**from**、**to**（可选） |
| **swipe** | 在元素上模拟滑动手势 | **direction**（必需）：`left` / `right` / `up` / `down` |
| **long_press** | 在元素上模拟长按 | **duration**（可选，毫秒，默认 500） |
| **double_tap** | 在元素上模拟双击 | **key**、**text**、**type**、**coordinates**（可选） |

---

## 导航控制

| 工具 | 描述 | 参数 |
|------|------|------|
| **navigate** | 控制应用导航 | **action**（必需）：`push` / `pop` / `replace` / `pushReplacement` / `popUntil` |

---

## 调试与监控

| 工具 | 描述 | 参数 |
|------|------|------|
| **get_logs** | 获取自连接或上次获取以来收集的日志 | 无 |
| **get_rebuild_snapshot** | 获取重绘快照与重绘热点排行 | **topLimit**（可选，默认 20） |
| **take_screenshots** | 捕获当前所有视图的截图，返回 base64 编码的 PNG | 无 |
| **hot_reload** | 执行热重载，保留应用状态 | 无 |

---

## 建议执行流程

1. **自动发现**：先用 `list_apps`，再按会话 ID 操作。
2. **未运行**：用 `ensure_apps`；遇到多个候选时由用户选择。
3. **探查界面**：需要时调用 **get_interactive_elements** 或 **take_screenshots**
4. **交互**：按需使用 **tap**、**enter_text**、**scroll_to** 或手势工具
5. **导航**：需要跳转页面时使用 **navigate**
6. **验证与调试**：用 **get_logs** 查看日志；用 **take_screenshots** 验证界面；用 **hot_reload** 热重载
7. **断开**：任务结束后可调用 **disconnect**

**元素匹配优先级：** 坐标 > key > text > type。优先用 **key** 更稳定。
