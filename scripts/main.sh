#!/bin/bash
# =============================================================================
# main.sh - RPZ Local Processor 主執行腳本
# =============================================================================

set -euo pipefail

# 取得腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 載入工具函數
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# 配置目錄
CONFIG_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"
OUTPUT_DIR="${OUTPUT_DIR:-/var/tmp/rpz_datagroups}"

# =============================================================================
# 初始化
# =============================================================================

init() {
    log_info "=== RPZ Local Processor 啟動 ==="
    log_info "專案根目錄: $PROJECT_ROOT"

    # 建立必要目錄
    ensure_dir "$LOG_DIR"
    ensure_dir "$OUTPUT_DIR"

    # 檢查必要指令
    check_command "bash"
    check_command "awk"
    check_command "sed"

    # TODO: 檢查 tmsh 指令 (F5 環境)
    # check_command "tmsh"
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    local start_time
    start_time=$(date +%s)

    init

    log_info "步驟 1: 從 DNS Express 提取 RPZ 資料"
    # bash "${SCRIPT_DIR}/extract_rpz.sh"

    log_info "步驟 2: 解析 RPZ 記錄"
    # bash "${SCRIPT_DIR}/parse_rpz.sh"

    log_info "步驟 3: 產生 DataGroup 檔案"
    # bash "${SCRIPT_DIR}/generate_datagroup.sh"

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    log_info "=== 處理完成 ==="
    log_info "總耗時: $(timer_format "$elapsed")"
}

# =============================================================================
# 執行
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi