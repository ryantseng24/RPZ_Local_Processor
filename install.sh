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
mkdir -p "$OUTPUT_BASE"/{raw,parsed,final,.soa_cache}
echo "  ✓ $OUTPUT_BASE"

# 設定腳本權限
echo ""
echo "[3/4] 設定執行權限..."
chmod +x "${SCRIPT_DIR}/scripts"/*.sh
echo "  ✓ scripts/*.sh"

# 檢查 F5 環境
echo ""
echo "[4/4] 檢查 F5 環境..."
if command -v tmsh >/dev/null 2>&1; then
    echo "  ✓ tmsh 指令可用"
else
    echo "  ⚠ 警告: tmsh 指令不存在，可能不在 F5 環境中"
fi

if command -v /usr/local/bin/dnsxdump >/dev/null 2>&1; then
    echo "  ✓ dnsxdump 指令可用"
else
    echo "  ⚠ 警告: dnsxdump 指令不存在，需要啟用 DNS Express"
fi

echo ""
echo "=========================================="
echo "  安裝完成！"
echo "=========================================="
echo ""
echo "下一步："
echo "1. 測試執行:"
echo "   bash scripts/main.sh --force --verbose"
echo ""
echo "2. 設定 iCall 定期執行:"
echo "   bash config/icall_setup.sh"
echo ""
echo "3. 檢查輸出:"
echo "   ls -lh $OUTPUT_BASE/final/"
echo "   tail -f /var/log/ltm | grep RPZ"
echo ""