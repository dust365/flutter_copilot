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
