#!/bin/bash
# =============================================================================
# deploy.sh - RPZ Local Processor 自動化部署腳本
# =============================================================================
# 用途: 自動部署到新的 F5 設備
# 用法: bash deploy.sh <F5_IP> [F5_PASSWORD]
# =============================================================================

set -euo pipefail

# 參數
F5_HOST="${1:-}"
F5_USER="admin"
F5_PASS="${2:-uniforce}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_PATH="/var/tmp/RPZ_Local_Processor"

# 函數
log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*"
}

log_error() {
    echo "[ERROR] $*"
}

show_usage() {
    cat << EOF
用法: $0 <F5_IP> [F5_PASSWORD]

參數:
  F5_IP          F5 設備 IP 位址
  F5_PASSWORD    F5 admin 密碼 (預設: uniforce)

範例:
  $0 10.8.34.22
  $0 10.8.34.22 mypassword

EOF
}

check_requirements() {
    log_info "檢查本地環境..."

    for cmd in sshpass ssh scp tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "缺少必要指令: $cmd"
            exit 1
        fi
    done

    log_info "✓ 本地環境檢查通過"
}

test_connection() {
    log_info "測試 F5 連線..."

    if ! sshpass -p "$F5_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
         "${F5_USER}@${F5_HOST}" "echo connected" >/dev/null 2>&1; then
        log_error "無法連線到 F5: ${F5_HOST}"
        log_error "請檢查:"
        log_error "  1. IP 位址是否正確"
        log_error "  2. SSH 服務是否啟動"
        log_error "  3. 密碼是否正確"
        exit 1
    fi

    log_info "✓ F5 連線測試通過"
}

create_package() {
    local temp_dir=$(mktemp -d)
    local package="${temp_dir}/RPZ_Local_Processor.tar.gz"

    echo "[INFO] 建立部署套件: $package" >&2

    # 打包整個專案目錄
    cd "$(dirname "$PROJECT_DIR")"
    tar czf "$package" \
        --exclude='.git' \
        --exclude='*.md' \
        --exclude='docs' \
        --exclude='*.tar.gz' \
        --exclude='infoblox_rpz_data.csv' \
        --exclude='F5_rpztw_data_group.txt' \
        --exclude='dnsxdump_all.txt' \
        RPZ_Local_Processor/scripts \
        RPZ_Local_Processor/config \
        RPZ_Local_Processor/install.sh

    echo "$package"
}

upload_package() {
    local package="$1"

    log_info "上傳部署套件到 F5..."

    if ! sshpass -p "$F5_PASS" scp -o StrictHostKeyChecking=no \
         "$package" "${F5_USER}@${F5_HOST}:/var/tmp/"; then
        log_error "上傳失敗"
        exit 1
    fi

    log_info "✓ 上傳完成"
}

execute_remote() {
    local command="$1"
    local description="$2"

    log_info "$description"

    if ! sshpass -p "$F5_PASS" ssh -o StrictHostKeyChecking=no \
         "${F5_USER}@${F5_HOST}" "$command"; then
        log_error "執行失敗: $description"
        return 1
    fi

    return 0
}

deploy_on_f5() {
    log_info "在 F5 上部署..."

    # 解壓套件
    execute_remote "cd /var/tmp && tar xzf RPZ_Local_Processor.tar.gz" \
        "→ 解壓部署套件" || return 1

    # 執行安裝腳本
    execute_remote "bash ${DEPLOY_PATH}/install.sh" \
        "→ 執行安裝腳本" || return 1

    log_info "✓ 部署完成"
}

verify_deployment() {
    log_info "驗證部署..."

    # 檢查腳本是否存在
    if ! execute_remote "test -f ${DEPLOY_PATH}/scripts/main.sh" \
         "→ 檢查主腳本"; then
        log_error "驗證失敗: 主腳本不存在"
        return 1
    fi

    # 檢查輸出目錄
    if ! execute_remote "test -d /var/tmp/rpz_datagroups" \
         "→ 檢查輸出目錄"; then
        log_error "驗證失敗: 輸出目錄不存在"
        return 1
    fi

    # 測試執行 (如果有 dnsxdump)
    log_info "→ 測試執行主腳本..."
    if execute_remote "bash ${DEPLOY_PATH}/scripts/main.sh --force 2>&1 | tail -20" \
         "  執行測試" 2>/dev/null; then
        log_info "✓ 測試執行成功"
    else
        log_warn "⚠ 測試執行失敗 (可能沒有 DNS Express 資料)"
        log_warn "  這在空的 LAB 環境是正常的"
    fi

    log_info "✓ 基本驗證通過"
}

setup_icall() {
    log_info "詢問是否設定 iCall 排程..."
    read -p "是否設定 iCall 定期執行? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 使用 REST API 版本 (推薦 - 避免 tmsh brace escaping 問題)
        log_info "使用 REST API 方式設定 iCall..."
        if execute_remote "F5_HOST=localhost F5_USER=admin F5_PASS='${F5_PASS}' bash ${DEPLOY_PATH}/config/icall_setup_api.sh" \
             "→ 設定 iCall (REST API)"; then
            log_info "✓ iCall 設定完成 (REST API)"
        else
            log_warn "REST API 方式失敗，嘗試使用 tmsh 方式..."
            if execute_remote "bash ${DEPLOY_PATH}/config/icall_setup.sh" \
                 "→ 設定 iCall (tmsh)"; then
                log_info "✓ iCall 設定完成 (tmsh)"
            else
                log_error "iCall 設定失敗 (兩種方式都失敗)"
                log_error "請稍後手動在 F5 上執行:"
                log_error "  bash ${DEPLOY_PATH}/config/icall_setup_api.sh"
                return 1
            fi
        fi
    else
        log_info "跳過 iCall 設定"
        log_info "稍後可執行:"
        log_info "  REST API 版本 (推薦): bash ${DEPLOY_PATH}/config/icall_setup_api.sh"
        log_info "  tmsh 版本: bash ${DEPLOY_PATH}/config/icall_setup.sh"
    fi
}

show_summary() {
    echo ""
    echo "=========================================="
    echo "  部署完成總結"
    echo "=========================================="
    echo ""
    echo "F5 設備: ${F5_HOST}"
    echo "部署路徑: ${DEPLOY_PATH}"
    echo ""
    echo "下一步:"
    echo "  1. SSH 登入 F5:"
    echo "     ssh ${F5_USER}@${F5_HOST}"
    echo ""
    echo "  2. 手動測試執行:"
    echo "     bash ${DEPLOY_PATH}/scripts/main.sh --force --verbose"
    echo ""
    echo "  3. 設定 iCall (如未設定):"
    echo "     bash ${DEPLOY_PATH}/config/icall_setup.sh"
    echo ""
    echo "  4. 檢查執行日誌:"
    echo "     tail -f /var/log/ltm | grep RPZ"
    echo "     tail -f /var/tmp/rpz_wrapper.log"
    echo ""
    echo "  5. 檢查輸出:"
    echo "     ls -lh /var/tmp/rpz_datagroups/final/"
    echo ""
}

# =========================================
# 主流程
# =========================================

main() {
    echo "=========================================="
    echo "  RPZ Local Processor 自動部署"
    echo "=========================================="
    echo ""

    # 檢查參數
    if [[ -z "$F5_HOST" ]]; then
        show_usage
        exit 1
    fi

    # 執行部署流程
    check_requirements
    test_connection

    local package=$(create_package)
    upload_package "$package"

    deploy_on_f5
    verify_deployment

    # 清理臨時檔案
    rm -rf "$(dirname "$package")"

    # 詢問是否設定 iCall
    setup_icall

    # 顯示總結
    show_summary

    log_info "🎉 部署完成!"
}

# 執行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
