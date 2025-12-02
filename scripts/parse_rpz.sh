#!/bin/bash
# =============================================================================
# parse_rpz.sh - 解析 RPZ 記錄 (動態 Zone 支援)
# =============================================================================
# 功能:
# 1. 從 zonelist.txt 讀取要處理的 zones
# 2. 解析 FQDN 類型 RPZ 記錄 (A record) -> key := value 格式
# 3. 解析 IP 類型 RPZ 記錄 (CNAME with rpz-ip) -> network 格式
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
RAW_DATA_DIR="${OUTPUT_DIR}/raw"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
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
# 將 zone 名稱轉換為正則表達式安全格式
# =============================================================================

escape_zone_for_regex() {
    local zone="$1"
    # 將 . 轉義為 \.
    echo "$zone" | sed 's/\./\\./g'
}

# =============================================================================
# AWK 動態解析邏輯
# =============================================================================
# 輸出格式:
# - FQDN: "domain" := "landing_ip",
# - IP:   network ip/mask,
# =============================================================================

parse_rpz_records() {
    local input_file="$1"
    local output_dir="$2"
    local timestamp="$3"
    shift 3
    local zones=("$@")

    log_info "解析 RPZ 記錄: $(basename "$input_file")"
    log_info "處理 Zones: ${zones[*]}"

    # 建立 AWK zones 參數 (用 | 分隔，包含原始名稱和 regex 安全格式)
    # 格式: zone1|escaped1 zone2|escaped2 ...
    local zone_list=""
    for zone in "${zones[@]}"; do
        local escaped_zone
        escaped_zone=$(escape_zone_for_regex "$zone")
        zone_list="${zone_list}${zone}|${escaped_zone} "
    done

    awk -v zone_list="$zone_list" \
        -v output_dir="$output_dir" \
        -v timestamp="$timestamp" '
    BEGIN {
        # 解析 zone 清單
        n = split(zone_list, zone_entries, " ")
        for (i = 1; i <= n; i++) {
            if (zone_entries[i] != "") {
                # 分割 zone|escaped_zone
                split(zone_entries[i], parts, "|")
                zone_name = parts[1]
                zone_escaped = parts[2]
                zone_names[zone_name] = zone_escaped
            }
        }
    }
    {
        # 僅處理 IN class 記錄
        if ($3 == "IN") {

            # ===== 處理 FQDN 類型 (A 記錄) =====
            if ($4 == "A") {
                # 遍歷所有 zones
                for (zone in zone_names) {
                    zone_escaped = zone_names[zone]
                    zone_pattern = "\\." zone_escaped "\\.$"

                    if ($1 ~ zone_pattern) {
                        # 移除 zone 後綴 (使用 escaped 版本)
                        sub("\\." zone_escaped "\\.$", "", $1)

                        # 構建 key (zone + SUBSEP + domain)
                        if (substr($1, 1, 2) == "*.") {
                            # 萬用字元記錄 - 加前綴點
                            domain = substr($1, 3)
                            key = zone SUBSEP "." domain
                        } else {
                            # 精確記錄
                            key = zone SUBSEP $1
                        }
                        zone_data[key] = $5
                        break
                    }
                }
            }

            # ===== 處理 IP 類型 (rpz-ip CNAME) =====
            else if ($4 == "CNAME") {
                for (zone in zone_names) {
                    zone_escaped = zone_names[zone]
                    ip_pattern = "rpz-ip\\." zone_escaped "\\."

                    if (index($1, "rpz-ip." zone ".") > 0) {
                        # 移除 rpz-ip.zone 後綴
                        sub("\\.rpz-ip\\." zone_escaped "\\.$", "", $1)

                        # 分割為 IP 部分
                        split($1, ip_parts, ".")

                        # 至少需要 5 個部分 (netmask + 4 個 IP octets)
                        if (length(ip_parts) >= 5) {
                            netmask = ip_parts[1]
                            reversed_ip = ip_parts[5] "." ip_parts[4] "." ip_parts[3] "." ip_parts[2]
                            iplist[reversed_ip "/" netmask] = 1
                        }
                        break
                    }
                }
            }
        }
    }
    END {
        # 輸出各 zone 的 FQDN (key := value 格式)
        for (zone in zone_names) {
            output_file = output_dir "/" zone "_" timestamp ".txt"
            count = 0

            # 遍歷所有 zone_data，找出屬於此 zone 的記錄
            for (key in zone_data) {
                # 分割 key 為 zone 和 domain
                split(key, key_parts, SUBSEP)
                if (key_parts[1] == zone) {
                    domain = key_parts[2]
                    ip = zone_data[key]
                    print "\"" domain "\" := \"" ip "\"," > output_file
                    count++
                }
            }

            if (count > 0) {
                printf "ZONE_COUNT:%s=%d\n", zone, count > "/dev/stderr"
            }
        }

        # 輸出 IP 網段 (network 格式)
        ip_output_file = output_dir "/rpzip_" timestamp ".txt"
        ip_count = 0
        for (n in iplist) {
            print "network " n "," > ip_output_file
            ip_count++
        }
        if (ip_count > 0) {
            printf "ZONE_COUNT:rpzip=%d\n", ip_count > "/dev/stderr"
        }
    }' "$input_file" 2>&1 | while read -r line; do
        if [[ "$line" =~ ^ZONE_COUNT:(.+)=([0-9]+)$ ]]; then
            local zname="${BASH_REMATCH[1]}"
            local zcount="${BASH_REMATCH[2]}"
            log_info "  - $zname: $zcount 筆"
        fi
    done

    # 確保所有輸出檔案都存在（即使為空）
    for zone in "${zones[@]}"; do
        touch "${output_dir}/${zone}_${timestamp}.txt"
    done
    touch "${output_dir}/rpzip_${timestamp}.txt"

    log_info "解析完成"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local timestamp_compact=$(timestamp_compact)

    log_info "=== 開始解析 RPZ 記錄 ==="

    # 讀取 zone 清單
    local zone_list_str
    zone_list_str=$(get_zone_list)

    if [[ -z "$zone_list_str" ]]; then
        die "Zone 清單為空"
    fi

    # 轉換為陣列
    read -ra ZONES <<< "$zone_list_str"
    log_info "載入 ${#ZONES[@]} 個 Zones: ${ZONES[*]}"

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

    # 執行 AWK 解析
    parse_rpz_records "$dnsxdump_file" "$PARSED_DATA_DIR" "$timestamp_compact" "${ZONES[@]}"

    log_info "=== 解析完成 ==="
    log_info "輸出目錄: $PARSED_DATA_DIR"

    # 設定全域變數供後續使用
    export PARSED_TIMESTAMP="$timestamp_compact"
    export PARSED_ZONES="${ZONES[*]}"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
