#!/bin/bash
# =============================================================================
# generate_datagroup.sh - 產生 F5 External DataGroup 檔案
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MAPPING_CONFIG="${PROJECT_ROOT}/config/datagroup_mapping.conf"
OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
DG_OUTPUT_DIR="${OUTPUT_DIR}/datagroups"

# =============================================================================
# 產生 FQDN DataGroup
# =============================================================================

generate_fqdn_datagroup() {
    local landing_ip="$1"
    local dg_name="$2"
    local output_file="${DG_OUTPUT_DIR}/${dg_name}.txt"

    log_info "產生 FQDN DataGroup: $dg_name (Landing IP: $landing_ip)"

    # TODO: 從解析資料中篩選對應 Landing IP 的 FQDN
    # 格式: "fqdn" := "action",
    # 範例:
    # "malicious.com" := "drop",
    # "phishing.net" := "drop",

    > "$output_file"  # 清空檔案

    log_debug "DataGroup 已產生: $output_file"
}

# =============================================================================
# 產生 IP DataGroup
# =============================================================================

generate_ip_datagroup() {
    local dg_name="$1"
    local output_file="${DG_OUTPUT_DIR}/${dg_name}.txt"

    log_info "產生 IP DataGroup: $dg_name"

    # TODO: 合併所有 IP 記錄
    # 格式:
    # network 1.2.3.0/24 := "drop",
    # host 4.5.6.7 := "drop",

    > "$output_file"  # 清空檔案

    log_debug "IP DataGroup 已產生: $output_file"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始產生 DataGroup 檔案 ==="

    # 建立輸出目錄
    ensure_dir "$DG_OUTPUT_DIR"

    # 檢查配置檔案
    [[ -f "$MAPPING_CONFIG" ]] || die "映射配置檔案不存在: $MAPPING_CONFIG"

    # 讀取 Landing IP 映射並產生對應的 DataGroup
    local dg_count=0
    while IFS='=' read -r landing_ip dg_name; do
        [[ -z "$landing_ip" ]] && continue
        [[ "$landing_ip" =~ ^# ]] && continue

        landing_ip=$(echo "$landing_ip" | xargs)  # 去除空白
        dg_name=$(echo "$dg_name" | xargs)

        generate_fqdn_datagroup "$landing_ip" "$dg_name"
        ((dg_count++))
    done < "$MAPPING_CONFIG"

    # 產生合併的 IP DataGroup
    generate_ip_datagroup "dg_rpzip"

    log_info "完成產生 $((dg_count + 1)) 個 DataGroup 檔案"
    log_info "輸出目錄: $DG_OUTPUT_DIR"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi