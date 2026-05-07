#!/usr/bin/env bash
#
# 发布 flutter_copilot_cli 到 npmjs.org
#
# 用法:
#   ./tool/publish_cli.sh                                 # dry-run (默认, 不真正发布)
#   ./tool/publish_cli.sh --force                         # 真正发布 (会提示 OTP)
#   ./tool/publish_cli.sh --force --otp 123456            # 传入 2FA 验证码, 非交互式
#   ./tool/publish_cli.sh --version 1.0.4                 # 先把 3 个包统一到 1.0.4, 再 dry-run
#   ./tool/publish_cli.sh --version 1.0.4 --force --otp 123456
#
# 选项:
#   --force           真正上传 (默认 dry-run)
#   --version X.Y.Z   先把 3 个包统一到该版本 (调用 dart tool/version.dart --set)
#   --otp <code>      npm 2FA 一次性验证码。未提供时: TTY 下 npm 会自己提示;
#                     非 TTY (CI) 下会报错要求必须传 --otp。
#   -h, --help        查看此帮助
#
# 前置条件:
#   - pnpm / npm / node 在 PATH 上
#   - 若 --force, 已 `npm login` 到 registry.npmjs.org (2FA 已启用就需要 OTP)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLI_DIR="$ROOT_DIR/packages/flutter_copilot_cli"
PKG_JSON="$CLI_DIR/package.json"

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

DRY_RUN=true
VERSION=""
OTP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   DRY_RUN=false; shift ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --otp)     OTP="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unknown option: $1" >&2; usage; exit 64 ;;
  esac
done

# ---------- helpers ----------

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' not found on PATH" >&2
    exit 1
  fi
}

read_json_field() {
  # 用 node 读 package.json 的字段, 避免依赖 jq
  local field="$1"
  node -e "process.stdout.write(String(require('$PKG_JSON').$field ?? ''))"
}

# ---------- preflight ----------

require_cmd pnpm
require_cmd npm
require_cmd node

if [[ ! -f "$PKG_JSON" ]]; then
  echo "ERROR: $PKG_JSON not found" >&2
  exit 1
fi

# ---------- version bump (optional) ----------

if [[ -n "$VERSION" ]]; then
  echo "================================================"
  echo "  Bumping all 3 packages to $VERSION first"
  echo "================================================"
  (cd "$ROOT_DIR" && dart tool/version.dart --set "$VERSION")
  echo ""
fi

PKG_NAME=$(read_json_field name)
PKG_VERSION=$(read_json_field version)

if [[ -z "$PKG_NAME" || -z "$PKG_VERSION" ]]; then
  echo "ERROR: failed to read name/version from $PKG_JSON" >&2
  exit 1
fi

echo "================================================"
if $DRY_RUN; then
  echo "  MODE: dry-run (不会真正发布)"
  echo "  加 --force 参数真正发布: ./tool/publish_cli.sh --force"
else
  echo "  MODE: PUBLISH (将真正发布到 npmjs!)"
fi
echo "  Package: $PKG_NAME@$PKG_VERSION"
echo "================================================"

# ---------- version sync check ----------
# 不管走没走 --version, 都保证 generated 文件与 3 份 source 对齐。
# 这里不再依赖 git 是否 clean, 因为调用者可能刚刚 bump 完还未 commit。

if [[ -f "$ROOT_DIR/tool/version.dart" ]]; then
  echo ""
  echo "  [step] Checking version alignment across claw / mcp / cli ..."
  if ! command -v dart >/dev/null 2>&1; then
    echo "  [warn] dart not found; skipping shared version drift check."
  else
    # --check 模式: 版本不齐 或 generated 文件过期 直接 exit 1
    (cd "$ROOT_DIR" && dart tool/version.dart --check >/dev/null)
    echo "  [ok]   三个包版本一致, generated 文件已同步。"
  fi
fi

# ---------- npm registry check ----------

if ! $DRY_RUN; then
  REGISTRY=$(npm config get registry)
  if [[ "$REGISTRY" != "https://registry.npmjs.org/" && "$REGISTRY" != "https://registry.npmjs.org" ]]; then
    echo "  [warn] npm registry is '$REGISTRY' (not registry.npmjs.org)."
    echo "         publishConfig.registry in package.json will override per-publish,"
    echo "         but make sure you actually want to push to npmjs.org."
  fi

  if ! npm whoami >/dev/null 2>&1; then
    echo "ERROR: not logged in to npm. Run 'npm login' first." >&2
    exit 1
  fi
  echo "  [ok]   npm whoami: $(npm whoami)"
fi

# ---------- duplicate version guard ----------
#
# 语义: 版本号已经发布过 = "幂等跳过"(exit 75), 不是硬错误。
# 75 在 sysexits(3) 里是 EX_TEMPFAIL, 这里借用作为 "非失败, 但没做任何事" 的信号,
# 方便 publish.sh 编排器批量发布时识别并继续。真正的上传失败仍是 exit 1。

REMOTE_VERSION=$(npm view "$PKG_NAME" version 2>/dev/null || echo "")
if [[ -n "$REMOTE_VERSION" ]]; then
  echo "  [info] latest published version: $REMOTE_VERSION"
  if ! $DRY_RUN && [[ "$REMOTE_VERSION" == "$PKG_VERSION" ]]; then
    echo "  ⊘ $PKG_NAME@$PKG_VERSION 已存在于 npm, 跳过。"
    exit 75
  fi
fi

# ---------- build & test ----------

echo ""
echo "  [step] Installing dependencies (pnpm install --frozen-lockfile) ..."
(cd "$CLI_DIR" && pnpm install --frozen-lockfile)

echo "  [step] Cleaning dist ..."
(cd "$CLI_DIR" && pnpm clean)

echo "  [step] Type-checking ..."
(cd "$CLI_DIR" && pnpm typecheck)

echo "  [step] Building ..."
(cd "$CLI_DIR" && pnpm build)

echo "  [step] Running tests ..."
(cd "$CLI_DIR" && pnpm test)

# ---------- preview tarball contents ----------

echo ""
echo "  [step] Previewing files that will be packed ..."
(cd "$CLI_DIR" && npm pack --dry-run)

# ---------- publish ----------

echo ""
if $DRY_RUN; then
  echo "  [step] Dry-run publish (npm publish --dry-run) ..."
  (cd "$CLI_DIR" && npm publish --dry-run --access public)
  echo ""
  echo "  ✓ $PKG_NAME@$PKG_VERSION (dry-run OK)"
else
  # npm 2FA (TOTP/WebAuthn) 处理:
  #   a) 传了 --otp <code>        → 直接附到 npm publish, 可捕获输出检测 "already exists"
  #   b) 没传 --otp, stdin 是 TTY → 让 npm 自己跟用户交互 (不捕获输出, 否则 prompt 被吞)
  #                                  此时无法事后 grep stderr 检测 "cannot publish over",
  #                                  靠前面的 npm view preflight 兜底 (已在 exit 75 处理)。
  #   c) 没传 --otp, 非 TTY (CI)  → 直接报错, 要求显式传 --otp, 避免卡在不可见的 prompt 上。
  if [[ -n "$OTP" ]]; then
    echo "  [step] Publishing to npmjs.org (with --otp) ..."
    set +e
    publish_out=$(cd "$CLI_DIR" && npm publish --access public --otp="$OTP" 2>&1)
    publish_rc=$?
    set -e
    printf '%s\n' "$publish_out"
    if [[ $publish_rc -eq 0 ]]; then
      :
    elif echo "$publish_out" | grep -qE "cannot publish over the previously published versions|403 Forbidden.*previously published"; then
      echo ""
      echo "  ⊘ $PKG_NAME@$PKG_VERSION 已存在于 npm (publish 时发现), 跳过。"
      exit 75
    elif echo "$publish_out" | grep -qiE "EOTP|one-time password"; then
      echo "  ✗ OTP 校验失败 (--otp 过期/错误)。重新跑: ./tool/publish_cli.sh --force --otp <NEW_CODE>" >&2
      exit "$publish_rc"
    else
      echo "  ✗ npm publish 失败 (exit $publish_rc)。" >&2
      exit "$publish_rc"
    fi
  elif [[ -t 0 ]]; then
    echo "  [step] Publishing to npmjs.org (交互式, 会提示 OTP) ..."
    # 不捕获: 让 npm 直接读终端的 OTP 输入。publish 失败会让 set -e 终止。
    # "版本已存在" 的情况已由前面 npm view preflight (exit 75) 拦截。
    set +e
    (cd "$CLI_DIR" && npm publish --access public)
    publish_rc=$?
    set -e
    if [[ $publish_rc -ne 0 ]]; then
      echo "  ✗ npm publish 失败 (exit $publish_rc)。" >&2
      echo "    若提示 EOTP, 用 --otp <6位验证码> 重试: ./tool/publish_cli.sh --force --otp 123456" >&2
      exit "$publish_rc"
    fi
  else
    echo "  ✗ 非交互环境 (stdin 非 TTY), 但未提供 --otp。" >&2
    echo "    在 CI 或管道里必须显式传 --otp <code>: ./tool/publish_cli.sh --force --otp 123456" >&2
    exit 1
  fi

  echo ""
  echo "  ✓ Published $PKG_NAME@$PKG_VERSION"
  echo "    https://www.npmjs.com/package/$PKG_NAME"
fi

echo ""
echo "========================================"
echo "  All done!"
echo "========================================"
