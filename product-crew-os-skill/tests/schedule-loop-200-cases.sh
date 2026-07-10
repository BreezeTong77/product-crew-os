#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/run-loop-200-cases.rb"
RUN_AT="10:00 AM tomorrow"
ITERATIONS=4
RUN_ID="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --at|--time)
      RUN_AT="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "未知参数: $1" >&2
      exit 1
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
  echo "额外参数: ${EXTRA_ARGS[*]}"
fi

LOG_FILE="${SCRIPT_DIR}/results/loop-200-scheduled-${RUN_ID}.log"
mkdir -p "${SCRIPT_DIR}/results"

EXTRA_ARG_STR=""
if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
  for arg in "${EXTRA_ARGS[@]}"; do
    printf -v EXTRA_ARG_STR '%s %q' "$EXTRA_ARG_STR" "$arg"
  done
fi

CMD="cd \"${SCRIPT_DIR}\" && /usr/bin/ruby \"${RUNNER}\" --iterations ${ITERATIONS} ${EXTRA_ARG_STR} >> \"${LOG_FILE}\" 2>&1"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "DRY-RUN: 未实际入队"
  echo "time: ${RUN_AT}"
  echo "iterations: ${ITERATIONS}"
  echo "run-id: ${RUN_ID}"
  echo "command: ${CMD}"
  exit 0
fi

schedule_with_nohup() {
  delay_seconds=$(
    ruby -e '
      require "time"
      now = Time.now
      target = Time.new(now.year, now.month, now.day, 10, 0, 0, now.utc_offset)
      target = target + 24 * 60 * 60 if target <= now
      sleep_seconds = (target - now).to_i
      puts sleep_seconds
    '
  )
  nohup /bin/bash -lc "sleep ${delay_seconds}; ${CMD}" >/tmp/pco-loop200-${RUN_ID}.scheduler.log 2>&1 &
  echo "${!}"
}

if command -v at >/dev/null 2>&1; then
  if printf '%s\n' "${CMD}" | at "${RUN_AT}" >/tmp/pco-loop200-${RUN_ID}.at.out 2>/tmp/pco-loop200-${RUN_ID}.at.err; then
    echo "已使用 at 入队：${RUN_AT}"
    echo "日志文件: ${LOG_FILE}"
    exit 0
  fi
fi

echo "at 调度不可用，已自动降级到 nohup fallback（到点启动一次性任务）。"
pid="$(schedule_with_nohup)"
echo "已启动 fallback 守护：pid=${pid}"
echo "日志文件: ${LOG_FILE}"
echo "at 失败日志: /tmp/pco-loop200-${RUN_ID}.at.err"
echo "nohup 命令: /tmp/pco-loop200-${RUN_ID}.scheduler.log"
