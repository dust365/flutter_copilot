# Flutter Copilot MCP

通过 MCP 连接已以调试模式运行的 Flutter 应用，进行 UI 检测、点击/输入/滚动、手势、导航与截图/日志等操作。

## 前置条件

1. 应用已在 **Debug 模式** 下运行
2. 优先从项目根目录自动读取 `.vm_service_uri`，拿到 VM service URI 后自动调用 **connect**
3. 仅当自动发现失败时，再向用户索要 VM service URI（形如 `ws://127.0.0.1:xxxxx/ws`）

## 自动连接规则

1. 先读取项目根目录 `.vm_service_uri`
   - 该文件由 `./scripts/flutter_run.sh` 自动写入
   - VS Code / 终端只要通过该脚本启动 Flutter，通常都能自动拿到最新地址
2. 如果文件存在且内容是合法的 `ws://.../ws` URI：
   - 直接调用 **connect** 连接，不要先反问用户
3. 如果首次连接失败：
   - 重新读取一次 `.vm_service_uri`
   - 若 URI 已变化，则使用最新 URI 再重试一次 **connect**
4. 如果 `.vm_service_uri` 不存在、为空、格式不对，或重试后仍连接失败：
   - 再提示用户重新用 `./scripts/flutter_run.sh` 或 `/run-android` 启动调试
   - 仍失败时，再请用户手动提供 VM service URI

**默认行为：** 执行本命令时，先尝试自动读取 `.vm_service_uri` 并自动连接；不要一开始就向用户询问 URI。

---

## 连接管理

| 工具 | 描述 | 参数 |
|------|------|------|
| **connect** | 通过 VM service URI 连接到 Flutter 应用。优先使用从 `.vm_service_uri` 自动发现到的地址 | **uri**（必需）：VM service URI，例如 `ws://127.0.0.1:54321/ws` |
| **disconnect** | 断开当前连接。断开后需再次 **connect** 才能使用其他工具 | 无 |

---

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

1. **自动连接**：先读取项目根目录 `.vm_service_uri`，拿到 URI 后立即调用 **connect**
2. **失败兜底**：若自动连接失败，重新读取 `.vm_service_uri` 重试一次；仍失败再向用户要 URI 或引导重新启动调试
3. **探查界面**：需要时调用 **get_interactive_elements** 或 **take_screenshots**
4. **交互**：按需使用 **tap**、**enter_text**、**scroll_to** 或手势工具
5. **导航**：需要跳转页面时使用 **navigate**
6. **验证与调试**：用 **get_logs** 查看日志；用 **take_screenshots** 验证界面；用 **hot_reload** 热重载
7. **断开**：任务结束后可调用 **disconnect**

**元素匹配优先级：** 坐标 > key > text > type。优先用 **key** 更稳定。