#!/bin/bash
# =============================================================================
# parse_rpz.sh - 解析 RPZ 記錄
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
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"

# =============================================================================
# 解析 FQDN 類型記錄
# =============================================================================

parse_fqdn_records() {
    local zone_file="$1"
    local output_file="$2"

    log_info "解析 FQDN 記錄: $(basename "$zone_file")"

    # TODO: 實作 FQDN 解析邏輯
    # 範例格式:
    # malicious.com.rpztw. IN CNAME .
    # -> 提取 malicious.com 和對應的 Landing IP

    > "$output_file"  # 清空輸出檔案

    log_debug "FQDN 記錄已儲存至: $output_file"
}

# =============================================================================
# 解析 IP 類型記錄
# =============================================================================

parse_ip_records() {
    local zone_file="$1"
    local output_file="$2"

    log_info "解析 IP 記錄: $(basename "$zone_file")"

    # TODO: 實作 IP 解析邏輯
    # 範例格式:
    # 32.1.2.3.4.rpz-ip IN CNAME .
    # -> 提取 1.2.3.4/32

    > "$output_file"  # 清空輸出檔案

    log_debug "IP 記錄已儲存至: $output_file"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始解析 RPZ 記錄 ==="

    # 建立輸出目錄
    ensure_dir "$PARSED_DATA_DIR"

    # 處理所有原始檔案
    local file_count=0
    for raw_file in "${RAW_DATA_DIR}"/*.raw; do
        [[ -f "$raw_file" ]] || continue

        local basename=$(basename "$raw_file" .raw)
        local fqdn_output="${PARSED_DATA_DIR}/${basename}_fqdn.txt"
        local ip_output="${PARSED_DATA_DIR}/${basename}_ip.txt"

        parse_fqdn_records "$raw_file" "$fqdn_output"
        parse_ip_records "$raw_file" "$ip_output"

        ((file_count++))
    done

    log_info "完成解析 $file_count 個 Zone 檔案"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi