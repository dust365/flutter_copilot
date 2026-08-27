#!/bin/bash
# flutter_run.sh - Wraps `flutter run`, captures VM Service URI and writes to .vm_service_uri
#
# 两种用法：
#   1. VS Code launch (Dart 扩展通过 customTool 调用):
#      脚本替代 flutter 命令，接收 Dart 扩展传来的 run --machine ... 等参数
#   2. 终端手动运行:
#      ./scripts/flutter_run.sh -d emulator-5554

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URI_FILE="$PROJECT_ROOT/.vm_service_uri"

rm -f "$URI_FILE"

# 如果第一个参数是 run，说明是 Dart 扩展调用 (flutter run --machine ...)
# 否则是手动调用，自动补上 run
if [ "$1" = "run" ]; then
  ARGS=("$@")
else
  ARGS=("run" "$@")
fi

TARGET_PATH=""
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  if [ "${ARGS[$i]}" = "--target" ] || [ "${ARGS[$i]}" = "-t" ]; then
    if [ $((i + 1)) -lt ${#ARGS[@]} ]; then
      TARGET_PATH="${ARGS[$((i + 1))]}"
    fi
    break
  fi
done

RUN_DIR="$PROJECT_ROOT"
if [ -n "$TARGET_PATH" ] && [ -f "$TARGET_PATH" ]; then
  SEARCH_DIR="$(cd "$(dirname "$TARGET_PATH")" && pwd)"
  while [ "$SEARCH_DIR" != "/" ]; do
    if [ -f "$SEARCH_DIR/pubspec.yaml" ]; then
      RUN_DIR="$SEARCH_DIR"
      break
    fi
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
  done

  if [ "$RUN_DIR" != "$PROJECT_ROOT" ]; then
    for ((i = 0; i < ${#ARGS[@]}; i++)); do
      if [ "${ARGS[$i]}" = "--target" ] || [ "${ARGS[$i]}" = "-t" ]; then
        ARGS[$((i + 1))]="${TARGET_PATH#$RUN_DIR/}"
        break
      fi
    done
  fi
fi

cd "$RUN_DIR"
flutter "${ARGS[@]}" 2>&1 | while IFS= read -r line; do
  echo "$line"

  # --machine 模式输出 JSON, URI 在 params.uri 字段:
  #   [{"event":"app.debugPort","params":{"port":12345,"wsUri":"ws://..."}}]
  # 普通模式输出文本:
  #   The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN/
  if [[ "$line" =~ \"wsUri\"[[:space:]]*:[[:space:]]*\"(ws[s]?://[^\"]+)\" ]]; then
    WS_URI="${BASH_REMATCH[1]}"
    echo "$WS_URI" > "$URI_FILE"
    echo "" >&2
    echo "════════════════════════════════════════════════════════" >&2
    echo "  [copilot] VM Service URI -> $URI_FILE" >&2
    echo "  [copilot] $WS_URI" >&2
    echo "════════════════════════════════════════════════════════" >&2
    echo "" >&2
  elif [[ "$line" =~ (https?://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/) ]]; then
    HTTP_URI="${BASH_REMATCH[1]}"
    WS_URI="${HTTP_URI/http:/ws:}"
    WS_URI="${WS_URI%/}/ws"
    echo "$WS_URI" > "$URI_FILE"
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  [copilot] VM Service URI -> $URI_FILE"
    echo "  [copilot] $WS_URI"
    echo "════════════════════════════════════════════════════════"
    echo ""
  fi
done
