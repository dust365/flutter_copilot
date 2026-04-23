#!/bin/bash
# Feishu Markdown Sync
# 将本地 Markdown（含本地图片引用）同步到飞书文档：
#   1) 上传所有本地图片并获取 file_token
#   2) 将 ![alt](path) 替换为 <image token="..."/>
#   3) 以 overwrite 模式覆盖目标飞书文档正文（可选同时更新标题）
#
# 用法:
#   bash sync.sh <SOURCE_MD> <FEISHU_DOC_URL> [NEW_TITLE]
#
# 依赖:
#   - lark-cli (npm i -g @larksuite/cli)，已 lark-cli auth login
#   - python3
#
# 图片路径约定：
#   - Markdown 中的图片使用相对路径（如 ./images/xx.svg）
#   - 实际文件路径 = 源 MD 所在目录 + 相对路径
set -e

SOURCE_MD="${1:?Usage: sync.sh <SOURCE_MD> <FEISHU_DOC_URL> [NEW_TITLE]}"
FEISHU_DOC_URL="${2:?Usage: sync.sh <SOURCE_MD> <FEISHU_DOC_URL> [NEW_TITLE]}"
NEW_TITLE="${3:-}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SKILL_DIR/cache"
mkdir -p "$CACHE_DIR"

BASENAME="$(basename "$SOURCE_MD" .md)"
TOKEN_JSON="$CACHE_DIR/${BASENAME}.tokens.json"
TEMP_MD="$CACHE_DIR/${BASENAME}.with_tokens.md"

SRC_DIR="$(cd "$(dirname "$SOURCE_MD")" && pwd)"
SRC_ABS="$SRC_DIR/$(basename "$SOURCE_MD")"

echo "📖 源文件: $SRC_ABS"
echo "🎯 飞书文档: $FEISHU_DOC_URL"

# 提取所有本地图片引用（去重，仅保留非 http 的相对路径）
echo "🔎 提取图片引用..."
IMAGE_PATHS=($(grep -oE '!\[[^]]*\]\(([^)]+)\)' "$SRC_ABS" \
  | sed -E 's/^!\[[^]]*\]\(([^)]+)\)$/\1/' \
  | grep -vE '^https?://' \
  | sort -u))
echo "   共 ${#IMAGE_PATHS[@]} 张本地图片"

# 加载已有 token 缓存（按 md_path+mtime 缓存，内容改动后自动重新上传）
python3 - <<PYEOF
import json, os, pathlib
p = pathlib.Path("$TOKEN_JSON")
if not p.exists():
    p.write_text("{}")
PYEOF

for md_path in "${IMAGE_PATHS[@]}"; do
  actual_path="$SRC_DIR/${md_path#./}"
  if [ ! -f "$actual_path" ]; then
    echo "   ⚠️  跳过不存在的文件: $actual_path"
    continue
  fi
  mtime=$(stat -f '%m' "$actual_path" 2>/dev/null || stat -c '%Y' "$actual_path")
  cache_key="${md_path}@${mtime}"

  cached=$(python3 -c "
import json
d=json.load(open('$TOKEN_JSON'))
print(d.get('$cache_key',''))
")
  if [ -n "$cached" ]; then
    echo "   ♻️  命中缓存: $md_path -> $cached"
    continue
  fi

  echo "   ⬆️  上传: $md_path"
  result=$(lark-cli docs +media-insert --doc "$FEISHU_DOC_URL" --file "$actual_path" --type image --align center 2>&1)
  token=$(echo "$result" | python3 -c "
import sys,json,re
data=sys.stdin.read()
try:
    j=json.loads(data)
    def find(o):
        if isinstance(o,dict):
            if 'file_token' in o: return o['file_token']
            for v in o.values():
                r=find(v);
                if r: return r
        elif isinstance(o,list):
            for v in o:
                r=find(v);
                if r: return r
    t=find(j) or ''
    print(t)
except Exception:
    m=re.search(r'file_token[\"\s:]+([A-Za-z0-9_-]+)',data)
    print(m.group(1) if m else '')
")
  if [ -z "$token" ]; then
    echo "      ❌ 上传失败: $result"
    exit 1
  fi
  echo "      ✅ $token"
  python3 -c "
import json
p='$TOKEN_JSON'
d=json.load(open(p))
d['$cache_key']='$token'
json.dump(d,open(p,'w'),ensure_ascii=False,indent=2)
"
done

echo "📝 生成 Token 化 Markdown..."
SOURCE_MD_ABS="$SRC_ABS" TOKEN_JSON_PATH="$TOKEN_JSON" TEMP_MD_PATH="$TEMP_MD" SRC_DIR_ABS="$SRC_DIR" python3 <<'PYEOF'
import json, re, os, pathlib
src = pathlib.Path(os.environ["SOURCE_MD_ABS"])
dst = pathlib.Path(os.environ["TEMP_MD_PATH"])
src_dir = pathlib.Path(os.environ["SRC_DIR_ABS"])
tokens_raw = json.loads(pathlib.Path(os.environ["TOKEN_JSON_PATH"]).read_text())
latest = {}
for k, v in tokens_raw.items():
    path, _, mt = k.rpartition("@")
    if path not in latest or int(mt) > latest[path][0]:
        latest[path] = (int(mt), v)
tokens = {p: mv[1] for p, mv in latest.items()}

TARGET_W = 1200  # 飞书文档列宽适配

def parse_aspect(fp: pathlib.Path):
    """返回 (w, h) 像素；无法解析则返回 None。"""
    try:
        if fp.suffix.lower() == ".svg":
            head = fp.read_text(errors="ignore")[:2000]
            m_vb = re.search(r'viewBox\s*=\s*"([\d.\s-]+)"', head)
            if m_vb:
                parts = m_vb.group(1).split()
                if len(parts) == 4:
                    return float(parts[2]), float(parts[3])
            mw = re.search(r'\bwidth\s*=\s*"([\d.]+)', head)
            mh = re.search(r'\bheight\s*=\s*"([\d.]+)', head)
            if mw and mh:
                return float(mw.group(1)), float(mh.group(1))
        else:
            try:
                from PIL import Image  # type: ignore
                with Image.open(fp) as im:
                    return im.size
            except Exception:
                return None
    except Exception:
        return None
    return None

def repl(m):
    path = m.group(2)
    tk = tokens.get(path)
    if not tk:
        return m.group(0)
    actual = src_dir / path.lstrip("./")
    dims = parse_aspect(actual) if actual.exists() else None
    if dims:
        w, h = dims
        height = int(round(TARGET_W * h / w))
    else:
        height = int(TARGET_W * 9 / 16)
    return f'<image token="{tk}" width="{TARGET_W}" height="{height}" align="center"/>'

text = src.read_text()
text = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', repl, text)
dst.write_text(text)
print(f"   -> {dst}")
PYEOF

echo "🚀 覆盖飞书文档..."
# lark-cli requires a relative path within cwd for @file
REL_TEMP_MD="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], os.getcwd()))" "$TEMP_MD")"
CMD=(lark-cli docs +update --doc "$FEISHU_DOC_URL" --mode overwrite --markdown "@$REL_TEMP_MD")
if [ -n "$NEW_TITLE" ]; then
  CMD+=(--new-title "$NEW_TITLE")
fi
"${CMD[@]}"

echo ""
echo "✅ 完成: $FEISHU_DOC_URL"
