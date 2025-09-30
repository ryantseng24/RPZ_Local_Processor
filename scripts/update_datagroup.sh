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
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
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

    # 執行 tmsh 更新
    if tmsh modify ltm data-group external "$dg_name" source-path "file:$source_file" 2>&1; then
        log_info "DataGroup $dg_name 更新成功"
        echo "$timestamp $(hostname) INFO: updated DataGroup $dg_name (file=$source_file)" >> "$LOG_FILE"
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
    local timestamp_compact=$(timestamp_compact)
    local success_count=0
    local fail_count=0

    log_info "=== 開始更新 DataGroups ==="

    # 更新 rpz DataGroup (主要的)
    local rpz_file
    if [[ -n "${RPZ_PARSED_FILE:-}" && -f "$RPZ_PARSED_FILE" ]]; then
        rpz_file="$RPZ_PARSED_FILE"
    else
        rpz_file=$(ls -t "${PARSED_DATA_DIR}"/rpz_*.txt 2>/dev/null | head -1)
    fi

    if [[ -f "$rpz_file" ]]; then
        if update_single_datagroup "rpz" "$rpz_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    else
        log_warn "找不到 RPZ 解析檔案"
    fi

    # 更新 phishtw DataGroup (如果有的話)
    local phishtw_file
    if [[ -n "${PHISHTW_PARSED_FILE:-}" && -f "$PHISHTW_PARSED_FILE" ]]; then
        phishtw_file="$PHISHTW_PARSED_FILE"
    else
        phishtw_file=$(ls -t "${PARSED_DATA_DIR}"/phishtw_*.txt 2>/dev/null | head -1)
    fi

    if [[ -f "$phishtw_file" ]]; then
        if update_single_datagroup "phishtw" "$phishtw_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    fi

    # 更新 IP DataGroup
    local ip_file
    if [[ -n "${IP_PARSED_FILE:-}" && -f "$IP_PARSED_FILE" ]]; then
        ip_file="$IP_PARSED_FILE"
    else
        ip_file=$(ls -t "${PARSED_DATA_DIR}"/ip_*.txt 2>/dev/null | head -1)
    fi

    if [[ -f "$ip_file" ]]; then
        if update_single_datagroup "rpzip" "$ip_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    fi

    log_info "=== 更新完成: 成功 $success_count, 失敗 $fail_count ==="

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