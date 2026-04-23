---
name: feishu-sync-doc
description: 将当前项目的 Markdown 文档（及其引用的本地图片）一键同步到飞书云文档。基于 lark-cli，自动上传图片、替换 token、以 overwrite 方式覆盖正文。
author: Flutter Copilot Team
---

# Feishu Doc Sync Skill

一键把本地 Markdown（含本地图片引用）同步到飞书文档：上传图片 → 替换 token → 覆盖正文。

## 目录结构

```
.claude/skills/feishu_sync/
├── SKILL.md            # 本文件
├── sync.sh             # 可复用的同步脚本
├── cache/              # Token 缓存（按文件 mtime 命中，避免重复上传）
│   └── *.tokens.json
└── examples/           # 历史运行产物（参考）
    └── *.with_tokens.md
```

## 前提条件

```bash
npm i -g @larksuite/cli
lark-cli auth login --scope "docs:write drive:write"
```

已有目标飞书文档（Docx）且拥有写入权限。

## 使用方法

```bash
bash .claude/skills/feishu_sync/sync.sh <SOURCE_MD> <FEISHU_DOC_URL> [NEW_TITLE]
```

**示例：**

```bash
bash .claude/skills/feishu_sync/sync.sh \
  "分享/FlutterCopilot项目演讲稿_v2.md" \
  "https://hcnigilc9nwt.feishu.cn/docx/YzAPdiEhWoAFKUxNMbbc2Ww2nLh" \
  "让 AI 真正上手操作 App —— Flutter Copilot 项目实践分享"
```

## 工作流程

1. **提取图片引用**：扫描 Markdown 中 `![alt](path)`，只保留非 http 的本地相对路径。
2. **上传 + 缓存**：对每张图片用 `lark-cli docs +media-insert --doc <DOC> --file <path>` 上传，解析返回的 `file_token`；以 `path@mtime` 为 key 缓存到 `cache/<md名>.tokens.json`，下次命中则跳过上传。
3. **生成 token 化 MD**：把 `![alt](path)` 替换为 `<image token="..." width="1200" height="<按SVG宽高比计算>" align="center"/>`（脚本会自动解析 SVG `viewBox`/`width`/`height` 计算比例，PNG/JPG 通过 PIL 读取像素），输出到 `cache/<md名>.with_tokens.md`。
4. **覆盖飞书文档**：`lark-cli docs +update --mode overwrite --markdown @<tmp.md>`，可选 `--new-title` 同步更新标题。

## 图片路径约定

- Markdown 中图片写 **相对路径**（如 `./images/svg/xx.svg`）
- 实际文件路径 = **源 MD 所在目录 + 相对路径**
- 已支持 png / jpg / svg

## 清理缓存

```bash
rm -rf .claude/skills/feishu_sync/cache/*
```

## 参考

- [lark-cli 文档](https://github.com/larksuite/cli)
- `lark-cli docs +media-insert --help`
- `lark-cli docs +update --help`

## 局部更新（保留已有内容）

整文 overwrite 会清掉飞书上手动插入的视频/附件/白板等块，使用 `--mode` 做局部更新：

```bash
# 按标题选中某个 section 替换
lark-cli docs +update --doc <URL> \
  --mode replace_range \
  --selection-by-title "### 某章节标题" \
  --markdown @new_section.md

# 在指定文本前插入
lark-cli docs +update --doc <URL> \
  --mode insert_before \
  --selection-with-ellipsis "目标锚点文本" \
  --markdown @addition.md
```

**已知限制：** lark-cli 的 Markdown 方言不识别 `<view>` / `<file>` 等非标准标签，整文同步时会被丢弃（触发 `UNSUPPORTED_HTML_TAG` 警告）。若目标文档里有手动上传的视频/附件块，**不要用 overwrite 整段替换**，改用 `replace_range` / `insert_before` / `insert_after` 绕开这些块。仅 `<image token="..."/>` 是受支持的 HTML 标签。
