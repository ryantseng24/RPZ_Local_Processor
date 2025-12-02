#!/bin/bash
# =============================================================================
# package.sh - 打包 RPZ Local Processor 部署檔案
# =============================================================================
# 用途: 產生可傳輸到客戶 F5 的安裝包
# 輸出: rpz_local_processor_YYYYMMDD_HHMMSS.tar.gz
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 版本與時間戳
VERSION="1.2"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
PACKAGE_NAME="rpz_local_processor_v${VERSION}_${TIMESTAMP}"
OUTPUT_DIR="${SCRIPT_DIR}/dist"

echo "=========================================="
echo "  RPZ Local Processor 打包工具"
echo "=========================================="
echo ""
echo "版本: $VERSION"
echo "時間: $TIMESTAMP"
echo ""

# 建立輸出目錄
mkdir -p "$OUTPUT_DIR"

# 建立臨時打包目錄
TEMP_DIR=$(mktemp -d)
PACKAGE_DIR="${TEMP_DIR}/${PACKAGE_NAME}"
mkdir -p "$PACKAGE_DIR"

echo "[1/4] 複製核心檔案..."

# 複製 scripts
mkdir -p "${PACKAGE_DIR}/scripts"
cp scripts/*.sh "${PACKAGE_DIR}/scripts/"
echo "  ✓ scripts/*.sh"

# 複製 config
mkdir -p "${PACKAGE_DIR}/config"
cp config/zonelist.txt "${PACKAGE_DIR}/config/"
cp config/icall_setup_api.sh "${PACKAGE_DIR}/config/"
echo "  ✓ config/zonelist.txt"
echo "  ✓ config/icall_setup_api.sh"

# 複製安裝腳本
cp install.sh "${PACKAGE_DIR}/"
echo "  ✓ install.sh"

# 複製安裝說明
cp INSTALL_GUIDE.txt "${PACKAGE_DIR}/" 2>/dev/null || true
echo "  ✓ INSTALL_GUIDE.txt"

echo ""
echo "[2/4] 設定檔案權限..."
chmod +x "${PACKAGE_DIR}/scripts"/*.sh
chmod +x "${PACKAGE_DIR}/install.sh"
chmod +x "${PACKAGE_DIR}/config/icall_setup_api.sh"
echo "  ✓ 執行權限已設定"

echo ""
echo "[3/4] 建立壓縮檔..."
cd "$TEMP_DIR"
tar czf "${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"
echo "  ✓ ${PACKAGE_NAME}.tar.gz"

echo ""
echo "[4/4] 清理暫存..."
rm -rf "$TEMP_DIR"
echo "  ✓ 暫存目錄已清理"

# 顯示結果
PACKAGE_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz"
PACKAGE_SIZE=$(ls -lh "$PACKAGE_FILE" | awk '{print $5}')

echo ""
echo "=========================================="
echo "  打包完成！"
echo "=========================================="
echo ""
echo "輸出檔案: $PACKAGE_FILE"
echo "檔案大小: $PACKAGE_SIZE"
echo ""
echo "包含內容:"
tar tzf "$PACKAGE_FILE" | head -20
echo ""
echo "----------------------------------------"
echo "部署步驟:"
echo "----------------------------------------"
echo "1. 上傳檔案到 F5:"
echo "   scp ${PACKAGE_FILE} admin@<F5_IP>:/var/tmp/"
echo ""
echo "2. SSH 登入 F5 執行:"
echo "   cd /var/tmp"
echo "   tar xzf ${PACKAGE_NAME}.tar.gz"
echo "   cd ${PACKAGE_NAME}"
echo "   bash install.sh"
echo ""
