set -euo pipefail
DOC='https://hcnigilc9nwt.feishu.cn/docx/TeCadPnIsoMtRVxM8FNcrBBSnxc?from=from_copylink'
TOP_FILE=.agents/skills/feishu_sync/cache/v3_resync_top_before_section2.md
AFTER_FILE=.agents/skills/feishu_sync/cache/v3_resync_after_section2.md
TOP_CONTENT="$(cat "$TOP_FILE")"
AFTER_CONTENT="$(cat "$AFTER_FILE")"
lark-cli docs +update --as user --doc "$DOC" --mode replace_range --selection-with-ellipsis '# 让 AI 真正上手操作 App...@.claude/skills/feishu_sync/cache/FlutterCopilot演示文稿_v3.chunk.bb9c5857.md' --markdown "$TOP_CONTENT" --new-title '让 AI 真正上手操作 App —— Flutter Copilot 项目实践分享'
lark-cli docs +update --as user --doc "$DOC" --mode replace_range --selection-with-ellipsis '@.claude/skills/feishu_sync/cache/FlutterCopilot演示文稿_v3.chunk.aca5efa0.md...@.claude/skills/feishu_sync/cache/FlutterCopilot演示文稿_v3.chunk.ab6a8140.md' --markdown "$AFTER_CONTENT"
