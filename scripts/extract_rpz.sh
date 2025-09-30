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
ZONE_CONFIG="${PROJECT_ROOT}/config/rpz_zones.conf"
OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"
RAW_DATA_DIR="${OUTPUT_DIR}/raw"

# =============================================================================
# 從 DNS Express 提取單一 Zone
# =============================================================================

extract_zone() {
    local zone_name="$1"
    log_info "提取 Zone: $zone_name"

    # TODO: 實作實際的提取邏輯
    # 方法 1: 使用 tmsh 指令
    # tmsh list ltm dns zone "$zone_name" -detail > "${RAW_DATA_DIR}/${zone_name}.raw"

    # 方法 2: 直接讀取 zone 檔案 (如果知道路徑)
    # cat "/path/to/dns/express/${zone_name}" > "${RAW_DATA_DIR}/${zone_name}.raw"

    log_debug "Zone 資料已儲存至: ${RAW_DATA_DIR}/${zone_name}.raw"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始提取 RPZ 資料 ==="

    # 建立輸出目錄
    ensure_dir "$RAW_DATA_DIR"

    # 檢查配置檔案
    [[ -f "$ZONE_CONFIG" ]] || die "Zone 配置檔案不存在: $ZONE_CONFIG"

    # 讀取並處理每個 Zone
    local zone_count=0
    while IFS= read -r zone; do
        [[ -z "$zone" ]] && continue
        [[ "$zone" =~ ^# ]] && continue

        extract_zone "$zone"
        ((zone_count++))
    done < "$ZONE_CONFIG"

    log_info "完成提取 $zone_count 個 Zones"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi