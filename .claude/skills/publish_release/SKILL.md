---
name: publish-release
description: 升级 flutter_copilot_claw 和 flutter_copilot_mcp 的共享版本号，更新 changelog，生成 version.g.dart，并通过 tool/publish.sh 完成 dry-run 或正式发布
---

# Flutter Copilot 发布 Skill

用于本仓库的 pub.dev 发布流程：统一升级两个包版本、补 changelog、校验发布内容、执行 dry-run，最后按需正式发布。

## When to Use

- 需要同时发布 `flutter_copilot_claw` 和 `flutter_copilot_mcp`
- 需要把两个包版本统一升级到同一个新版本
- 需要补 `CHANGELOG.md` 并生成 `packages/flutter_copilot_mcp/lib/src/version.g.dart`
- 需要按仓库既有脚本执行 pub.dev dry-run 或正式发布

## Key Files

- `packages/flutter_copilot_claw/pubspec.yaml` — `flutter_copilot_claw` 版本号与 pub.dev 元数据
- `packages/flutter_copilot_mcp/pubspec.yaml` — `flutter_copilot_mcp` 版本号与 pub.dev 元数据
- `packages/flutter_copilot_claw/CHANGELOG.md` — claw 发布说明
- `packages/flutter_copilot_mcp/CHANGELOG.md` — mcp 发布说明
- `packages/flutter_copilot_mcp/README.md` — mcp 的 pub.dev 首页说明
- `packages/flutter_copilot_mcp/lib/src/version.g.dart` — 由 `dart tool/generate_version.dart` 生成的共享版本文件
- `tool/publish.sh` — 仓库内置发布脚本，默认 dry-run，`--force` 时真正发布

## Release Rules

1. `flutter_copilot_claw` 和 `flutter_copilot_mcp` 必须使用**相同版本号**。
2. 修改 `pubspec.yaml` 后，必须运行：
   ```bash
   dart tool/generate_version.dart
   ```
3. `CHANGELOG.md` 顶部必须新增当前版本条目，且内容和这次实际发布一致。
4. 正式发布前必须先跑：
   ```bash
   ./tool/publish.sh
   ```
5. 只有在 dry-run 成功后，才执行：
   ```bash
   ./tool/publish.sh --force
   ```
6. `tool/publish.sh` 会在临时目录里去掉 `resolution: workspace` 后再发布，不要手动改仓库里的该字段。

## Recommended Workflow

### 1. 确认这次版本包含的改动

优先检查：

```bash
git status --short
git diff -- packages/flutter_copilot_claw packages/flutter_copilot_mcp README.md docs
```

重点确认：

- 这次是否需要升级版本
- `packages/flutter_copilot_mcp/README.md` 是否要同步最新演示内容
- `CHANGELOG.md` 文案是否准确反映本次发布内容

### 2. 升级两个包版本

同时修改：

- `packages/flutter_copilot_claw/pubspec.yaml`
- `packages/flutter_copilot_mcp/pubspec.yaml`

例如把：

```yaml
version: 1.0.3
```

改为：

```yaml
version: 1.0.4
```

### 3. 更新两个 changelog

在两个文件顶部新增同版本条目：

- `packages/flutter_copilot_claw/CHANGELOG.md`
- `packages/flutter_copilot_mcp/CHANGELOG.md`

推荐结构：

```md
## 1.0.x

- One-line summary of the release.
- Highlight the user-visible docs/demo/tooling update.
- MCP tools: connect, disconnect, get_interactive_elements, tap, enter_text, scroll_to, get_logs, get_rebuild_snapshot, take_screenshots, hot_reload, flutter_copilot_drag, swipe, long_press, double_tap, navigate.
```

如果这次只是文档、演示、README、发布元数据更新，也要明确写出来，不要伪装成代码能力新增。

### 4. 重新生成共享版本文件

```bash
dart tool/generate_version.dart
```

生成结果应体现在：

- `packages/flutter_copilot_mcp/lib/src/version.g.dart`

### 5. 运行 dry-run

```bash
./tool/publish.sh
```

预期结果：

- 两个包都 analyze 通过
- pub.dev dry-run 无 warning 或阻塞错误
- 输出里显示当前发布版本号正确

如果失败，优先排查：

- 版本号不一致
- `CHANGELOG.md` 未包含当前版本
- `version.g.dart` 未同步
- `README.md` 引用了不合适的本地资源或失效链接

### 6. 正式发布

dry-run 成功后再执行：

```bash
./tool/publish.sh --force
```

成功后会看到类似输出：

```text
Successfully uploaded https://pub.dev/packages/flutter_copilot_claw version x.y.z
Successfully uploaded https://pub.dev/packages/flutter_copilot_mcp version x.y.z
```

pub.dev 页面通常需要几分钟到 10 分钟左右刷新。

## Demo / README Notes

如果这次发布包含演示内容更新，优先检查：

- `README.md`
- `packages/flutter_copilot_mcp/README.md`

当前仓库里，`flutter_copilot_mcp` 的 README 可以直接展示首页 demo GIF，并链接到完整演示视频。对 pub.dev 页面更友好的做法是使用远程可访问地址，而不是依赖本地相对视频直接播放。

## Suggested Post-release Checks

发布完成后建议检查：

```bash
git diff -- packages/flutter_copilot_claw/pubspec.yaml packages/flutter_copilot_mcp/pubspec.yaml packages/flutter_copilot_claw/CHANGELOG.md packages/flutter_copilot_mcp/CHANGELOG.md packages/flutter_copilot_mcp/lib/src/version.g.dart packages/flutter_copilot_mcp/README.md
```

然后确认：

- pub.dev 上两个包都显示新版本
- `flutter_copilot_mcp` 的 README/GIF 展示正常
- 版本号、changelog、README 内容彼此一致

## Quick Commands

```bash
# 1) 改版本号后生成共享版本文件
dart tool/generate_version.dart

# 2) dry-run
./tool/publish.sh

# 3) 正式发布
./tool/publish.sh --force
```
