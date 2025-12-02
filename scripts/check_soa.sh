#!/bin/bash
# =============================================================================
# check_soa.sh - RPZ Zone SOA Serial 版本檢查
# =============================================================================
# 功能: 檢查 RPZ Zone 的 SOA Serial 是否有更新
#       如果沒有更新則跳過處理，節省資源
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOA_CACHE_DIR="${SOA_CACHE_DIR:-/config/snmp}"
DNSXDUMP_CMD="${DNSXDUMP_CMD:-/usr/local/bin/dnsxdump}"

# =============================================================================
# 取得指定 Zone 的 SOA Serial
# =============================================================================

get_zone_soa() {
    local zone_name="$1"

    log_debug "取得 $zone_name 的 SOA Serial"

    # 執行 dnsxdump 並擷取 SOA serial
    local soa_serial
    soa_serial=$($DNSXDUMP_CMD | grep "$zone_name" | grep SOA | awk '{print $7}' | head -1)

    if [[ -z "$soa_serial" ]]; then
        log_warn "無法取得 $zone_name 的 SOA Serial"
        return 1
    fi

    log_debug "Zone $zone_name SOA Serial: $soa_serial"
    echo "$soa_serial"
}

# =============================================================================
# 讀取上次記錄的 SOA Serial
# =============================================================================

get_cached_soa() {
    local zone_name="$1"
    local cache_file="${SOA_CACHE_DIR}/.${zone_name}_soa_serial.last"

    if [[ ! -f "$cache_file" ]]; then
        log_debug "SOA 快取檔案不存在: $cache_file"
        echo "0"
        return
    fi

    local cached_soa
    cached_soa=$(cat "$cache_file" 2>/dev/null || echo "0")
    log_debug "Zone $zone_name 快取的 SOA: $cached_soa"
    echo "$cached_soa"
}

# =============================================================================
# 儲存 SOA Serial 到快取
# =============================================================================

save_soa_cache() {
    local zone_name="$1"
    local soa_serial="$2"
    local cache_file="${SOA_CACHE_DIR}/.${zone_name}_soa_serial.last"

    ensure_dir "$SOA_CACHE_DIR"
    echo "$soa_serial" > "$cache_file"
    log_debug "已更新 SOA 快取: $cache_file (Serial: $soa_serial)"
}

# =============================================================================
# 檢查 Zone 是否需要更新
# =============================================================================

check_zone_update_needed() {
    local zone_name="$1"

    log_info "檢查 Zone 更新狀態: $zone_name"

    # 取得當前 SOA
    local current_soa
    if ! current_soa=$(get_zone_soa "$zone_name"); then
        log_error "無法取得 $zone_name 的 SOA Serial"
        return 2
    fi

    # 取得快取的 SOA
    local cached_soa
    cached_soa=$(get_cached_soa "$zone_name")

    # 初始化快取 (首次執行)
    if [[ "$cached_soa" == "0" ]]; then
        log_info "初始化 SOA 快取: $zone_name (Serial: $current_soa)"
        save_soa_cache "$zone_name" "$current_soa"
        return 0
    fi

    # 比對 SOA Serial
    if [[ "$current_soa" -le "$cached_soa" ]]; then
        log_info "Zone $zone_name 無變更 (快取: $cached_soa, 當前: $current_soa)"
        return 1
    fi

    # 有更新
    log_info "Zone $zone_name 有更新 (快取: $cached_soa, 當前: $current_soa)"
    save_soa_cache "$zone_name" "$current_soa"
    return 0
}

# =============================================================================
# 批次檢查多個 Zones
# =============================================================================

check_all_zones() {
    local zone_config="${1:-${PROJECT_ROOT}/config/zonelist.txt}"
    local update_needed=0

    log_info "=== 開始批次檢查 Zones ==="

    [[ -f "$zone_config" ]] || die "Zone 配置檔案不存在: $zone_config"

    while IFS= read -r zone; do
        [[ -z "$zone" ]] && continue
        [[ "$zone" =~ ^# ]] && continue

        # 移除可能的空白
        zone=$(echo "$zone" | xargs)

        if check_zone_update_needed "$zone"; then
            update_needed=1
        fi
    done < "$zone_config"

    if [[ $update_needed -eq 1 ]]; then
        log_info "至少有一個 Zone 需要更新"
        echo "UPDATE_NEEDED"
        return 0
    else
        log_info "所有 Zones 均無變更"
        # 輸出狀態字串並返回 0（避免 F5 iCall scriptd 誤判）
        echo "NO_UPDATE"
        return 0
    fi
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local mode="${1:-check}"
    local zone_name="${2:-}"

    case "$mode" in
        check)
            # 檢查單一 Zone
            if [[ -z "$zone_name" ]]; then
                die "用法: $0 check <zone_name>"
            fi
            check_zone_update_needed "$zone_name"
            ;;

        check-all)
            # 檢查所有 Zones
            check_all_zones
            ;;

        get)
            # 僅取得 SOA Serial
            if [[ -z "$zone_name" ]]; then
                die "用法: $0 get <zone_name>"
            fi
            get_zone_soa "$zone_name"
            ;;

        reset)
            # 重置快取
            if [[ -z "$zone_name" ]]; then
                log_warn "清除所有 Zone 的 SOA 快取"
                rm -f "${SOA_CACHE_DIR}"/.*.last
            else
                log_warn "清除 $zone_name 的 SOA 快取"
                rm -f "${SOA_CACHE_DIR}/.${zone_name}_soa_serial.last"
            fi
            ;;

        *)
            echo "用法: $0 {check|check-all|get|reset} [zone_name]"
            echo ""
            echo "指令:"
            echo "  check <zone>    - 檢查指定 Zone 是否需要更新"
            echo "  check-all       - 檢查所有 Zones"
            echo "  get <zone>      - 取得指定 Zone 的 SOA Serial"
            echo "  reset [zone]    - 重置 SOA 快取"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi