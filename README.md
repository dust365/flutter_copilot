# Flutter Copilot

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![flutter_copilot_mcp pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_mcp)](https://pub.dev/packages/flutter_copilot_mcp)
[![flutter_copilot_claw pub.dev badge](https://img.shields.io/pub/v/flutter_copilot_claw)](https://pub.dev/packages/flutter_copilot_claw)

**Flutter Copilot 是一个面向运行中 Flutter 应用的 MCP 方案，让 Claude Code、Cursor 等 AI Agent 能够直接连接、观察、操作和诊断 App。**

它通过 `MCP + VM Service` 把 AI 工具和 Flutter 运行时连接起来，让 Agent 不只停留在代码层面，还能进入真实应用状态完成页面验证、交互调试、日志排查和运行时诊断。

## 演示视频

通过下面的演示视频，可以更快了解 Flutter Copilot 的实际工作方式：

[文档/video/演示视频.mp4](文档/video/演示视频.mp4)

## 项目概述

Flutter Copilot 由两部分组成：

![Flutter Copilot 整体架构](分享/images/svg/【3-1-1】FlutterCopilot整体架构.svg)

上图展示了项目的整体结构：AI Client 通过 MCP 调用 `flutter_copilot_mcp`，后者再通过 VM Service 与集成了 `flutter_copilot_claw` 的 Flutter App 通信。

- [`flutter_copilot_mcp`](https://pub.dev/packages/flutter_copilot_mcp)：运行在 App 外部的 MCP Server，对 AI Client 暴露标准工具能力
- [`flutter_copilot_claw`](https://pub.dev/packages/flutter_copilot_claw)：集成在 Flutter App 内的运行时挂载插件，负责注册 VM Service 扩展

一句话理解：

> `flutter_copilot_claw` 在 App 内提供能力，`flutter_copilot_mcp` 在 App 外桥接 AI，最终让 Agent 可以直接操作运行中的 Flutter 应用。

## 适用场景

Flutter Copilot 适合这些典型场景：

- 页面交互验证
- 冒烟测试与流程回归
- UI 问题复现与调试
- 运行时日志采集
- 热重载后的快速确认
- Widget 重建热点排查

## 核心能力

![Flutter Copilot 能力总览](分享/images/svg/【3-4-1】FlutterCopilot能力总览.svg)

上图概括了 Flutter Copilot 当前覆盖的能力范围，包括连接、观察、交互、导航和诊断，适合构建从页面验证到问题排查的完整运行时协作链路。

当前能力覆盖连接、观察、交互、导航和诊断几个方向：

- 连接 Flutter App 的 VM Service
- 获取当前页面可交互元素
- 点击、输入、滚动、拖拽、滑动、长按、双击
- 页面导航控制
- 截图与日志获取
- Hot Reload
- Rebuild Snapshot / 重建热点分析

元素定位支持以下方式：

- `ValueKey<String>`
- 文本内容
- Widget 类型
- 坐标

其中 `ValueKey<String>` 是最稳定、最推荐的方式。

## 工作原理

![MCP 协议与 VM Service 调用链路](分享/images/svg/【3-3-1】MCP协议与VMService调用链路.svg)

这张图展示了从 AI 发起请求，到 MCP Server 翻译意图，再到 Flutter 运行时实际执行并返回结果的完整链路。

Flutter Copilot 的调用链路可以概括为：

1. AI Client 发起工具调用
2. `flutter_copilot_mcp` 将调用转换为 Flutter 可执行的操作
3. `flutter_copilot_claw` 在运行中的 App 内通过 VM Service 扩展执行操作
4. 结果以截图、日志、状态或结构化文本返回给 AI Client

这使得 AI 可以直接基于 Flutter 运行时状态进行判断，而不是只依赖源码或屏幕像素猜测。

## 仓库结构

- [packages/flutter_copilot_mcp/](packages/flutter_copilot_mcp/) — MCP Server 与工具桥接层
- [packages/flutter_copilot_claw/](packages/flutter_copilot_claw/) — Flutter 侧运行时绑定与 VM Service 扩展
- [example/](example/) — 示例应用
- [tool/](tool/) — 仓库工具脚本
- [文档/](文档/) — 补充文档

## 从哪里开始

如果你是第一次接触这个项目，建议从 `flutter_copilot_mcp` 开始：

- [flutter_copilot_mcp on pub.dev](https://pub.dev/packages/flutter_copilot_mcp)
- [flutter_copilot_mcp README](packages/flutter_copilot_mcp/README.md)
- [flutter_copilot_claw on pub.dev](https://pub.dev/packages/flutter_copilot_claw)

其中：

- `flutter_copilot_mcp` 是主要入口，包含安装、快速开始、工具列表和 Agent 配置方式
- `flutter_copilot_claw` 是 Flutter 侧接入包，职责更偏向运行时挂载

## 平台支持

Flutter Copilot 面向 Flutter 调试运行时，适用于：

- Android
- iOS
- Web
- macOS
- Windows
- Linux

实际能力依赖 Flutter 调试能力与 VM Service，可用性以调试模式下的运行环境为准。

## 本地开发

运行示例应用：

```bash
cd example && flutter run
```

从源码运行 MCP Server：

```bash
cd packages/flutter_copilot_mcp && dart run bin/flutter_copilot_mcp.dart -l FINEST
```

常用检查：

```bash
cd packages/flutter_copilot_mcp && dart analyze --fatal-infos lib bin
cd packages/flutter_copilot_claw && flutter analyze --fatal-infos lib
cd packages/flutter_copilot_claw && flutter test
cd example && flutter analyze
cd example && flutter test
dart tool/generate_version.dart
```

## 文档

- [项目说明](文档/项目说明.md)
- [VM Service 连接原理与实现](文档/VM_Service连接原理与实现.md)
- [Claude Code 调试本地 MCP 教程](文档/ClaudeCode调试本地MCP教程.md)
- [GitHub Repository](https://github.com/dust365/flutter_copilot)

## 发布包

- [flutter_copilot_mcp](https://pub.dev/packages/flutter_copilot_mcp)
- [flutter_copilot_claw](https://pub.dev/packages/flutter_copilot_claw)

## License

Apache License 2.0
