#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
INPUT_FILE="$SCRIPT_DIR/北疆11日自驾攻略-手机离线版.html"
OUTPUT_FILE="${1:-$SCRIPT_DIR/北疆11日自驾攻略-手机PDF版.pdf}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "找不到 HTML：$INPUT_FILE" >&2
  exit 1
fi

BROWSER=""
for candidate in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  if [[ -x "$candidate" ]]; then
    BROWSER="$candidate"
    break
  fi
done

if [[ -z "$BROWSER" ]]; then
  echo "没有找到 Chrome、Edge 或 Chromium。" >&2
  echo "也可以直接打开 HTML，点击页面里的“导出 PDF”，再在系统打印页选择“存储为 PDF”。" >&2
  exit 2
fi

TEMP_PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/travel-pdf.XXXXXX")"
TEMP_PDF="$TEMP_PROFILE/output.pdf"
CHROME_PID=""
cleanup() {
  if [[ -n "$CHROME_PID" ]] && kill -0 "$CHROME_PID" 2>/dev/null; then
    kill "$CHROME_PID" 2>/dev/null || true
  fi
  if [[ -n "$TEMP_PROFILE" && -d "$TEMP_PROFILE" ]]; then
    rm -rf -- "$TEMP_PROFILE"
  fi
}
trap cleanup EXIT

CHROME_LOG="$TEMP_PROFILE/chrome.log"
"$BROWSER" \
  --headless \
  --disable-gpu \
  --disable-background-networking \
  --disable-component-update \
  --disable-sync \
  --metrics-recording-only \
  --no-first-run \
  --no-default-browser-check \
  --no-pdf-header-footer \
  --run-all-compositor-stages-before-draw \
  --virtual-time-budget=2000 \
  --user-data-dir="$TEMP_PROFILE" \
  --print-to-pdf="$TEMP_PDF" \
  "file://$INPUT_FILE" >"$CHROME_LOG" 2>&1 &
CHROME_PID=$!

# 某些 macOS Chrome 版本写完 PDF 后仍不退出，因此以文件大小稳定为完成信号。
LAST_SIZE=0
STABLE_TICKS=0
EXPORT_READY=0
for _ in {1..160}; do
  if [[ -s "$TEMP_PDF" ]]; then
    CURRENT_SIZE="$(wc -c < "$TEMP_PDF" | tr -d ' ')"
    if [[ "$CURRENT_SIZE" = "$LAST_SIZE" ]]; then
      STABLE_TICKS=$((STABLE_TICKS + 1))
    else
      LAST_SIZE="$CURRENT_SIZE"
      STABLE_TICKS=0
    fi
    if (( STABLE_TICKS >= 4 )); then
      EXPORT_READY=1
      break
    fi
  elif ! kill -0 "$CHROME_PID" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if kill -0 "$CHROME_PID" 2>/dev/null; then
  kill "$CHROME_PID" 2>/dev/null || true
fi
wait "$CHROME_PID" 2>/dev/null || true
CHROME_PID=""

if (( EXPORT_READY != 1 )); then
  echo "Chrome 导出失败或等待超时，最后一段日志如下：" >&2
  tail -20 "$CHROME_LOG" >&2
  exit 3
fi

mv -f -- "$TEMP_PDF" "$OUTPUT_FILE"

if [[ ! -s "$OUTPUT_FILE" ]]; then
  echo "PDF 导出失败：没有生成有效文件。" >&2
  exit 4
fi

echo "已导出：$OUTPUT_FILE"
if [[ "${NO_OPEN:-0}" != "1" ]]; then
  open "$OUTPUT_FILE"
fi

if [[ -t 0 ]]; then
  echo "按回车关闭窗口。"
  read -r
fi
