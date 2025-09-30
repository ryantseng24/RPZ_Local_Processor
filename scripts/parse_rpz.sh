#!/bin/bash
# =============================================================================
# parse_rpz.sh - 解析 RPZ 記錄
# =============================================================================
# 功能:
# 1. 解析 FQDN 類型 RPZ 記錄 (A record)
# 2. 解析 IP 類型 RPZ 記錄 (CNAME with rpz-ip)
# 3. 根據 Landing IP 分類 FQDN 記錄
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
# AWK 主解析邏輯 (移植自原始程式碼)
# =============================================================================

parse_rpz_records() {
    local input_file="$1"
    local rpz_output="$2"
    local phishtw_output="$3"
    local ip_output="$4"

    log_info "解析 RPZ 記錄: $(basename "$input_file")"

    awk -v rpz_file="$rpz_output" \
        -v phishtw_file="$phishtw_output" \
        -v ip_file="$ip_output" '
    {
        # 僅處理 IN class 記錄
        if ($3 == "IN") {

            # ===== 處理 FQDN 類型 (A 記錄) =====
            if ($4 == "A" && substr($1,1,1) != "*") {

                # rpztw zone
                if ($1 ~ /\.rpztw\.?$/) {
                    sub(/\.rpztw\.$/, "", $1)
                    rpz[$1] = $5
                }
                # phishtw zone
                else if ($1 ~ /\.phishtw\.?$/) {
                    sub(/\.phishtw\.$/, "", $1)
                    phishtw[$1] = $5
                }
            }

            # ===== 處理 IP 類型 (rpz-ip CNAME) =====
            else if ($4 == "CNAME" && index($1, "rpz-ip.rpztw.") > 0) {
                # 移除 rpz-ip.rpztw 後綴
                sub(/\.rpz-ip\.rpztw\.$/, "", $1)

                # 分割為 IP 部分
                split($1, ip_parts, ".")

                # 至少需要 5 個部分 (netmask + 4 個 IP octets)
                if (length(ip_parts) >= 5) {
                    # 第一個是 netmask
                    netmask = ip_parts[1]

                    # 反轉 IP (parts 5,4,3,2)
                    reversed_ip = ip_parts[5] "." ip_parts[4] "." ip_parts[3] "." ip_parts[2]

                    # 儲存為 network/mask
                    iplist[reversed_ip "/" netmask] = 1
                }
            }
        }
    }
    END {
        # 輸出 rpztw FQDN
        for (d in rpz) {
            print "\"" d "\" := \"" rpz[d] "\"," > rpz_file
        }

        # 輸出 phishtw FQDN
        for (d in phishtw) {
            print "\"" d "\" := \"" phishtw[d] "\"," > phishtw_file
        }

        # 輸出 IP 網段
        for (n in iplist) {
            print "network " n "," > ip_file
        }
    }' "$input_file"

    # 統計結果
    local rpz_count=$(wc -l < "$rpz_output" 2>/dev/null || echo "0")
    local phishtw_count=$(wc -l < "$phishtw_output" 2>/dev/null || echo "0")
    local ip_count=$(wc -l < "$ip_output" 2>/dev/null || echo "0")

    log_info "解析完成: rpztw=$rpz_count, phishtw=$phishtw_count, ip=$ip_count"
}

# =============================================================================
# 根據 Landing IP 分類 FQDN (進階版)
# =============================================================================

classify_by_landing_ip() {
    local rpz_file="$1"
    local mapping_config="${PROJECT_ROOT}/config/datagroup_mapping.conf"
    local output_dir="$PARSED_DATA_DIR"

    log_info "根據 Landing IP 分類 FQDN"

    [[ -f "$mapping_config" ]] || die "映射配置不存在: $mapping_config"
    [[ -f "$rpz_file" ]] || die "RPZ 檔案不存在: $rpz_file"

    # 清空或建立分類輸出檔案
    while IFS='=' read -r landing_ip dg_name; do
        [[ -z "$landing_ip" ]] && continue
        [[ "$landing_ip" =~ ^# ]] && continue

        landing_ip=$(echo "$landing_ip" | xargs)
        dg_name=$(echo "$dg_name" | xargs)

        > "${output_dir}/${dg_name}.fqdn"
    done < "$mapping_config"

    # 分類 FQDN
    while IFS='=' read -r landing_ip dg_name; do
        [[ -z "$landing_ip" ]] && continue
        [[ "$landing_ip" =~ ^# ]] && continue

        landing_ip=$(echo "$landing_ip" | xargs)
        dg_name=$(echo "$dg_name" | xargs)

        # 從 rpz_file 中篩選出對應 landing_ip 的 FQDN
        grep ":= \"${landing_ip}\"" "$rpz_file" > "${output_dir}/${dg_name}.fqdn" || true

        local count=$(wc -l < "${output_dir}/${dg_name}.fqdn" 2>/dev/null || echo "0")
        log_debug "$dg_name: $count 個 FQDN (Landing IP: $landing_ip)"
    done < "$mapping_config"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local timestamp_compact=$(timestamp_compact)

    log_info "=== 開始解析 RPZ 記錄 ==="

    # 建立輸出目錄
    ensure_dir "$PARSED_DATA_DIR"

    # 檢查是否有 dnsxdump 輸出
    local dnsxdump_file
    if [[ -n "${DNSXDUMP_FILE:-}" && -f "$DNSXDUMP_FILE" ]]; then
        dnsxdump_file="$DNSXDUMP_FILE"
    else
        # 尋找最新的 dnsxdump 檔案
        dnsxdump_file=$(ls -t "${RAW_DATA_DIR}"/dnsxdump_*.out 2>/dev/null | head -1)
        [[ -f "$dnsxdump_file" ]] || die "找不到 dnsxdump 輸出檔案"
    fi

    log_info "使用 dnsxdump 檔案: $dnsxdump_file"

    # 定義輸出檔案
    local rpz_output="${PARSED_DATA_DIR}/rpz_${timestamp_compact}.txt"
    local phishtw_output="${PARSED_DATA_DIR}/phishtw_${timestamp_compact}.txt"
    local ip_output="${PARSED_DATA_DIR}/ip_${timestamp_compact}.txt"

    # 執行 AWK 解析
    parse_rpz_records "$dnsxdump_file" "$rpz_output" "$phishtw_output" "$ip_output"

    # 進階分類 (根據 Landing IP)
    if [[ -f "${PROJECT_ROOT}/config/datagroup_mapping.conf" ]]; then
        classify_by_landing_ip "$rpz_output"
    else
        log_warn "未找到 Landing IP 映射配置，跳過分類"
    fi

    log_info "=== 解析完成 ==="

    # 設定全域變數供後續使用
    export RPZ_PARSED_FILE="$rpz_output"
    export PHISHTW_PARSED_FILE="$phishtw_output"
    export IP_PARSED_FILE="$ip_output"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi