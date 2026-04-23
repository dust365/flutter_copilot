---
name: feishu-sync-doc
description: "使用 Feishu CLI (lark-cli) 将当前项目的 Markdown 文档（及其包含的本地图片）同步到飞书文档。"
author: Flutter Copilot Team
---

# Feishu Doc Sync Skill

这个 skill 封装了使用 `lark-cli` 将本地 Markdown 文档及其引用的本地图片同步到飞书云文档的流程。

## 前提条件

1.  已安装 `lark-cli` (Node.js 版本)。
    ```bash
    npm install -g @larksuite/cli
    ```
2.  `lark-cli` 已登录并获得相应权限 (如 `docs:write` 或 `drive:write`)。
    ```bash
    lark-cli auth login --scope "docs:write drive:write"
    ```
3.  已有一个目标飞书文档（Doc 或 DocX），并拥有写入权限。

## 核心流程

同步过程分为三步：

1.  **准备 Markdown 和图片**：确保 Markdown 文件中的图片引用使用本地相对路径（如 `./images/xx.png`）。
2.  **上传图片并获取 Token**：使用 `lark-cli docs +media-insert` 或 `drive +upload` 将本地图片上传到飞书，并获取其 `file_token`。
3.  **替换图片 Token 并覆盖文档**：将 Markdown 中的本地图片链接替换为飞书 `<image token="..." />` 标签，然后使用 `lark-cli docs +update` 覆盖目标飞书文档的正文。

## 示例：同步 V2 演讲稿到飞书

以下是一个完整的示例，演示如何将 `文档/FlutterCopilot项目演讲稿_v2.md` 同步到指定的飞书文档。

**注意**：
- 请将 `FEISHU_DOC_URL` 替换为你的实际飞书文档链接或 ID。
- 此脚本为示例，实际使用时请根据你的 Markdown 文件名和图片路径进行调整。

```bash
#!/bin/bash
set -e

# === 配置项 ===
# 目标飞书文档 URL 或 ID
FEISHU_DOC_URL="https://hcnigilc9nwt.feishu.cn/docx/YzAPdiEhWoAFKUxNMbbc2Ww2nLh"
# 源 Markdown 文件
SOURCE_MD="文档/FlutterCopilot项目演讲稿_v2.md"
# 临时文件（用于 Token 替换后）
TEMP_MD=".claude/tmp_feishu_v2_with_images.md"
# 飞书文档标题
NEW_TITLE="Flutter Copilot 项目实践分享"

# === 步骤 1：上传所有本地图片并获取 Token ===
# 这里列出 V2 文档中引用的所有本地图片路径，请根据实际情况增删
IMAGE_PATHS=(
  "./文档/images/【0-0-1】让AI真正上手操作App.svg"
  "./文档/images/【3-1-1】FlutterCopilot整体架构.svg"
  "./文档/images/【3-2-1】MCP是什么.svg"
  "./文档/images/【3-2-2】VMService是什么.svg"
  "./文档/images/【3-3-1】MCP协议与VMService调用链路.svg"
  "./文档/images/【3-4-1】FlutterCopilot能力总览.svg"
  "./文档/images/【4-1-1】接入路径与提效指标示意图.svg"
  "./文档/images/【5-2-1】接入前后效率提升对比.svg"
  "./文档/images/【5-4-1】全链路开发闭环.svg"
  "./文档/images/【6-3-1】我是怎么利用AI从探索到落地的.svg"
)

echo "正在上传 ${#IMAGE_PATHS[@]} 张图片..."

# 创建一个临时 Python 脚本用于保存 token
TOKEN_MAP_SCRIPT=".claude/image_tokens_map.py"
cat <<EOF > "$TOKEN_MAP_SCRIPT"
token_map = {}
EOF

for img_path in "${IMAGE_PATHS[@]}"; do
  echo "  - 上传: $img_path"
  # 使用 lark-cli 上传图片，并解析输出中的 file_token
  # 注意：这里使用 docs +media-insert 是因为它直接返回可用于 docx 的 file_token
  # 并且可以指定 --doc 将图片挂载到目标文档下（避免权限问题）
  token=$(lark-cli docs +media-insert --doc "$FEISHU_DOC_URL" --file "$img_path" --type image --align center --jq '.data.file_token')

  if [ -z "$token" ] || [ "$token" == "null" ]; then
    echo "    [错误] 上传失败，未获取到 token。"
    exit 1
  fi
  echo "    [成功] Token: $token"

  # 将图片路径和 token 写入映射文件
  # 注意：这里的 key 使用 Markdown 中的相对路径引用格式
  md_ref_path=$(echo "$img_path" | sed 's|^./文档/images/|./images/|')
  echo "token_map['$md_ref_path'] = '$token'" >> "$TOKEN_MAP_SCRIPT"
done

echo "图片上传完成，Token 映射已保存。"

# === 步骤 2：生成带有图片 Token 的 Markdown 文件 ===
echo "正在生成 Token 化 Markdown..."

# 使用 Python 脚本进行批量替换
python3 - <<EOF
from pathlib import Path
from .claude.image_tokens_map import token_map

src_md = Path('$SOURCE_MD')
tmp_md = Path('$TEMP_MD')
text = src_md.read_text()

# 替换 Markdown 图片链接为飞书图片标签
for md_path, token in token_map.items():
    old_pattern = f'![.*]({md_path})'
    # 使用正则替换以匹配不同的 alt 文本
    import re
    text = re.sub(
        rf'!\[.*\]\({re.escape(md_path)}\)',
        f'<image token="{token}" width="1000" align="center"/>',
        text
    )

tmp_md.write_text(text)
print(f'  - 已生成: {tmp_md}')
EOF

# === 步骤 3：覆盖目标飞书文档 ===
echo "正在覆盖飞书文档..."

# 使用 lark-cli docs +update 覆盖正文和标题
lark-cli docs +update \
  --doc "$FEISHU_DOC_URL" \
  --mode overwrite \
  --new-title "$NEW_TITLE" \
  --markdown @"$TEMP_MD"

echo "✅ 飞书文档同步完成！"
echo "文档链接: $FEISHU_DOC_URL"

# 清理临时文件 (可选)
# rm "$TEMP_MD" "$TOKEN_MAP_SCRIPT"
```

## 参考资料

- [Feishu CLI 文档](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/cli-overview)
- [lark-cli docs 命令说明](https://github.com/larksuite/cli/blob/main/docs/docs.md)
