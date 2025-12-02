#!/bin/bash
# =============================================================================
# extract_rpz.sh - 從 DNS Express 提取 RPZ 資料
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
RAW_DATA_DIR="${OUTPUT_DIR}/raw"
DNSXDUMP_CMD="${DNSXDUMP_CMD:-/usr/local/bin/dnsxdump}"
LOG_FILE="${LOG_FILE:-/var/log/ltm}"

# =============================================================================
# 執行 dnsxdump 並導出完整資料
# =============================================================================

execute_dnsxdump() {
    local output_file="$1"
    local timestamp=$(timestamp)

    log_info "執行 dnsxdump 導出 DNS Express 資料"

    # 檢查指令是否存在
    if [[ ! -x "$DNSXDUMP_CMD" ]]; then
        log_error "dnsxdump 指令不存在或無執行權限: $DNSXDUMP_CMD"
        echo "$timestamp ERROR: dnsxdump command not found" >> "$LOG_FILE" 2>/dev/null || true
        return 1
    fi

    # 執行 dnsxdump
    if ! "$DNSXDUMP_CMD" > "$output_file" 2>&1; then
        log_error "執行 dnsxdump 失敗"
        echo "$timestamp ERROR: dnsxdump execution failed" >> "$LOG_FILE" 2>/dev/null || true
        return 1
    fi

    # 檢查輸出檔案
    if [[ ! -s "$output_file" ]]; then
        log_error "dnsxdump 輸出檔案為空"
        echo "$timestamp ERROR: dnsxdump output is empty" >> "$LOG_FILE" 2>/dev/null || true
        return 1
    fi

    local line_count=$(wc -l < "$output_file")
    log_info "dnsxdump 執行成功，匯出 $line_count 行資料"
    echo "$timestamp INFO: dnsxdump exported $line_count lines" >> "$LOG_FILE" 2>/dev/null || true

    return 0
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local timestamp_compact=$(timestamp_compact)

    log_info "=== 開始提取 RPZ 資料 ==="

    # 建立輸出目錄
    ensure_dir "$RAW_DATA_DIR"

    # 執行完整 dnsxdump - 直接產生供 parse_rpz.sh 使用
    local full_dump_file="${RAW_DATA_DIR}/dnsxdump_${timestamp_compact}.out"
    if ! execute_dnsxdump "$full_dump_file"; then
        die "DNS Express 資料提取失敗"
    fi

    log_info "=== RPZ 資料提取完成 ==="

    # 設定全域變數供後續腳本使用
    export DNSXDUMP_FILE="$full_dump_file"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi