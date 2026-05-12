#!/usr/bin/env bash
#
# 一键发布编排器 — 三个包可单发, 也可一键全发
#   - flutter_copilot_claw → pub.dev
#   - flutter_copilot_mcp  → pub.dev
#   - flutter_copilot_cli  → npmjs.org
#
# 用法:
#   ./tool/publish.sh --all                                    # 默认 dry-run, 三包都跑一遍
#   ./tool/publish.sh --all --force                            # 三包一起真发布 (npm 会交互式问 OTP)
#   ./tool/publish.sh --version 1.0.4 --all --force            # 先统一版本, 再一键三发
#   ./tool/publish.sh --version 1.0.4 --all --force --otp 123456  # 非交互 (CI 场景)
#   ./tool/publish.sh --cli --force                            # 只发 CLI
#   ./tool/publish.sh --mcp --claw --force                     # 只发两个 Dart 包
#   ./tool/publish.sh --version 1.0.4                          # 只 bump 版本号不发布
#
# 选项:
#   --version X.Y.Z   先把 3 个包统一到该版本 (调用 dart tool/version.dart --set, 可选)
#   --cli             发布 flutter_copilot_cli  → npm
#   --mcp             发布 flutter_copilot_mcp  → pub.dev
#   --claw            发布 flutter_copilot_claw → pub.dev
#   --all             = --cli --mcp --claw
#   --force           真正上传 (默认 dry-run)
#   --otp <code>      npm 2FA 一次性验证码; 转发给 publish_cli.sh。只对 --cli 有效,
#                     Dart 侧 pub.dev 用 OAuth 不需要。
#   -h, --help        查看此帮助
#
# 发布顺序 (真发布时): claw → mcp → cli
#   Dart 侧 claw 是 mcp 的运行时依赖, 先发 claw 再发 mcp。
#   CLI 不依赖 Dart 端 pub.dev 发布成功与否, 放最后。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
}

VERSION=""
DRY_RUN=true
DO_CLI=false
DO_MCP=false
DO_CLAW=false
OTP=""
# 记录因 "版本已存在" 而被跳过的包, 末尾汇总
SKIPPED_PKGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --cli)     DO_CLI=true;  shift ;;
    --mcp)     DO_MCP=true;  shift ;;
    --claw)    DO_CLAW=true; shift ;;
    --all)     DO_CLI=true; DO_MCP=true; DO_CLAW=true; shift ;;
    --force)   DRY_RUN=false; shift ;;
    --otp)     OTP="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unknown option: $1" >&2; usage; exit 64 ;;
  esac
done

# ---------- 1. 可选的版本统一 ----------

if [[ -n "$VERSION" ]]; then
  (cd "$ROOT_DIR" && dart tool/version.dart --set "$VERSION")
  echo ""
fi

# ---------- 2. 未选择任何包时 ----------

if ! $DO_CLI && ! $DO_MCP && ! $DO_CLAW; then
  if [[ -n "$VERSION" ]]; then
    echo "(版本已统一为 $VERSION; 未指定任何 --cli/--mcp/--claw/--all, 不发布。)"
    exit 0
  fi
  echo "ERROR: 未指定任何 --cli/--mcp/--claw/--all, 什么也没做。" >&2
  echo "" >&2
  usage >&2
  exit 64
fi

# ---------- 3. 打印计划 ----------

echo "================================================"
if $DRY_RUN; then
  echo "  MODE: dry-run  (加 --force 可真正发布)"
else
  echo "  MODE: PUBLISH  (将真正上传!)"
fi
echo "  Plan (按执行顺序):"
$DO_CLAW && echo "    1. flutter_copilot_claw → pub.dev"
$DO_MCP  && echo "    2. flutter_copilot_mcp  → pub.dev"
$DO_CLI  && echo "    3. flutter_copilot_cli  → npm"
echo "================================================"
echo ""

# ---------- 4. Dart 包发布函数 ----------
#
# 保留原 publish.sh 的临时目录策略: 把包复制到 tmp 目录并去掉 `resolution: workspace`
# 再 pub publish, 这样不会污染原仓库、也避免 IDE watcher 竞态。

publish_dart() {
  local pkg_dir="$1"
  local pkg_name
  pkg_name=$(basename "$pkg_dir")

  echo ""
  echo "========================================"
  echo "  Publishing: $pkg_name"
  echo "========================================"

  # Step 1: 只在发 mcp 前重新同步 version.g.dart (version.generated.ts 由 bump 时已生成)
  if [[ "$pkg_name" == "flutter_copilot_mcp" && -f "$ROOT_DIR/tool/version.dart" ]]; then
    echo "  [step] Regenerating version.g.dart ..."
    (cd "$ROOT_DIR" && dart tool/version.dart) || true
  fi

  # Step 2: analyze
  echo "  [step] Analyzing ..."
  (cd "$pkg_dir" && dart analyze .)

  # Step 3: 拷到 tmp 目录 (-L 解引用软链)
  local tmp_pkg="$WORK_DIR/$pkg_name"
  echo "  [step] Copying to temp directory ..."
  rm -rf "$tmp_pkg"
  cp -RL "$pkg_dir" "$tmp_pkg"

  # Step 4: 去掉 resolution: workspace (pub publish 不接受)
  local tmp_pubspec="$tmp_pkg/pubspec.yaml"
  if grep -q '^resolution:' "$tmp_pubspec"; then
    grep -v '^resolution:' "$tmp_pubspec" > "$tmp_pubspec.tmp"
    mv "$tmp_pubspec.tmp" "$tmp_pubspec"
    echo "  [info] Removed 'resolution' from temp pubspec.yaml"
  fi

  # Step 5: pub get (临时目录重新解析依赖)
  echo "  [step] Running dart pub get in temp directory ..."
  (cd "$tmp_pkg" && dart pub get) || true

  # Step 6: publish
  if $DRY_RUN; then
    echo "  [step] Dry-run publish ..."
    (cd "$tmp_pkg" && PUB_HOSTED_URL=https://pub.dev dart pub publish --dry-run)
    echo "  ✓ $pkg_name"
  else
    echo "  [step] Publishing to pub.dev ..."
    # 捕获输出, 以便在 "已存在" 错误时转为跳过而不是终止整个流水线。
    local out rc
    set +e
    out=$(cd "$tmp_pkg" && PUB_HOSTED_URL=https://pub.dev dart pub publish --force 2>&1)
    rc=$?
    set -e
    # 回显子进程输出 (不吞日志)
    printf '%s\n' "$out"
    if [[ $rc -eq 0 ]]; then
      echo "  ✓ $pkg_name"
    elif echo "$out" | grep -qE "Version .+ of package .+ already exists|Package .+ already has the version"; then
      # pub.dev 报该版本已存在 — 幂等跳过
      echo "  ⊘ $pkg_name@$(_pkg_version "$pkg_dir") already on pub.dev, skipping."
      SKIPPED_PKGS+=("$pkg_name")
    else
      echo "  ✗ $pkg_name publish failed (exit $rc)." >&2
      return "$rc"
    fi
  fi
}

# 读取 pubspec.yaml / package.json 的版本, 用于打印跳过日志
_pkg_version() {
  local pkg_dir="$1"
  if [[ -f "$pkg_dir/pubspec.yaml" ]]; then
    grep -E '^version:' "$pkg_dir/pubspec.yaml" | head -1 | awk '{print $2}'
  elif [[ -f "$pkg_dir/package.json" ]]; then
    node -p "require('$pkg_dir/package.json').version" 2>/dev/null || echo '?'
  else
    echo '?'
  fi
}

# ---------- 5. CLI 发布: 委托给 publish_cli.sh ----------
#
# publish_cli.sh 已经处理了全部 npm 特有的 preflight (drift 检查 / registry / whoami /
# 重复版本 / pnpm build + test / 打包预览)。这里不传 --version, 版本在前面 bump 过了。

publish_cli() {
  echo ""
  echo "========================================"
  echo "  Publishing: flutter_copilot_cli"
  echo "========================================"

  # 组装参数: dry-run / --force [+ --otp <code>]
  local args=()
  if ! $DRY_RUN; then
    args+=(--force)
    if [[ -n "$OTP" ]]; then
      args+=(--otp "$OTP")
    fi
  fi

  # 捕获 publish_cli.sh 的 exit code: 0=发布成功, 75=版本已存在(跳过), 其它=真失败
  local rc
  set +e
  if [[ ${#args[@]} -gt 0 ]]; then
    "$SCRIPT_DIR/publish_cli.sh" "${args[@]}"
  else
    "$SCRIPT_DIR/publish_cli.sh"
  fi
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    return 0
  elif [[ $rc -eq 75 ]]; then
    SKIPPED_PKGS+=("flutter_copilot_cli")
    return 0
  else
    return "$rc"
  fi
}

# ---------- 6. 执行 ----------

if $DO_CLAW || $DO_MCP; then
  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
fi

$DO_CLAW && publish_dart "$ROOT_DIR/packages/flutter_copilot_claw"
$DO_MCP  && publish_dart "$ROOT_DIR/packages/flutter_copilot_mcp"
$DO_CLI  && publish_cli

echo ""
echo "========================================"
echo "  All done!"
if [[ ${#SKIPPED_PKGS[@]} -gt 0 ]]; then
  echo "  Skipped (version already on registry):"
  for p in "${SKIPPED_PKGS[@]}"; do echo "    - $p"; done
fi
echo "========================================"
