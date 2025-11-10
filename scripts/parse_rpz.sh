#!/bin/bash
# =============================================================================
# parse_rpz.sh - 解析 RPZ 記錄
# =============================================================================
# 功能:
# 1. 解析 FQDN 類型 RPZ 記錄 (A record) -> key := value 格式
# 2. 解析 IP 類型 RPZ 記錄 (CNAME with rpz-ip) -> network 格式
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
# 輸出格式:
# - FQDN: "domain" := "landing_ip",
# - IP:   network ip/mask,
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
            if ($4 == "A") {

                # rpztw zone
                if ($1 ~ /\.rpztw\.?$/) {
                    sub(/\.rpztw\.$/, "", $1)

                    # 檢查是否為萬用字元記錄 (*.domain)
                    if (substr($1, 1, 2) == "*.") {
                        # 移除 "*." 前綴，取得 domain
                        domain = substr($1, 3)
                        # 只產生萬用字元記錄（加前綴點）
                        rpz["." domain] = $5
                    } else {
                        # 一般精確記錄（不加前綴點）
                        rpz[$1] = $5
                    }
                }
                # phishtw zone
                else if ($1 ~ /\.phishtw\.?$/) {
                    sub(/\.phishtw\.$/, "", $1)

                    # 同樣處理萬用字元
                    if (substr($1, 1, 2) == "*.") {
                        domain = substr($1, 3)
                        # 只產生萬用字元記錄
                        phishtw["." domain] = $5
                    } else {
                        # 精確記錄
                        phishtw[$1] = $5
                    }
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
        # 輸出 rpztw FQDN (key := value 格式)
        for (d in rpz) {
            print "\"" d "\" := \"" rpz[d] "\"," > rpz_file
        }

        # 輸出 phishtw FQDN (key := value 格式)
        for (d in phishtw) {
            print "\"" d "\" := \"" phishtw[d] "\"," > phishtw_file
        }

        # 輸出 IP 網段 (network 格式)
        for (n in iplist) {
            print "network " n "," > ip_file
        }
    }' "$input_file"

    # 確保所有輸出檔案都存在（即使為空）
    touch "$rpz_output" "$phishtw_output" "$ip_output"

    # 統計結果
    local rpz_count=$(wc -l < "$rpz_output" 2>/dev/null || echo "0")
    local phishtw_count=$(wc -l < "$phishtw_output" 2>/dev/null || echo "0")
    local ip_count=$(wc -l < "$ip_output" 2>/dev/null || echo "0")

    log_info "解析完成: rpztw=$rpz_count 筆, phishtw=$phishtw_count 筆, ip=$ip_count 筆"
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

    log_info "=== 解析完成 ==="
    log_info "輸出檔案:"
    log_info "  - RPZ FQDN: $rpz_output"
    log_info "  - PhishTW FQDN: $phishtw_output"
    log_info "  - IP 網段: $ip_output"

    # 設定全域變數供後續使用
    export RPZ_PARSED_FILE="$rpz_output"
    export PHISHTW_PARSED_FILE="$phishtw_output"
    export IP_PARSED_FILE="$ip_output"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi