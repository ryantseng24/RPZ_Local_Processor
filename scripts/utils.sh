#!/bin/bash
# =============================================================================
# utils.sh - 共用工具函數庫
# =============================================================================

# 顏色定義（在非互動環境中自動禁用，避免 ANSI 碼導致 iCall 誤報錯誤）
if [[ -t 2 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    # 有 TTY 且未禁用顏色
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[1;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_RESET='\033[0m'
else
    # 無 TTY（如 iCall 環境）或明確禁用顏色
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_RESET=''
fi

# 日誌等級
readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_WARN=2
readonly LOG_ERROR=3

# 預設日誌等級
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# =============================================================================
# 日誌函數
# =============================================================================

log_debug() {
    [[ $LOG_LEVEL -le $LOG_DEBUG ]] && echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $*" >&2 || true
}

log_info() {
    [[ $LOG_LEVEL -le $LOG_INFO ]] && echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*" >&2 || true
}

log_warn() {
    [[ $LOG_LEVEL -le $LOG_WARN ]] && echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2 || true
}

log_error() {
    [[ $LOG_LEVEL -le $LOG_ERROR ]] && echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2 || true
}

# =============================================================================
# 錯誤處理
# =============================================================================

die() {
    log_error "$*"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || die "必要指令不存在: $1"
}

# =============================================================================
# 檔案操作
# =============================================================================

ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p "$dir" || die "無法建立目錄: $dir"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.$(date +%Y%m%d_%H%M%S).bak"
        cp "$file" "$backup" || log_warn "無法備份檔案: $file"
        log_debug "已備份: $file -> $backup"
    fi
}

# =============================================================================
# 配置讀取
# =============================================================================

read_config() {
    local config_file="$1"
    [[ -f "$config_file" ]] || die "配置檔案不存在: $config_file"

    # 讀取非註解、非空白行
    grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$'
}

# =============================================================================
# 時間戳記
# =============================================================================

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

timestamp_compact() {
    date '+%Y%m%d_%H%M%S'
}

# =============================================================================
# 效能測量
# =============================================================================

timer_start() {
    TIMER_START=$(date +%s)
}

timer_end() {
    local end=$(date +%s)
    local elapsed=$((end - TIMER_START))
    echo "$elapsed"
}

timer_format() {
    local seconds="$1"
    printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

# =============================================================================
# 資料驗證
# =============================================================================

is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

# =============================================================================
# 安全函數
# =============================================================================

sanitize_input() {
    local input="$1"
    # 移除潛在危險字元
    echo "$input" | tr -d ';&|$`<>()'
}

# =============================================================================
# 取得符合 glob 的最新檔案 (依 mtime)
# =============================================================================
# 刻意不使用 `ls -t <glob> | head -1`。在 set -o pipefail 下，ls 對 pipe 的
# stdio write buffer 是 4096 bytes，輸出超過就需要多次 write()。head -1 取到
# 第一行即結束並關閉 pipe，ls 後續的 write() 收到 SIGPIPE 而以 141 結束。
# pipefail 讓管線回傳 141，set -e 隨即終止腳本，且不留任何錯誤訊息。
# 這是時序競態，機率隨檔案數上升。
# BIG-IP 17.1.3.1 實測 (真實 parse_rpz.sh，每組 30 次):
#   67 檔/4087B 0%、80 檔/4880B 17%、141 檔/8601B 80%、179 檔/10919B 87%
#
# 用法:
#   if ! newest=$(find_newest_file "$dir"/glob_*.txt); then
#       die "找不到檔案"
#   fi
#
# 回傳 0 並輸出路徑；完全沒有符合的檔案時回傳 1 且不輸出。
# 呼叫端必須明確處理回傳 1 的情況，不要用 `|| var=""` 把「找不到」
# 轉成成功控制流 (參見 CODE_REVIEW_20260821.md CR-01)。

find_newest_file() {
    local newest="" f
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        if [[ -z "$newest" || "$f" -nt "$newest" ]]; then
            newest="$f"
        fi
    done
    [[ -n "$newest" ]] || return 1
    printf '%s\n' "$newest"
}

# =============================================================================
# 匯出函數 (如果被 source)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # 被 source 時匯出所有函數
    export -f log_debug log_info log_warn log_error
    export -f die check_command
    export -f ensure_dir backup_file read_config find_newest_file
    export -f timestamp timestamp_compact
    export -f timer_start timer_end timer_format
    export -f is_valid_ip is_valid_domain sanitize_input
fi
