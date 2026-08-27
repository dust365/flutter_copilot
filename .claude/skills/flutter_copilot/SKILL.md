---
name: flutter-copilot
description: 连接 Flutter Copilot MCP，支持自动读取 VM Service URI、截图、交互、热重载，以及需要重启时自动调用脚本重连
---

# Flutter Copilot MCP 连接 Skill

自动连接 Flutter Copilot MCP，提供截图、UI 交互、热重载等能力。

## When to Use

- 需要通过 MCP 查看 Flutter 应用当前页面截图
- 需要通过 MCP 与 Flutter 应用交互（点击、滑动、输入等）
- 需要热重载后验证 UI 修改效果
- 需要重启 Flutter 应用后重新连接 MCP
- 其他 skill（如 theme_switch）需要 MCP 验收时，作为前置步骤

## Instructions

### 1. 连接 MCP

从项目根目录的 `.vm_service_uri` 文件读取 VM Service URI，然后调用 `flutter_copilot connect`：

```bash
# 读取 URI
cat .vm_service_uri
```

```
# 连接（使用读取到的实际 URI）
flutter_copilot connect uri=<读取到的URI>
```

**注意**：`.vm_service_uri` 由 `scripts/flutter_run.sh` 在 `flutter run` 启动时自动写入，通过 VS Code 的 `YouFi (Copilot)` launch 配置或终端手动运行脚本均可。

### 2. 重启并重连

当需要重启 Flutter 应用时（如全量代码变更、hot reload 不生效），执行以下步骤：

1. **断开当前连接**：调用 `flutter_copilot disconnect`
2. **终止旧进程并重启**：在终端执行脚本重启
   ```bash
   # 终止当前 flutter run 进程
   pkill -f "flutter.*run" || true
   # 等待进程退出
   sleep 3
   # 重新启动（后台运行）
   ./scripts/flutter_run.sh &
   ```
3. **等待 URI 就绪**（30 秒）：
   ```bash
   # 等待 .vm_service_uri 文件被写入（最多等 30 秒）
   for i in $(seq 1 30); do
     if [ -f .vm_service_uri ] && [ -s .vm_service_uri ]; then
       echo "URI ready: $(cat .vm_service_uri)"
       break
     fi
     sleep 1
   done
   ```
4. **重新读取 URI 并连接**：
   ```bash
   cat .vm_service_uri
   ```
   然后调用 `flutter_copilot connect` 连接新的 URI。

### 3. 常用操作

| 操作 | MCP 工具 | 说明 |
|------|----------|------|
| 截图 | `flutter_copilot take_screenshots` | 查看当前页面 |
| 点击 | `flutter_copilot tap` | 通过 text/key/type/coordinates 点击元素 |
| 滚动到 | `flutter_copilot scroll_to` | 滚动到指定文本或 key 的元素 |
| 输入文字 | `flutter_copilot enter_text` | 在输入框中输入文本 |
| 获取元素 | `flutter_copilot get_interactive_elements` | 列出所有可交互元素 |
| 热重载 | `flutter_copilot hot_reload` | 代码修改后热重载 |
| 导航 | `flutter_copilot navigate` | push/pop/replace 路由导航 |
| 获取日志 | `flutter_copilot get_logs` | 获取应用日志 |

### 4. 连接失败排查

- **文件不存在**：确认是否通过 `YouFi (Copilot)` 启动或手动运行了 `scripts/flutter_run.sh`
- **连接超时**：URI 可能已过期（应用重启后 URI 会变），重新读取 `.vm_service_uri`
- **进程未运行**：执行重启流程（见上方第 2 节）

## Key Files

- `scripts/flutter_run.sh` — 包装 `flutter run`，自动捕获 VM Service URI 写入 `.vm_service_uri`
- `.vm_service_uri` — 存储当前 VM Service WebSocket 地址（gitignore 已忽略）
- `.vscode/launch.json` — `"YouFi (Copilot)"` 配置通过 `customTool` 调用脚本
