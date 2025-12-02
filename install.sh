#!/bin/bash
# =============================================================================
# install.sh - RPZ Local Processor 本地安裝腳本
# =============================================================================
# 用途: 在 F5 BIG-IP 上安裝 RPZ Local Processor
# 執行: 解壓縮部署包後，在 F5 上執行此腳本
# =============================================================================

set -euo pipefail

# 取得腳本所在目錄（解壓縮後的目錄）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 安裝目標目錄
INSTALL_DIR="/config/snmp/RPZ_Local_Processor"
OUTPUT_DIR="/config/snmp/rpz_datagroups"

echo "=========================================="
echo "  RPZ Local Processor 安裝程式"
echo "=========================================="
echo ""
echo "來源目錄: $SCRIPT_DIR"
echo "安裝目錄: $INSTALL_DIR"
echo "輸出目錄: $OUTPUT_DIR"
echo ""

# =============================================================================
# 步驟 1: 檢查系統環境
# =============================================================================

echo "[1/6] 檢查系統環境..."

# 檢查是否為 root 或 admin
if [[ $EUID -ne 0 ]] && [[ "$(whoami)" != "admin" ]]; then
    echo "  ⚠ 警告: 建議使用 root 或 admin 執行"
fi

# 檢查必要指令
for cmd in bash awk sed grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✗ 缺少必要指令: $cmd"
        exit 1
    fi
    echo "  ✓ $cmd"
done

# =============================================================================
# 步驟 2: 檢查 F5 環境
# =============================================================================

echo ""
echo "[2/6] 檢查 F5 環境..."

F5_ENV=true

if command -v tmsh >/dev/null 2>&1; then
    echo "  ✓ tmsh 指令可用"
else
    echo "  ✗ tmsh 指令不存在"
    F5_ENV=false
fi

if command -v /usr/local/bin/dnsxdump >/dev/null 2>&1; then
    echo "  ✓ dnsxdump 指令可用"
else
    echo "  ⚠ dnsxdump 指令不存在 (需要 DNS Express)"
fi

if [[ "$F5_ENV" != "true" ]]; then
    echo ""
    echo "錯誤: 此腳本需要在 F5 BIG-IP 環境執行"
    exit 1
fi

# =============================================================================
# 步驟 3: 建立目錄結構
# =============================================================================

echo ""
echo "[3/6] 建立目錄結構..."

# 建立安裝目錄
mkdir -p "$INSTALL_DIR"/{scripts,config}
echo "  ✓ $INSTALL_DIR"

# 建立輸出目錄
mkdir -p "$OUTPUT_DIR"/{raw,parsed,final,.soa_cache}
echo "  ✓ $OUTPUT_DIR"

# =============================================================================
# 步驟 4: 複製檔案
# =============================================================================

echo ""
echo "[4/6] 複製檔案..."

# 複製 scripts
if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
    cp -f "${SCRIPT_DIR}/scripts"/*.sh "$INSTALL_DIR/scripts/"
    echo "  ✓ scripts/*.sh"
else
    echo "  ✗ 找不到 scripts 目錄"
    exit 1
fi

# 複製 config
if [[ -d "${SCRIPT_DIR}/config" ]]; then
    # zonelist.txt - 如果目標已存在則保留（避免覆蓋客戶配置）
    if [[ -f "$INSTALL_DIR/config/zonelist.txt" ]]; then
        echo "  ⚠ zonelist.txt 已存在，保留現有配置"
        cp -f "${SCRIPT_DIR}/config/zonelist.txt" "$INSTALL_DIR/config/zonelist.txt.new"
        echo "    新版本已存為 zonelist.txt.new"
    else
        cp -f "${SCRIPT_DIR}/config/zonelist.txt" "$INSTALL_DIR/config/"
        echo "  ✓ config/zonelist.txt"
    fi

    cp -f "${SCRIPT_DIR}/config/icall_setup_api.sh" "$INSTALL_DIR/config/"
    echo "  ✓ config/icall_setup_api.sh"
fi

# =============================================================================
# 步驟 5: 設定權限
# =============================================================================

echo ""
echo "[5/6] 設定執行權限..."

chmod +x "$INSTALL_DIR/scripts"/*.sh
chmod +x "$INSTALL_DIR/config"/*.sh
echo "  ✓ 執行權限已設定"

# =============================================================================
# 步驟 6: 驗證安裝
# =============================================================================

echo ""
echo "[6/6] 驗證安裝..."

# 檢查關鍵檔案
REQUIRED_FILES=(
    "$INSTALL_DIR/scripts/main.sh"
    "$INSTALL_DIR/scripts/utils.sh"
    "$INSTALL_DIR/scripts/parse_rpz.sh"
    "$INSTALL_DIR/config/zonelist.txt"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        echo "  ✓ $(basename "$f")"
    else
        echo "  ✗ 缺少: $f"
        ALL_OK=false
    fi
done

if [[ "$ALL_OK" != "true" ]]; then
    echo ""
    echo "錯誤: 安裝驗證失敗"
    exit 1
fi

# =============================================================================
# 完成
# =============================================================================

echo ""
echo "=========================================="
echo "  安裝完成！"
echo "=========================================="
echo ""
echo "安裝位置: $INSTALL_DIR"
echo ""
echo "----------------------------------------"
echo "下一步操作:"
echo "----------------------------------------"
echo ""
echo "1. 編輯 Zone 清單 (如需修改):"
echo "   vi $INSTALL_DIR/config/zonelist.txt"
echo ""
echo "2. 測試執行:"
echo "   bash $INSTALL_DIR/scripts/main.sh --force"
echo ""
echo "3. 設定 iCall 定期執行 (每 5 分鐘):"
echo "   bash $INSTALL_DIR/config/icall_setup_api.sh"
echo ""
echo "4. 檢查執行結果:"
echo "   ls -lh $OUTPUT_DIR/final/"
echo "   tmsh list ltm data-group external"
echo ""
echo "5. 監控日誌:"
echo "   tail -f /var/log/ltm | grep -E '(RPZ|rpz)'"
echo ""
