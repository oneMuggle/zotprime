#!/usr/bin/env bash
# 探测 Windows 版本号
# 输入: 无（--probe 模式调用 wmic）或 stdin 一行 ver 输出
# 输出: 单行 win11 | win10 | win8 | win7 | xp | unknown
# 退出码: 0=识别, 1=unknown, 2=工具不可用
# 副作用: stderr 一行 ISO8601 日志

set -euo pipefail

PROBE=false
if [ "${1:-}" = "--probe" ]; then
    PROBE=true
fi

log_ts() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

classify() {
    # $1: 版本字符串片段（数字）
    case "$1" in
        10.0)
            # Win10 vs Win11 都报 10.0，需要 build 号
            # Win11 build >= 22000
            if [ "${2:-0}" -ge 22000 ] 2>/dev/null; then
                echo "win11"
            else
                echo "win10"
            fi
            ;;
        6.3) echo "win8" ;;
        6.2) echo "win8" ;;
        6.1) echo "win7" ;;
        5.1|5.2) echo "xp" ;;
        *) echo "unknown" ;;
    esac
}

if [ "$PROBE" = true ]; then
    # 通过 wmic 探测
    if ! command -v wmic >/dev/null 2>&1; then
        log_ts "wmic not available, cannot probe"
        exit 2
    fi
    VER_RAW=$(wmic os get Version /value 2>/dev/null | grep "^Version=" | head -1 | cut -d= -f2 | tr -d '\r')
    if [ -z "$VER_RAW" ]; then
        log_ts "wmic returned empty Version"
        exit 2
    fi
    log_ts "wmic raw: $VER_RAW"
    MAJOR_MINOR=$(echo "$VER_RAW" | cut -d. -f1-2)
    BUILD=$(echo "$VER_RAW" | cut -d. -f3)
    RESULT=$(classify "$MAJOR_MINOR" "$BUILD")
    if [ "$RESULT" = "unknown" ]; then
        echo "$RESULT"
        exit 1
    fi
    echo "$RESULT"
    exit 0
else
    # 从 stdin 读
    if [ -t 0 ]; then
        log_ts "no stdin and no --probe"
        exit 2
    fi
    VER_LINE=$(cat)
    log_ts "stdin: $VER_LINE"
    if [ -z "$VER_LINE" ]; then
        log_ts "stdin was empty, cannot parse"
        exit 2
    fi
    # 提取 [Version X.Y.Z]
    # 用 { ... || true; } 包裹 grep,避免空匹配时 grep 返回 1 触发 set -e
    # (pipefail 会把 grep 的非零退出码冒泡到整个管道,从而提前 exit 1 而不是 2)
    VER_RAW=$(echo "$VER_LINE" | { grep -oE 'Version [0-9.]+' || true; } | head -1 | awk '{print $2}' | tr -d '\r')
    if [ -z "$VER_RAW" ]; then
        log_ts "could not parse Version from stdin"
        exit 2
    fi
    MAJOR_MINOR=$(echo "$VER_RAW" | cut -d. -f1-2)
    BUILD=$(echo "$VER_RAW" | cut -d. -f3)
    RESULT=$(classify "$MAJOR_MINOR" "$BUILD")
    if [ "$RESULT" = "unknown" ]; then
        echo "$RESULT"
        exit 1
    fi
    echo "$RESULT"
    exit 0
fi
