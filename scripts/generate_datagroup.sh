#!/bin/bash
# =============================================================================
# generate_datagroup.sh - 產生 F5 External DataGroup 檔案 (動態 Zone 支援)
# =============================================================================
# 功能: 將解析後的檔案整理到最終輸出目錄
# 輸出格式已由 parse_rpz.sh 產生，此腳本僅負責檔案管理
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
FINAL_OUTPUT_DIR="${OUTPUT_DIR}/final"
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
# 整理 DataGroup 檔案到最終目錄
# =============================================================================

prepare_final_datagroups() {
    log_info "整理 DataGroup 檔案到最終目錄"

    # 建立最終輸出目錄
    ensure_dir "$FINAL_OUTPUT_DIR"

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

    # -------------------------------------------------------------------------
    # 第一階段：解析所有來源檔案，全部確認齊全才進入發布階段。
    #
    # 找不到 parsed artifact 必須硬失敗。原版靠 ls 的非零退出碼 + pipefail
    # 達到這個效果；改用 find_newest_file 後必須明確 die，不可讓 missing
    # artifact 落入 touch final 的成功分支。
    # 兩階段的目的是避免「前面的 zone 已經 cp 完、後面的 zone 缺檔才 die」
    # 造成 final/ 部分發布。
    # 參見 CODE_REVIEW_20260821.md CR-01。
    # -------------------------------------------------------------------------
    local -a src_zone=() src_file=()
    local zone parsed_file
    for zone in "${zones[@]}"; do
        if ! parsed_file=$(find_newest_file "${PARSED_DATA_DIR}/${zone}_"*.txt); then
            die "找不到 ${zone} 的解析檔案: ${PARSED_DATA_DIR}/${zone}_*.txt"
        fi
        [[ -f "$parsed_file" ]] || die "${zone} 的解析檔案不存在: $parsed_file"

        if [[ ! -s "$parsed_file" ]]; then
            log_warn "${zone} 的解析檔案為 0 bytes: $parsed_file"
        fi

        src_zone+=("$zone")
        src_file+=("$parsed_file")
    done

    # rpzip 的 artifact 必須存在，但允許內容為空 (目前來源沒有 IP 類型記錄)
    local ip_file
    if ! ip_file=$(find_newest_file "${PARSED_DATA_DIR}"/rpzip_*.txt); then
        die "找不到 rpzip 的解析檔案: ${PARSED_DATA_DIR}/rpzip_*.txt"
    fi
    [[ -f "$ip_file" ]] || die "rpzip 的解析檔案不存在: $ip_file"

    # -------------------------------------------------------------------------
    # 第二階段：發布
    #
    # 注意：這裡【不是】完整的 publish transaction。第一階段確保「缺 artifact
    # 時不會部分發布」，但發布階段仍是逐一 cp/touch 正式檔案，若某次 cp 中途
    # 失敗，前面已寫入的 final 檔案不會回復。
    # 完整的原子發布（temp + rename、run manifest、資料完整性門檻）屬於
    # CODE_REVIEW_20260821.md 的 CR-10，尚未實作。
    # 參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md 第 9.1 節。
    # -------------------------------------------------------------------------
    local count=0 i=0 record_count
    while [[ $i -lt ${#src_zone[@]} ]]; do
        cp "${src_file[$i]}" "${FINAL_OUTPUT_DIR}/${src_zone[$i]}.txt"
        record_count=$(wc -l < "${src_file[$i]}")
        log_info "✓ ${src_zone[$i]} DataGroup: ${FINAL_OUTPUT_DIR}/${src_zone[$i]}.txt ($record_count 筆)"
        count=$((count + 1))
        i=$((i + 1))
    done

    if [[ -s "$ip_file" ]]; then
        cp "$ip_file" "${FINAL_OUTPUT_DIR}/rpzip.txt"
        local ip_count
        ip_count=$(wc -l < "$ip_file")
        log_info "✓ rpzip DataGroup: ${FINAL_OUTPUT_DIR}/rpzip.txt ($ip_count 筆)"
        count=$((count + 1))
    else
        touch "${FINAL_OUTPUT_DIR}/rpzip.txt"
        log_debug "  rpzip: 無記錄 (建立空檔案)"
    fi

    if [[ $count -eq 0 ]]; then
        log_warn "沒有找到任何有效的解析檔案"
    fi

    log_info "共產生 $count 個有效的 DataGroup 檔案"

    # 設定全域變數供 update_datagroup.sh 使用
    export FINAL_OUTPUT_DIR
    export PROCESSED_ZONES="${zones[*]}"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始產生 DataGroup 檔案 ==="

    prepare_final_datagroups

    log_info "=== DataGroup 檔案產生完成 ==="
    log_info "檔案位置: $FINAL_OUTPUT_DIR"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
