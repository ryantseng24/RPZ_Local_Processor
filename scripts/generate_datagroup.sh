#!/bin/bash
# =============================================================================
# generate_datagroup.sh - 產生 F5 External DataGroup 檔案
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
OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
FINAL_OUTPUT_DIR="${OUTPUT_DIR}/final"

# =============================================================================
# 整理 DataGroup 檔案到最終目錄
# =============================================================================

prepare_final_datagroups() {
    log_info "整理 DataGroup 檔案到最終目錄"

    # 建立最終輸出目錄
    ensure_dir "$FINAL_OUTPUT_DIR"

    # 取得最新的解析檔案
    local rpz_file phishtw_file ip_file

    if [[ -n "${RPZ_PARSED_FILE:-}" && -f "$RPZ_PARSED_FILE" ]]; then
        rpz_file="$RPZ_PARSED_FILE"
    else
        rpz_file=$(ls -t "${PARSED_DATA_DIR}"/rpz_*.txt 2>/dev/null | head -1)
    fi

    if [[ -n "${PHISHTW_PARSED_FILE:-}" && -f "$PHISHTW_PARSED_FILE" ]]; then
        phishtw_file="$PHISHTW_PARSED_FILE"
    else
        phishtw_file=$(ls -t "${PARSED_DATA_DIR}"/phishtw_*.txt 2>/dev/null | head -1)
    fi

    if [[ -n "${IP_PARSED_FILE:-}" && -f "$IP_PARSED_FILE" ]]; then
        ip_file="$IP_PARSED_FILE"
    else
        ip_file=$(ls -t "${PARSED_DATA_DIR}"/ip_*.txt 2>/dev/null | head -1)
    fi

    # 複製到最終目錄（使用固定檔名供 F5 引用）
    local count=0

    if [[ -f "$rpz_file" ]]; then
        cp "$rpz_file" "${FINAL_OUTPUT_DIR}/rpz.txt"
        log_info "✓ RPZ DataGroup: ${FINAL_OUTPUT_DIR}/rpz.txt ($(wc -l < "$rpz_file") 筆)"
        ((count++))
    else
        log_warn "找不到 RPZ 解析檔案"
    fi

    if [[ -f "$phishtw_file" ]]; then
        cp "$phishtw_file" "${FINAL_OUTPUT_DIR}/phishtw.txt"
        log_info "✓ PhishTW DataGroup: ${FINAL_OUTPUT_DIR}/phishtw.txt ($(wc -l < "$phishtw_file") 筆)"
        ((count++))
    else
        log_debug "找不到 PhishTW 解析檔案（可能沒有此 Zone）"
    fi

    if [[ -f "$ip_file" ]]; then
        cp "$ip_file" "${FINAL_OUTPUT_DIR}/rpzip.txt"
        log_info "✓ IP DataGroup: ${FINAL_OUTPUT_DIR}/rpzip.txt ($(wc -l < "$ip_file") 筆)"
        ((count++))
    else
        log_debug "找不到 IP 解析檔案（可能沒有 IP 記錄）"
    fi

    if [[ $count -eq 0 ]]; then
        die "沒有找到任何解析檔案"
    fi

    log_info "共產生 $count 個 DataGroup 檔案"

    # 設定全域變數供 update_datagroup.sh 使用
    export FINAL_RPZ_FILE="${FINAL_OUTPUT_DIR}/rpz.txt"
    export FINAL_PHISHTW_FILE="${FINAL_OUTPUT_DIR}/phishtw.txt"
    export FINAL_IP_FILE="${FINAL_OUTPUT_DIR}/rpzip.txt"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始產生 DataGroup 檔案 ==="

    prepare_final_datagroups

    log_info "=== DataGroup 檔案產生完成 ==="
    log_info "檔案位置: $FINAL_OUTPUT_DIR"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi