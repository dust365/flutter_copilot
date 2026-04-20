# Claude Code 调试本地 MCP 教程

本文说明如何在 **Claude Code** 中调试本仓库的本地 MCP 服务 `flutter_copilot_mcp`。

> 适用仓库：`flutter_copilot`
> 
> MCP 服务入口：`packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart`

---

## 1. 先明确：Claude Code 不读取 `.cursor/mcp.json`

本仓库已经有 Cursor 配置文件：

- `.cursor/mcp.json`

但 **Claude Code 不会读取这个文件**。在 Claude Code 里：

- 项目级 MCP 配置使用 **`.mcp.json`**
- Claude Code 的项目设置使用 **`.claude/settings.json`**

所以：

- `.cursor/mcp.json` 是给 Cursor 用的
- `.mcp.json` 是给 Claude Code 用的
- `.claude/settings.json` 不是用来声明 MCP server 的

---

## 2. 推荐做法：用 `claude mcp add` 注册项目级 MCP

推荐在**仓库根目录**执行，让 Claude Code 自动写入项目级 `.mcp.json`。

### 最小可用命令

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

如果相对路径启动失败，再改成绝对路径：

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run <repo-root>/packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

其中 `<repo-root>` 替换成你本机上的仓库绝对路径。

### 为什么不要直接照搬 Cursor 配置

Cursor 里的写法是：

```json
{
  "mcpServers": {
    "flutter_copilot": {
      "type": "stdio",
      "command": "dart run ${workspaceFolder}/packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST"
    }
  }
}
```

这里的 `${workspaceFolder}` 是 Cursor 的变量，**Claude Code 里不能直接依赖它**。

---

## 3. 如何确认 Claude Code 已经识别到这个 MCP

注册后，先做三步检查：

### 3.1 列出 MCP 服务

```bash
claude mcp list
```

### 3.2 查看单个服务详情

```bash
claude mcp get flutter_copilot_mcp
```

### 3.3 在 Claude Code 会话里检查

在 Claude Code 交互界面里：

- 输入 `/mcp` 查看 MCP server 状态
- 输入 `/doctor` 检查 MCP 配置问题

如果状态是：

- `connected` / 可用：说明注册成功
- `pending`：通常是启动中或握手未完成
- `failed`：通常是命令错误、路径错误或 server 启动异常

---

## 4. 推荐的调试启动方式

为了方便排查，建议把日志级别开到 `FINEST`。本仓库的 MCP 入口支持：

- `-l FINEST`：最详细日志级别
- `--log-file <path>`：把日志写到文件

### 推荐命令

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST --log-file ./.claude/logs/flutter_copilot_mcp.log
```

如果你希望路径更稳妥，可以把 `--log-file` 也改成绝对路径。

这样排查时可以同时看两类日志：

1. Claude Code 的 debug 日志
2. MCP server 自己的日志文件

---

## 5. Claude Code 里怎么查看 stdio MCP 的错误

本地 stdio MCP 最常见的问题是：**进程已经启动，但握手失败；或者命令根本没有成功启动。**

这时优先看：

```bash
~/.claude/debug/<session-id>.txt
```

这个文件里通常能看到：

- server 启动失败
- stdio 握手失败
- JSON-RPC 解析错误
- stderr 输出

如果你给 `flutter_copilot_mcp` 加了 `--log-file`，还要同时看你指定的日志文件，例如：

```bash
./.claude/logs/flutter_copilot_mcp.log
```

---

## 6. 手动验证 server 本身能不能启动

在怀疑 Claude Code 配置有问题之前，先单独跑一遍 server 命令，确认服务本身能启动。

### 手动运行

```bash
dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST
```

如果这一步都失败，就先不要排查 Claude Code，先修 server 本身。

优先检查：

- 依赖是否安装：`dart pub get`
- 入口路径是否正确
- 当前工作目录是否是仓库根目录
- Dart/Flutter 环境是否正常

---

## 7. 调试本仓库的完整链路

这个仓库的真实调试链路通常是：

1. 启动 Flutter 示例应用
2. 让 Claude Code 连接 `flutter_copilot_mcp`
3. 再用 MCP 工具连接 VM Service URI
4. 调用 `connect`、`get_interactive_elements`、`tap` 等工具

### 7.1 先启动示例应用

本仓库常用的是：

```bash
cd example && flutter run
```

如果你使用 VS Code 的 [`.vscode/launch.json`](../.vscode/launch.json) 中的 `Flutter (Copilot)`，也可以通过 [scripts/flutter_run.sh](../scripts/flutter_run.sh) 启动。

### 7.2 获取 VM Service URI

应用启动后，从终端输出中复制 `ws://.../ws`。

本仓库的启动脚本还会把 URI 写到：

```bash
.vm_service_uri
```

### 7.3 在 Claude Code 中使用 MCP

等 `flutter_copilot_mcp` 这个 MCP server 正常后，Claude Code 才能调用这些工具：

- `connect`
- `disconnect`
- `get_interactive_elements`
- `tap`
- `enter_text`
- `scroll_to`
- `get_logs`
- `take_screenshots`
- `hot_reload`

如果 server 注册成功但工具不可用，通常要检查：

- MCP server 是否真的完成初始化
- 是否已经连接到目标 Flutter 应用的 VM Service
- Flutter 应用是否调用了 `FlutterCopilotBinding.ensureInitialized()` 或 `runAppWithConfig()`

---

## 8. 常见问题排查顺序

建议按下面的顺序排查，不要一开始就怀疑 Flutter 侧逻辑。

### 问题 1：Claude Code 里看不到 MCP

优先检查：

1. 有没有执行过 `claude mcp add --scope project ...`
2. 仓库根目录是否生成了 `.mcp.json`
3. `/mcp` 是否显示 `failed`
4. `claude mcp list` 里是否存在同名 server 冲突

### 问题 2：server 状态是 failed

优先检查：

1. 路径是否正确
2. 是否错误使用了 `${workspaceFolder}`
3. `dart run ...` 手动执行是否成功
4. `~/.claude/debug/<session-id>.txt` 中的 stderr

### 问题 3：server 正常，但工具调用失败

优先检查：

1. Flutter 应用是否在 Debug/Profile 模式运行
2. VM Service URI 是否正确
3. 应用是否初始化了 `FlutterCopilotBinding`
4. MCP server 日志里是否有 `Not connected to any app`
5. VM 扩展是否注册成功

### 问题 4：重名或多 scope 冲突

如果同一个 `flutter_copilot_mcp` 在多个 scope 被定义，容易出现你以为改了项目配置，实际 Claude Code 读的是另一个配置。

建议：

- 保持同名 server 只在一个 scope 定义
- 使用 `claude mcp list` 和 `claude mcp get flutter_copilot_mcp` 先看清当前生效项

---

## 9. 一个适合本仓库的最小调试流程

下面是一套比较稳的最小流程。

### 第一步：在仓库根目录注册 MCP

```bash
claude mcp add --scope project --transport stdio flutter_copilot_mcp -- dart run ./packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart -l FINEST --log-file ./.claude/logs/flutter_copilot_mcp.log
```

### 第二步：确认 Claude Code 已识别

```bash
claude mcp list
claude mcp get flutter_copilot_mcp
```

然后在 Claude Code 里执行：

- `/mcp`
- `/doctor`

### 第三步：启动 Flutter 示例应用

```bash
cd example && flutter run
```

### 第四步：拿到 VM Service URI

从终端或 `.vm_service_uri` 中拿到：

```text
ws://127.0.0.1:xxxx/ws
```

### 第五步：在 Claude Code 中调用 MCP 工具

先让 Claude Code 使用 `connect` 连接应用，再继续调试其他工具。

---

## 10. 什么时候优先看哪份日志

### 优先看 Claude Code debug 日志的情况

- `/mcp` 里 server 直接 `failed`
- Claude Code 看起来没有识别到工具
- 注册命令看起来成功，但会话中不可用

看：

```bash
~/.claude/debug/<session-id>.txt
```

### 优先看 MCP 自己日志文件的情况

- server 已经启动，但工具调用异常
- `connect` 后行为不符合预期
- VM Service 交互失败
- 想看 `VmServiceConnector` 的详细连接过程

看你通过 `--log-file` 指定的文件。

---

## 11. 本仓库相关文件

调试 Claude Code 本地 MCP 时，最相关的文件通常是：

- [packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart](../packages/flutter_copilot_mcp/bin/flutter_copilot_mcp.dart)
- [packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_context.dart](../packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_context.dart)
- [packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_connector.dart](../packages/flutter_copilot_mcp/lib/src/vm_service/vm_service_connector.dart)
- [packages/flutter_copilot_mcp/lib/src/compat/copilot_stdio_server_transport.dart](../packages/flutter_copilot_mcp/lib/src/compat/copilot_stdio_server_transport.dart)
- [.cursor/mcp.json](../.cursor/mcp.json)
- [.vscode/launch.json](../.vscode/launch.json)
- [scripts/flutter_run.sh](../scripts/flutter_run.sh)

---

## 12. 结论

在这个仓库里调试 Claude Code 的本地 MCP，最关键的不是 Flutter UI 逻辑，而是先确保下面三件事成立：

1. Claude Code 读取的是 `.mcp.json`，不是 `.cursor/mcp.json`
2. `flutter_copilot_mcp` 能被 Claude Code 正常启动并完成 stdio 握手
3. MCP server 再去正确连接 Flutter 应用的 VM Service

如果这三层中任意一层出问题，就按本文的顺序排查：

- `claude mcp add`
- `claude mcp list`
- `/mcp`
- `/doctor`
- `~/.claude/debug/<session-id>.txt`
- `flutter_copilot_mcp --log-file ...`

这样通常能很快定位问题。