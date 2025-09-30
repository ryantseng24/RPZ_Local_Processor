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
OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"
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
        echo "$timestamp $(hostname) ERROR: dnsxdump command not found" >> "$LOG_FILE"
        return 1
    fi

    # 執行 dnsxdump
    if ! "$DNSXDUMP_CMD" > "$output_file" 2>&1; then
        log_error "執行 dnsxdump 失敗"
        echo "$timestamp $(hostname) ERROR: dnsxdump execution failed" >> "$LOG_FILE"
        return 1
    fi

    # 檢查輸出檔案
    if [[ ! -s "$output_file" ]]; then
        log_error "dnsxdump 輸出檔案為空"
        echo "$timestamp $(hostname) ERROR: dnsxdump output is empty" >> "$LOG_FILE"
        return 1
    fi

    local line_count=$(wc -l < "$output_file")
    log_info "dnsxdump 執行成功，匯出 $line_count 行資料"
    echo "$timestamp $(hostname) INFO: dnsxdump exported $line_count lines" >> "$LOG_FILE"

    return 0
}

# =============================================================================
# 從完整 dump 中提取特定 Zone 的資料
# =============================================================================

extract_zone_data() {
    local full_dump="$1"
    local zone_name="$2"
    local output_file="$3"

    log_debug "提取 Zone 資料: $zone_name"

    # 提取包含指定 zone 的所有記錄
    grep -E "\\.$zone_name\\.?[[:space:]]" "$full_dump" > "$output_file" || true

    local record_count=$(wc -l < "$output_file" 2>/dev/null || echo "0")
    log_debug "Zone $zone_name: 共 $record_count 筆記錄"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local timestamp_compact=$(timestamp_compact)

    log_info "=== 開始提取 RPZ 資料 ==="

    # 建立輸出目錄
    ensure_dir "$RAW_DATA_DIR"

    # 執行完整 dnsxdump
    local full_dump_file="${RAW_DATA_DIR}/dnsxdump_${timestamp_compact}.out"
    if ! execute_dnsxdump "$full_dump_file"; then
        die "DNS Express 資料提取失敗"
    fi

    # 讀取 Zone 清單並分別提取
    local zone_config="${PROJECT_ROOT}/config/rpz_zones.conf"
    [[ -f "$zone_config" ]] || die "Zone 配置檔案不存在: $zone_config"

    local zone_count=0
    while IFS= read -r zone; do
        [[ -z "$zone" ]] && continue
        [[ "$zone" =~ ^# ]] && continue

        zone=$(echo "$zone" | xargs)
        local zone_file="${RAW_DATA_DIR}/${zone%.}.raw"

        extract_zone_data "$full_dump_file" "$zone" "$zone_file"
        ((zone_count++))
    done < "$zone_config"

    log_info "完成提取 $zone_count 個 Zones"

    # 保留完整 dump 供除錯使用
    log_debug "完整 dump 檔案: $full_dump_file"

    # 設定全域變數供後續腳本使用
    export DNSXDUMP_FILE="$full_dump_file"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi