#!/bin/bash
# =============================================================================
# generate_datagroup.sh - 產生 F5 External DataGroup 檔案 (動態 Zone 支援)
# =============================================================================
# 功能: 將解析後的檔案整理到最終輸出目錄
# 輸出格式已由 parse_rpz.sh 產生，此腳本僅負責檔案管理
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
FINAL_OUTPUT_DIR="${OUTPUT_DIR}/final"
ZONELIST_FILE="${ZONELIST_FILE:-${PROJECT_ROOT}/config/zonelist.txt}"

# =============================================================================
# 讀取 Zone 清單
# =============================================================================

get_zone_list() {
    if [[ ! -f "$ZONELIST_FILE" ]]; then
        die "Zone 清單檔案不存在: $ZONELIST_FILE"
    fi

    # 讀取非註解、非空白行
    grep -v '^#' "$ZONELIST_FILE" | grep -v '^[[:space:]]*$' | xargs
}

# =============================================================================
# 整理 DataGroup 檔案到最終目錄
# =============================================================================

prepare_final_datagroups() {
    log_info "整理 DataGroup 檔案到最終目錄"

    # 建立最終輸出目錄
    ensure_dir "$FINAL_OUTPUT_DIR"

    # 讀取 zone 清單
    local zone_list_str
    zone_list_str=$(get_zone_list)

    if [[ -z "$zone_list_str" ]]; then
        die "Zone 清單為空"
    fi

    # 轉換為陣列
    local zones
    read -ra zones <<< "$zone_list_str"
    log_info "處理 ${#zones[@]} 個 Zones: ${zones[*]}"

    local count=0

    # 處理每個 zone
    for zone in "${zones[@]}"; do
        local parsed_file
        parsed_file=$(ls -t "${PARSED_DATA_DIR}/${zone}_"*.txt 2>/dev/null | head -1)

        if [[ -f "$parsed_file" ]]; then
            cp "$parsed_file" "${FINAL_OUTPUT_DIR}/${zone}.txt"
            local record_count
            record_count=$(wc -l < "$parsed_file")
            log_info "✓ ${zone} DataGroup: ${FINAL_OUTPUT_DIR}/${zone}.txt ($record_count 筆)"
            count=$((count + 1))
        else
            # 建立空檔案
            touch "${FINAL_OUTPUT_DIR}/${zone}.txt"
            log_debug "  ${zone}: 無記錄 (建立空檔案)"
        fi
    done

    # 處理 IP DataGroup (rpzip)
    local ip_file
    ip_file=$(ls -t "${PARSED_DATA_DIR}"/rpzip_*.txt 2>/dev/null | head -1)

    if [[ -f "$ip_file" && -s "$ip_file" ]]; then
        cp "$ip_file" "${FINAL_OUTPUT_DIR}/rpzip.txt"
        local ip_count
        ip_count=$(wc -l < "$ip_file")
        log_info "✓ rpzip DataGroup: ${FINAL_OUTPUT_DIR}/rpzip.txt ($ip_count 筆)"
        count=$((count + 1))
    else
        touch "${FINAL_OUTPUT_DIR}/rpzip.txt"
        log_debug "  rpzip: 無記錄 (建立空檔案)"
    fi

    if [[ $count -eq 0 ]]; then
        log_warn "沒有找到任何有效的解析檔案"
    fi

    log_info "共產生 $count 個有效的 DataGroup 檔案"

    # 設定全域變數供 update_datagroup.sh 使用
    export FINAL_OUTPUT_DIR
    export PROCESSED_ZONES="${zones[*]}"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始產生 DataGroup 檔案 ==="

    prepare_final_datagroups

    log_info "=== DataGroup 檔案產生完成 ==="
    log_info "檔案位置: $FINAL_OUTPUT_DIR"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
