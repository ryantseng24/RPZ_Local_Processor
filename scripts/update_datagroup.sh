#!/bin/bash
# =============================================================================
# update_datagroup.sh - 更新 F5 External DataGroup (動態 Zone 支援 + 自動建立)
# =============================================================================
# 功能:
# 1. 從 zonelist.txt 讀取要處理的 zones
# 2. 檢查 DataGroup 是否存在，不存在則自動建立
# 3. 更新 DataGroup 內容
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
FINAL_OUTPUT_DIR="${OUTPUT_DIR}/final"
LOG_FILE="${LOG_FILE:-/var/log/ltm}"
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
# 檢查 DataGroup 是否存在
# =============================================================================

datagroup_exists() {
    local dg_name="$1"

    if tmsh list ltm data-group external "$dg_name" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# 建立 External DataGroup
# =============================================================================

create_datagroup() {
    local dg_name="$1"
    local source_file="$2"
    local timestamp=$(timestamp)

    log_info "建立新的 DataGroup: $dg_name"

    # 建立 external data-group
    if tmsh create ltm data-group external "$dg_name" \
        source-path "file:$source_file" \
        type string 2>&1; then
        log_info "✓ DataGroup $dg_name 建立成功"
        echo "$timestamp $(uname -n) INFO: created DataGroup $dg_name (file=$source_file)" >> "$LOG_FILE"
        return 0
    else
        log_error "DataGroup $dg_name 建立失敗"
        echo "$timestamp $(uname -n) ERROR: failed to create DataGroup $dg_name" >> "$LOG_FILE"
        return 1
    fi
}

# =============================================================================
# 更新單一 DataGroup
# =============================================================================

update_single_datagroup() {
    local dg_name="$1"
    local source_file="$2"
    local timestamp=$(timestamp)

    log_info "處理 DataGroup: $dg_name"

    # 檢查檔案是否存在
    if [[ ! -f "$source_file" ]]; then
        log_error "來源檔案不存在: $source_file"
        echo "$timestamp $(uname -n) ERROR: source file not found: $source_file" >> "$LOG_FILE"
        return 1
    fi

    # 檢查檔案是否為空
    if [[ ! -s "$source_file" ]]; then
        log_warn "來源檔案為空，跳過: $source_file"
        return 0
    fi

    # 檢查 DataGroup 是否存在
    if ! datagroup_exists "$dg_name"; then
        log_info "DataGroup $dg_name 不存在，嘗試建立..."
        if ! create_datagroup "$dg_name" "$source_file"; then
            return 1
        fi
        return 0
    fi

    # DataGroup 已存在，執行更新
    if tmsh modify ltm data-group external "$dg_name" source-path "file:$source_file" 2>&1; then
        local record_count=$(wc -l < "$source_file")
        log_info "✓ DataGroup $dg_name 更新成功 ($record_count 筆記錄)"
        echo "$timestamp $(uname -n) INFO: updated DataGroup $dg_name ($record_count records, file=$source_file)" >> "$LOG_FILE"
        return 0
    else
        log_error "DataGroup $dg_name 更新失敗"
        echo "$timestamp $(uname -n) ERROR: failed to update DataGroup $dg_name" >> "$LOG_FILE"
        return 1
    fi
}

# =============================================================================
# 批次更新 DataGroups
# =============================================================================

update_all_datagroups() {
    local success_count=0
    local fail_count=0
    local skip_count=0

    log_info "=== 開始更新 F5 DataGroups ==="

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

    # 更新每個 zone 的 DataGroup
    for zone in "${zones[@]}"; do
        local source_file="${FINAL_OUTPUT_DIR}/${zone}.txt"

        if [[ -f "$source_file" && -s "$source_file" ]]; then
            if update_single_datagroup "$zone" "$source_file"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        else
            log_debug "跳過 $zone (檔案不存在或為空)"
            skip_count=$((skip_count + 1))
        fi
    done

    # 處理 IP DataGroup (rpzip) - 如果有資料的話
    local ip_file="${FINAL_OUTPUT_DIR}/rpzip.txt"
    if [[ -f "$ip_file" && -s "$ip_file" ]]; then
        if update_single_datagroup "rpzip" "$ip_file"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    else
        log_debug "跳過 rpzip (檔案不存在或為空)"
    fi

    log_info "=== 更新完成 ==="
    log_info "成功: $success_count 個, 失敗: $fail_count 個, 跳過: $skip_count 個"

    # 儲存配置 (如果有成功更新)
    if [[ $success_count -gt 0 ]]; then
        log_info "儲存 F5 配置..."
        if tmsh save sys config 2>&1; then
            log_info "✓ 配置已儲存"
        else
            log_warn "配置儲存失敗 (可能需要手動儲存)"
        fi
    fi

    return $fail_count
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    update_all_datagroups
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
