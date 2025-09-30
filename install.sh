#!/bin/bash
# =============================================================================
# install.sh - RPZ Local Processor 安裝腳本
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  RPZ Local Processor 安裝程式"
echo "=========================================="
echo ""

# 檢查必要指令
echo "[1/4] 檢查系統環境..."
for cmd in bash awk sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: 缺少必要指令: $cmd"
        exit 1
    fi
    echo "  ✓ $cmd"
done

# 建立輸出目錄
echo ""
echo "[2/4] 建立輸出目錄..."
OUTPUT_BASE="/var/tmp/rpz_datagroups"
mkdir -p "$OUTPUT_BASE"/{raw,parsed,datagroups}
echo "  ✓ $OUTPUT_BASE"

# 設定腳本權限
echo ""
echo "[3/4] 設定執行權限..."
chmod +x "${SCRIPT_DIR}/scripts"/*.sh
echo "  ✓ scripts/*.sh"

# 檢查配置檔案
echo ""
echo "[4/4] 檢查配置檔案..."
if [[ ! -f "${SCRIPT_DIR}/config/rpz_zones.conf" ]]; then
    echo "  ⚠ 警告: rpz_zones.conf 不存在，請手動配置"
else
    echo "  ✓ rpz_zones.conf"
fi

if [[ ! -f "${SCRIPT_DIR}/config/datagroup_mapping.conf" ]]; then
    echo "  ⚠ 警告: datagroup_mapping.conf 不存在，請手動配置"
else
    echo "  ✓ datagroup_mapping.conf"
fi

echo ""
echo "=========================================="
echo "  安裝完成！"
echo "=========================================="
echo ""
echo "下一步："
echo "1. 編輯配置檔案:"
echo "   - config/rpz_zones.conf"
echo "   - config/datagroup_mapping.conf"
echo ""
echo "2. 執行處理程序:"
echo "   bash scripts/main.sh"
echo ""
echo "3. 檢查輸出:"
echo "   ls -lh $OUTPUT_BASE/datagroups/"
echo ""