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
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"

# 是否清理臨時檔案 (預設: 是)
CLEANUP_TEMP="${CLEANUP_TEMP:-true}"

# 是否強制執行 (跳過 SOA 檢查)
FORCE_RUN="${FORCE_RUN:-false}"

# 暫存檔保留數量上限（每個檔案家族）。與天數上限並用，取先到者。
# 接受範圍 1~99999；範圍外或非數字回退預設 24（防 bash 整數溢位）。
RPZ_KEEP_COUNT="${RPZ_KEEP_COUNT:-24}"
if ! [[ "$RPZ_KEEP_COUNT" =~ ^[1-9][0-9]{0,4}$ ]]; then
    log_warn "RPZ_KEEP_COUNT 非法或超出範圍 1-99999（${RPZ_KEEP_COUNT}），改用預設 24"
    RPZ_KEEP_COUNT=24
fi

# cleanup 只執行一次（成功路徑先呼叫，EXIT trap 補所有其他路徑）
CLEANUP_RAN="false"

# =============================================================================
# 初始化
# =============================================================================

init() {
    log_info "=========================================="
    log_info "  RPZ Local Processor 啟動"
    log_info "=========================================="
    log_info "專案根目錄: $PROJECT_ROOT"
    log_info "輸出目錄: $OUTPUT_DIR"
    log_info "系統事件 log: syslog local0 -> /var/log/ltm（tag=RPZLocal）"

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

# 時間戳的精確 glob 形狀: 8 位日期 _ 6 位時間
TS_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]'

prune_family() {
    # prune_family <目錄> <家族前綴> <副檔名> <保留數>
    # 家族成員 = <前綴>_<8位日期>_<6位時間><副檔名> 的精確形狀。
    # 前綴以字面比對（引號展開），不作為 glob 使用：
    # alpha 家族不會選中 alpha_beta 家族的檔案（P1B-08）。
    # 檔名時間戳使 glob 展開的字典序即時間序。
    # 純 bash 迴圈，不用管線（SIGPIPE 根因見 process.md 第 2 節，實測數據第 6 節）。
    local dir="$1" prefix="$2" ext="$3" keep="$4"
    local files=() f i del
    for f in "$dir/${prefix}"_${TS_GLOB}"${ext}"; do
        [[ -f "$f" ]] || continue
        files+=("$f")
    done
    del=$(( ${#files[@]} - keep ))
    (( del > 0 )) || return 0
    local deleted=0 failed=0
    for (( i = 0; i < del; i++ )); do
        if rm -f -- "${files[$i]}" 2>/dev/null; then
            deleted=$((deleted + 1))
        else
            failed=$((failed + 1))
        fi
    done
    if (( failed > 0 )); then
        log_warn "數量上限清理: ${dir##*/}/${prefix} 家族應刪 ${del} 個，實際刪除 ${deleted} 個，失敗 ${failed} 個（實際保留數超過 ${keep}）"
    else
        log_info "數量上限清理: ${dir##*/}/${prefix} 家族刪除 ${deleted} 個，保留 ${keep} 個"
    fi
}

prune_parsed_families() {
    # 從 parsed/ 檔名推導家族前綴（zone 名），逐家族套用數量上限。
    # 不讀 zonelist.txt：zone 增減自動適應，也不引入新的解析路徑。
    local dir="$1" keep="$2"
    local f name prefix
    declare -A seen
    for f in "$dir"/*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].txt; do
        [[ -f "$f" ]] || continue
        name="${f##*/}"
        [[ "$name" =~ ^(.+)_[0-9]{8}_[0-9]{6}\.txt$ ]] || continue
        prefix="${BASH_REMATCH[1]}"
        # 前綴只接受本專案會產生的安全字元，避免被當成 glob 使用
        if [[ "$prefix" =~ ^[A-Za-z0-9._-]+$ ]]; then
            seen["$prefix"]=1
        else
            log_warn "略過不安全的家族前綴（僅由天數上限管理）: ${name}"
        fi
    done
    (( ${#seen[@]} > 0 )) || return 0    # bash 4.2: 空陣列展開會踩 set -u
    for prefix in "${!seen[@]}"; do
        prune_family "$dir" "$prefix" ".txt" "$keep"
    done
}

cleanup() {
    if [[ "$CLEANUP_TEMP" != "true" ]]; then
        log_info "跳過清理臨時檔案"
        return 0
    fi

    # 只清 raw/ 與 parsed/，不遞迴掃 OUTPUT_DIR。
    # final/ 是 DataGroup 的 source-path，刪除即影響服務（實測見 process.md 第 27 節）。
    if [[ -d "$OUTPUT_DIR/raw" ]]; then
        if ! find "$OUTPUT_DIR/raw" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null; then
            log_warn "天數上限清理失敗（raw/ 有檔案無法刪除）"
        fi
    fi
    if [[ -d "$OUTPUT_DIR/parsed" ]]; then
        if ! find "$OUTPUT_DIR/parsed" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null; then
            log_warn "天數上限清理失敗（parsed/ 有檔案無法刪除）"
        fi
    fi

    prune_family "$OUTPUT_DIR/raw" "dnsxdump" ".out" "$RPZ_KEEP_COUNT"
    prune_parsed_families "$OUTPUT_DIR/parsed" "$RPZ_KEEP_COUNT"

    # 缺陷 A（Phase 2）: DNSXDUMP_FILE 由 extract_rpz.sh 子行程 export，
    # 傳不回本行程，此分支從未執行。本次保留原樣。
    if [[ -n "${DNSXDUMP_FILE:-}" && -f "$DNSXDUMP_FILE" ]]; then
        rm -f "$DNSXDUMP_FILE" || true
        log_info "清理 dnsxdump 檔案完成"
    fi

    return 0
}

run_cleanup_once() {
    if [[ "$CLEANUP_RAN" == "true" ]]; then
        return 0
    fi
    CLEANUP_RAN="true"
    cleanup
}

on_exit() {
    # 先保存退出碼，清理後原樣回傳，不改變 wrapper 記錄的語意。
    local rc=$?
    run_cleanup_once || true
    exit "$rc"
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    local start_time=$(date +%s)

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
            logger -t RPZLocal -p local0.notice "RPZ SOA not changed, skip update" || true
            exit 0
        elif [[ "$soa_check_output" != "UPDATE_NEEDED" ]]; then
            # 檢查失敗或輸出異常
            log_error "SOA 檢查失敗或輸出異常（退出碼: $soa_check_exit, 輸出: '$soa_check_output'）"
            logger -t RPZLocal -p local0.err "RPZ SOA check failed" || true
            exit 1
        fi

        # SOA 已變更，繼續處理
        log_info "SOA Serial 已變更，繼續處理"
        logger -t RPZLocal -p local0.notice "RPZ SOA changed, start processing" || true
    fi

    # 步驟 2: 從 DNS Express 提取 RPZ 資料
    log_info ""
    log_info "步驟 2/5: 提取 DNS Express 資料"
    if ! bash "${SCRIPT_DIR}/extract_rpz.sh"; then
        log_error "資料提取失敗"
        logger -t RPZLocal -p local0.err "RPZ extraction failed" || true
        exit 1
    fi

    # 步驟 3: 解析 RPZ 記錄
    log_info ""
    log_info "步驟 3/5: 解析 RPZ 記錄"
    if ! bash "${SCRIPT_DIR}/parse_rpz.sh"; then
        log_error "RPZ 解析失敗"
        logger -t RPZLocal -p local0.err "RPZ parsing failed" || true
        exit 1
    fi

    # 步驟 4: 產生 DataGroup 檔案
    log_info ""
    log_info "步驟 4/5: 產生 DataGroup 檔案"
    if ! bash "${SCRIPT_DIR}/generate_datagroup.sh"; then
        log_error "DataGroup 產生失敗"
        logger -t RPZLocal -p local0.err "DataGroup generation failed" || true
        exit 1
    fi

    # 步驟 5: 更新 F5 DataGroups
    log_info ""
    log_info "步驟 5/5: 更新 F5 DataGroups"
    if ! bash "${SCRIPT_DIR}/update_datagroup.sh"; then
        log_error "F5 DataGroup 更新失敗"
        logger -t RPZLocal -p local0.err "F5 update failed" || true
        exit 1
    fi

    # 清理臨時檔案
    run_cleanup_once

    # 統計執行時間
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    log_info ""
    log_info "=========================================="
    log_info "  處理完成"
    log_info "=========================================="
    log_info "總耗時: $(timer_format "$elapsed")"
    logger -t RPZLocal -p local0.notice "RPZ processing completed in ${elapsed}s" || true

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
  OUTPUT_DIR           DataGroup 輸出目錄 (預設: /config/snmp/rpz_datagroups)
  DNSXDUMP_CMD         dnsxdump 指令路徑 (預設: /usr/local/bin/dnsxdump)
  LOG_LEVEL            日誌等級 0-3 (預設: 1=INFO)
  RPZ_KEEP_COUNT       暫存檔每家族保留數量上限 (預設: 24，範圍 1-99999)

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

    # 所有 exit 路徑（成功、NO_UPDATE、失敗）都執行清理（Phase 1B）
    trap on_exit EXIT

    main "$@"
fi
