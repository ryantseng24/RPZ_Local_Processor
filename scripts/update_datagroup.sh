#!/bin/bash
# =============================================================================
# update_datagroup.sh - 更新 F5 External DataGroup
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"
FINAL_OUTPUT_DIR="${OUTPUT_DIR}/final"
LOG_FILE="${LOG_FILE:-/var/log/ltm}"

# =============================================================================
# 更新單一 DataGroup
# =============================================================================

update_single_datagroup() {
    local dg_name="$1"
    local source_file="$2"
    local timestamp=$(timestamp)

    log_info "更新 DataGroup: $dg_name"

    # 檢查檔案是否存在
    if [[ ! -f "$source_file" ]]; then
        log_error "來源檔案不存在: $source_file"
        echo "$timestamp $(hostname) ERROR: source file not found: $source_file" >> "$LOG_FILE"
        return 1
    fi

    # 檢查檔案是否為空
    if [[ ! -s "$source_file" ]]; then
        log_warn "來源檔案為空，跳過更新: $source_file"
        return 0
    fi

    # 執行 tmsh 更新
    if tmsh modify ltm data-group external "$dg_name" source-path "file:$source_file" 2>&1; then
        local record_count=$(wc -l < "$source_file")
        log_info "DataGroup $dg_name 更新成功 ($record_count 筆記錄)"
        echo "$timestamp $(hostname) INFO: updated DataGroup $dg_name ($record_count records, file=$source_file)" >> "$LOG_FILE"
        return 0
    else
        log_error "DataGroup $dg_name 更新失敗"
        echo "$timestamp $(hostname) ERROR: failed to update DataGroup $dg_name" >> "$LOG_FILE"
        return 1
    fi
}

# =============================================================================
# 批次更新 DataGroups
# =============================================================================

update_all_datagroups() {
    local success_count=0
    local fail_count=0

    log_info "=== 開始更新 F5 DataGroups ==="

    # 更新 rpz DataGroup
    local rpz_file="${FINAL_RPZ_FILE:-${FINAL_OUTPUT_DIR}/rpz.txt}"
    if [[ -f "$rpz_file" ]]; then
        if update_single_datagroup "rpz" "$rpz_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    else
        log_warn "找不到 RPZ DataGroup 檔案: $rpz_file"
        ((fail_count++))
    fi

    # 更新 phishtw DataGroup (如果存在)
    local phishtw_file="${FINAL_PHISHTW_FILE:-${FINAL_OUTPUT_DIR}/phishtw.txt}"
    if [[ -f "$phishtw_file" ]]; then
        if update_single_datagroup "phishtw" "$phishtw_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    else
        log_debug "PhishTW DataGroup 檔案不存在，跳過"
    fi

    # 更新 rpzip DataGroup (IP 類型)
    local ip_file="${FINAL_IP_FILE:-${FINAL_OUTPUT_DIR}/rpzip.txt}"
    if [[ -f "$ip_file" ]]; then
        if update_single_datagroup "rpzip" "$ip_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    else
        log_debug "IP DataGroup 檔案不存在，跳過"
    fi

    log_info "=== 更新完成 ==="
    log_info "成功: $success_count 個, 失敗: $fail_count 個"

    return $fail_count
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    update_all_datagroups
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi