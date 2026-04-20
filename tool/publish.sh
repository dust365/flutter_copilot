#!/usr/bin/env bash
#
# 一键发布 flutter_copilot_claw 和 flutter_copilot_mcp 到 pub.dev
#
# 用法:
#   ./tool/publish.sh          # dry-run 模式（默认，不真正发布）
#   ./tool/publish.sh --force  # 真正发布到 pub.dev
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAW_DIR="$ROOT_DIR/packages/flutter_copilot_claw"
MCP_DIR="$ROOT_DIR/packages/flutter_copilot_mcp"

DRY_RUN=true
if [[ "${1:-}" == "--force" ]]; then
  DRY_RUN=false
fi

# 创建临时工作目录，脚本退出时自动清理
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------- helpers ----------

# 将包复制到临时目录，去掉 "resolution: workspace" 后在临时目录中发布。
# 这样不会修改原始文件，避免 IDE watcher 竞态问题。
publish_package() {
  local pkg_dir="$1"
  local pkg_name
  pkg_name=$(basename "$pkg_dir")

  echo ""
  echo "========================================"
  echo "  Publishing: $pkg_name"
  echo "========================================"

  # Step 1: 更新 version.g.dart（仅 mcp 包有）
  if [[ -f "$ROOT_DIR/tool/generate_version.dart" && "$pkg_name" == "flutter_copilot_mcp" ]]; then
    echo "  [step] Generating version.g.dart ..."
    (cd "$ROOT_DIR" && dart run tool/generate_version.dart) || true
  fi

  # Step 2: 在原始目录分析
  echo "  [step] Analyzing ..."
  (cd "$pkg_dir" && dart analyze .)

  # Step 3: 复制到临时目录（-RL 解引用符号链接为实际文件）
  local tmp_pkg="$WORK_DIR/$pkg_name"
  echo "  [step] Copying to temp directory ..."
  rm -rf "$tmp_pkg"
  cp -RL "$pkg_dir" "$tmp_pkg"

  # Step 4: 在临时目录中去掉 resolution: workspace
  local tmp_pubspec="$tmp_pkg/pubspec.yaml"
  if grep -q '^resolution:' "$tmp_pubspec"; then
    grep -v '^resolution:' "$tmp_pubspec" > "$tmp_pubspec.tmp"
    mv "$tmp_pubspec.tmp" "$tmp_pubspec"
    echo "  [info] Removed 'resolution' from temp pubspec.yaml"
  fi

  # Step 5: 在临时目录中执行 dart pub get
  echo "  [step] Running dart pub get in temp directory ..."
  (cd "$tmp_pkg" && dart pub get) || true

  # Step 6: 发布（强制使用 pub.dev，避免走中国镜像）
  if $DRY_RUN; then
    echo "  [step] Dry-run publish ..."
    (cd "$tmp_pkg" && PUB_HOSTED_URL=https://pub.dev dart pub publish --dry-run)
  else
    echo "  [step] Publishing to pub.dev ..."
    (cd "$tmp_pkg" && PUB_HOSTED_URL=https://pub.dev dart pub publish --force)
  fi

  echo "  [done] $pkg_name finished."
}

# ---------- main ----------

echo "================================================"
if $DRY_RUN; then
  echo "  MODE: dry-run (不会真正发布)"
  echo "  加 --force 参数真正发布: ./tool/publish.sh --force"
else
  echo "  MODE: PUBLISH (将真正发布到 pub.dev!)"
fi
echo "================================================"

# 先发布 claw（基础包），再发布 mcp
publish_package "$CLAW_DIR"
publish_package "$MCP_DIR"

echo ""
echo "========================================"
echo "  All done!"
echo "========================================"
