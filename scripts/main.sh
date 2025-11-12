#!/bin/bash
# =============================================================================
# main.sh - RPZ Local Processor 主執行腳本
# =============================================================================
# 完整流程:
# 1. 檢查 SOA Serial 是否變更
# 2. 從 DNS Express 提取 RPZ 資料
# 3. 解析 RPZ 記錄 (FQDN + IP)
# 4. 產生 DataGroup 檔案
# 5. 更新 F5 DataGroups
# 6. 清理臨時檔案
# =============================================================================

set -euo pipefail

# 取得腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 載入工具函數
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

CONFIG_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"
OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"
LOG_FILE="${LOG_FILE:-/var/log/ltm}"

# 是否清理臨時檔案 (預設: 是)
CLEANUP_TEMP="${CLEANUP_TEMP:-true}"

# 是否強制執行 (跳過 SOA 檢查)
FORCE_RUN="${FORCE_RUN:-false}"

# =============================================================================
# 初始化
# =============================================================================

init() {
    log_info "=========================================="
    log_info "  RPZ Local Processor 啟動"
    log_info "=========================================="
    log_info "專案根目錄: $PROJECT_ROOT"
    log_info "輸出目錄: $OUTPUT_DIR"
    log_info "日誌檔案: $LOG_FILE"

    # 建立必要目錄
    ensure_dir "$LOG_DIR"
    ensure_dir "$OUTPUT_DIR"

    # 檢查必要指令
    check_command "bash"
    check_command "awk"
    check_command "sed"
    check_command "grep"

    # 檢查 F5 特定指令
    if ! command -v tmsh >/dev/null 2>&1; then
        log_warn "tmsh 指令不存在，可能不在 F5 環境中"
    fi

    if ! command -v /usr/local/bin/dnsxdump >/dev/null 2>&1; then
        log_warn "dnsxdump 指令不存在，可能不在 F5 DNS 環境中"
    fi
}

# =============================================================================
# 清理臨時檔案
# =============================================================================

cleanup() {
    if [[ "$CLEANUP_TEMP" != "true" ]]; then
        log_info "跳過清理臨時檔案"
        return 0
    fi

    log_info "清理臨時檔案..."

    # 清理超過 7 天的舊檔案
    find "$OUTPUT_DIR" -type f -mtime +7 -delete 2>/dev/null || true
    log_info "清理舊檔案完成"

    # 清理當前執行產生的中間檔案
    if [[ -n "${DNSXDUMP_FILE:-}" && -f "$DNSXDUMP_FILE" ]]; then
        rm -f "$DNSXDUMP_FILE" || true
        log_info "清理 dnsxdump 檔案完成"
    fi

    log_info "cleanup 函數完成"
    return 0
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    local start_time=$(date +%s)
    local timestamp=$(timestamp)

    # 初始化
    init

    # 步驟 1: 檢查 SOA Serial 變更
    log_info ""
    log_info "步驟 1/5: 檢查 RPZ Zone SOA Serial"

    if [[ "$FORCE_RUN" == "true" ]]; then
        log_warn "強制執行模式，跳過 SOA 檢查"
    else
        # 執行 SOA 檢查並捕獲輸出
        # 輸出: UPDATE_NEEDED=需要更新, NO_UPDATE=無需更新
        local soa_check_output
        soa_check_output=$(bash "${SCRIPT_DIR}/check_soa.sh" check-all 2>&1 | grep -E '^(UPDATE_NEEDED|NO_UPDATE)$' | tail -1)
        local soa_check_exit=$?

        if [[ "$soa_check_output" == "NO_UPDATE" ]]; then
            # SOA 未變更，無需更新（這是正常情況，不是錯誤）
            log_info "SOA Serial 未變更，無需更新"
            echo "$timestamp $(uname -n) INFO: RPZ SOA not changed, skip update" >> "$LOG_FILE"
            exit 0
        elif [[ "$soa_check_output" != "UPDATE_NEEDED" ]]; then
            # 檢查失敗或輸出異常
            log_error "SOA 檢查失敗或輸出異常（退出碼: $soa_check_exit, 輸出: '$soa_check_output'）"
            echo "$timestamp $(uname -n) ERROR: RPZ SOA check failed" >> "$LOG_FILE"
            exit 1
        fi

        # SOA 已變更，繼續處理
        log_info "SOA Serial 已變更，繼續處理"
        echo "$timestamp $(uname -n) INFO: RPZ SOA changed, start processing" >> "$LOG_FILE"
    fi

    # 步驟 2: 從 DNS Express 提取 RPZ 資料
    log_info ""
    log_info "步驟 2/5: 提取 DNS Express 資料"
    if ! bash "${SCRIPT_DIR}/extract_rpz.sh"; then
        log_error "資料提取失敗"
        echo "$timestamp $(uname -n) ERROR: RPZ extraction failed" >> "$LOG_FILE"
        exit 1
    fi

    # 步驟 3: 解析 RPZ 記錄
    log_info ""
    log_info "步驟 3/5: 解析 RPZ 記錄"
    if ! bash "${SCRIPT_DIR}/parse_rpz.sh"; then
        log_error "RPZ 解析失敗"
        echo "$timestamp $(uname -n) ERROR: RPZ parsing failed" >> "$LOG_FILE"
        exit 1
    fi

    # 步驟 4: 產生 DataGroup 檔案
    log_info ""
    log_info "步驟 4/5: 產生 DataGroup 檔案"
    if ! bash "${SCRIPT_DIR}/generate_datagroup.sh"; then
        log_error "DataGroup 產生失敗"
        echo "$timestamp $(uname -n) ERROR: DataGroup generation failed" >> "$LOG_FILE"
        exit 1
    fi

    # 步驟 5: 更新 F5 DataGroups
    log_info ""
    log_info "步驟 5/5: 更新 F5 DataGroups"
    if ! bash "${SCRIPT_DIR}/update_datagroup.sh"; then
        log_error "F5 DataGroup 更新失敗"
        echo "$timestamp $(uname -n) ERROR: F5 update failed" >> "$LOG_FILE"
        exit 1
    fi

    # 清理臨時檔案
    cleanup

    # 統計執行時間
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    log_info ""
    log_info "=========================================="
    log_info "  處理完成"
    log_info "=========================================="
    log_info "總耗時: $(timer_format "$elapsed")"
    echo "$timestamp $(uname -n) INFO: RPZ processing completed in ${elapsed}s" >> "$LOG_FILE"

    exit 0
}

# =============================================================================
# 命令列參數處理
# =============================================================================

show_usage() {
    cat << EOF
用法: $0 [選項]

選項:
  -f, --force          強制執行 (跳過 SOA 檢查)
  -n, --no-cleanup     不清理臨時檔案
  -h, --help           顯示此說明
  -v, --verbose        詳細模式 (DEBUG log level)

範例:
  $0                   # 正常執行
  $0 --force           # 強制執行，忽略 SOA 檢查
  $0 --no-cleanup      # 保留臨時檔案供除錯
  $0 -f -n -v          # 強制執行 + 保留檔案 + 詳細輸出

環境變數:
  OUTPUT_DIR           DataGroup 輸出目錄 (預設: /var/tmp/rpz_datagroups)
  LOG_FILE             日誌檔案位置 (預設: /var/log/ltm)
  DNSXDUMP_CMD         dnsxdump 指令路徑 (預設: /usr/local/bin/dnsxdump)
  LOG_LEVEL            日誌等級 0-3 (預設: 1=INFO)

EOF
}

# 解析命令列參數
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_RUN="true"
            shift
            ;;
        -n|--no-cleanup)
            CLEANUP_TEMP="false"
            shift
            ;;
        -v|--verbose)
            LOG_LEVEL=$LOG_DEBUG
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "未知選項: $1"
            show_usage
            exit 1
            ;;
    esac
done

# =============================================================================
# 執行
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 設定 trap 處理錯誤
    trap 'log_error "執行過程發生錯誤，退出碼: $?"' ERR

    main "$@"
fi