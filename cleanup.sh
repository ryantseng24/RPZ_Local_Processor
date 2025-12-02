#!/bin/bash
# =============================================================================
# cleanup.sh - RPZ Local Processor 清除腳本
# =============================================================================
# 用途: 完整移除 RPZ Local Processor 及相關配置
# 執行: 上傳到 F5 後執行 bash cleanup.sh
# =============================================================================

set -uo pipefail

echo "=========================================="
echo "  RPZ Local Processor 清除程式"
echo "=========================================="
echo ""

# =============================================================================
# 定義路徑 (新版路徑)
# =============================================================================

INSTALL_DIR="/config/snmp/RPZ_Local_Processor"
OUTPUT_DIR="/config/snmp/rpz_datagroups"
ICALL_HANDLER="rpz_update_handler"
ICALL_SCRIPT="rpz_update_script"

# 舊版路徑 (相容性清理)
OLD_INSTALL_DIR="/var/tmp/RPZ_Local_Processor"
OLD_OUTPUT_DIR="/var/tmp/rpz_datagroups"
OLD_ICALL_HANDLER="rpz_processor_handler"
OLD_ICALL_SCRIPT="rpz_processor_script"

# =============================================================================
# 確認清除
# =============================================================================

echo "此腳本將移除以下項目:"
echo ""
echo "  [iCall 配置]"
echo "    - Handler: $ICALL_HANDLER"
echo "    - Script:  $ICALL_SCRIPT"
echo ""
echo "  [程式目錄]"
echo "    - $INSTALL_DIR"
[[ -d "$OLD_INSTALL_DIR" ]] && echo "    - $OLD_INSTALL_DIR (舊版)"
echo ""
echo "  [輸出目錄]"
echo "    - $OUTPUT_DIR"
[[ -d "$OLD_OUTPUT_DIR" ]] && echo "    - $OLD_OUTPUT_DIR (舊版)"
echo ""
echo "  [DataGroups] (可選)"
echo ""

read -p "確定要繼續嗎? (yes/N): " confirm
if [[ "$confirm" != "yes" && "$confirm" != "YES" ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "=== 開始清理程序 ==="
echo ""

# =============================================================================
# 步驟 1: 移除 iCall 配置
# =============================================================================

echo "[1/5] 移除 iCall 配置..."

# 新版 iCall
if tmsh list sys icall handler periodic "$ICALL_HANDLER" &>/dev/null; then
    tmsh modify sys icall handler periodic "$ICALL_HANDLER" status inactive 2>/dev/null || true
    sleep 1
    tmsh delete sys icall handler periodic "$ICALL_HANDLER" 2>/dev/null && \
        echo "  ✓ 已移除 Handler: $ICALL_HANDLER" || \
        echo "  ✗ 移除 Handler 失敗: $ICALL_HANDLER"
else
    echo "  - Handler 不存在: $ICALL_HANDLER"
fi

if tmsh list sys icall script "$ICALL_SCRIPT" &>/dev/null; then
    tmsh delete sys icall script "$ICALL_SCRIPT" 2>/dev/null && \
        echo "  ✓ 已移除 Script: $ICALL_SCRIPT" || \
        echo "  ✗ 移除 Script 失敗: $ICALL_SCRIPT"
else
    echo "  - Script 不存在: $ICALL_SCRIPT"
fi

# 舊版 iCall (相容性)
if tmsh list sys icall handler periodic "$OLD_ICALL_HANDLER" &>/dev/null; then
    tmsh modify sys icall handler periodic "$OLD_ICALL_HANDLER" status inactive 2>/dev/null || true
    sleep 1
    tmsh delete sys icall handler periodic "$OLD_ICALL_HANDLER" 2>/dev/null && \
        echo "  ✓ 已移除舊版 Handler: $OLD_ICALL_HANDLER"
fi

if tmsh list sys icall script "$OLD_ICALL_SCRIPT" &>/dev/null; then
    tmsh delete sys icall script "$OLD_ICALL_SCRIPT" 2>/dev/null && \
        echo "  ✓ 已移除舊版 Script: $OLD_ICALL_SCRIPT"
fi

# =============================================================================
# 步驟 2: 移除程式目錄
# =============================================================================

echo ""
echo "[2/5] 移除程式目錄..."

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "  ✓ 已移除: $INSTALL_DIR"
else
    echo "  - 目錄不存在: $INSTALL_DIR"
fi

# 舊版目錄
if [[ -d "$OLD_INSTALL_DIR" ]]; then
    rm -rf "$OLD_INSTALL_DIR"
    echo "  ✓ 已移除舊版: $OLD_INSTALL_DIR"
fi

# =============================================================================
# 步驟 3: 移除輸出目錄
# =============================================================================

echo ""
echo "[3/5] 移除輸出目錄..."

if [[ -d "$OUTPUT_DIR" ]]; then
    echo "  → 目錄大小: $(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)"
    rm -rf "$OUTPUT_DIR"
    echo "  ✓ 已移除: $OUTPUT_DIR"
else
    echo "  - 目錄不存在: $OUTPUT_DIR"
fi

# 舊版目錄
if [[ -d "$OLD_OUTPUT_DIR" ]]; then
    rm -rf "$OLD_OUTPUT_DIR"
    echo "  ✓ 已移除舊版: $OLD_OUTPUT_DIR"
fi

# =============================================================================
# 步驟 4: 清理暫存檔案
# =============================================================================

echo ""
echo "[4/5] 清理暫存檔案..."

# Wrapper 檔案
rm -f /var/tmp/rpz_wrapper.sh /var/tmp/rpz_wrapper.log 2>/dev/null && \
    echo "  ✓ 已清理 wrapper 檔案" || echo "  - 無 wrapper 檔案"

# 部署套件
rm -f /var/tmp/RPZ_Local_Processor.tar.gz 2>/dev/null
rm -f /var/tmp/rpz_local_processor_*.tar.gz 2>/dev/null
echo "  ✓ 已清理部署套件"

# =============================================================================
# 步驟 5: 移除 DataGroups (可選)
# =============================================================================

echo ""
echo "[5/5] 移除 DataGroups..."
echo ""

# 列出所有 external DataGroups
echo "  偵測到以下 External DataGroups:"
DATAGROUPS=$(tmsh list ltm data-group external one-line 2>/dev/null | awk '{print $4}' | sort)

if [[ -z "$DATAGROUPS" ]]; then
    echo "    (無 external DataGroups)"
else
    # 篩選可能的 RPZ 相關 DataGroups
    RPZ_DGS=""
    for dg in $DATAGROUPS; do
        case "$dg" in
            rpztw|phishtw|rpzip|rpz.local|rpz_*)
                RPZ_DGS="$RPZ_DGS $dg"
                echo "    [RPZ] $dg"
                ;;
            *)
                echo "    [其他] $dg"
                ;;
        esac
    done
fi

echo ""
if [[ -n "$RPZ_DGS" ]]; then
    read -p "  是否移除 RPZ 相關 DataGroups? (y/N): " del_dg

    if [[ "$del_dg" == "y" || "$del_dg" == "Y" ]]; then
        for dg in $RPZ_DGS; do
            # 先刪除 external data-group
            tmsh delete ltm data-group external "$dg" 2>/dev/null && \
                echo "  ✓ 已移除 DataGroup: $dg" || \
                echo "  ✗ 移除失敗: $dg"

            # 再刪除 data-group file
            tmsh delete sys file data-group "$dg" 2>/dev/null || true
        done
    else
        echo "  - 保留 DataGroups"
    fi
else
    echo "  - 無 RPZ 相關 DataGroups"
fi

# =============================================================================
# 儲存配置
# =============================================================================

echo ""
echo "儲存配置..."

tmsh save sys config 2>&1 | grep -v "api-status-warning" && \
    echo "  ✓ 配置已儲存" || \
    echo "  ⚠ 配置儲存可能有警告，請檢查"

# =============================================================================
# 驗證清理結果
# =============================================================================

echo ""
echo "=== 驗證清理結果 ==="
echo ""

ISSUES=0

# 檢查 iCall
if tmsh list sys icall handler periodic 2>/dev/null | grep -qE "rpz_update|rpz_processor"; then
    echo "  ⚠ iCall 配置仍有殘留"
    ISSUES=$((ISSUES + 1))
else
    echo "  ✓ iCall 配置已清除"
fi

# 檢查目錄
if [[ -d "$INSTALL_DIR" ]] || [[ -d "$OLD_INSTALL_DIR" ]]; then
    echo "  ⚠ 程式目錄仍有殘留"
    ISSUES=$((ISSUES + 1))
else
    echo "  ✓ 程式目錄已清除"
fi

if [[ -d "$OUTPUT_DIR" ]] || [[ -d "$OLD_OUTPUT_DIR" ]]; then
    echo "  ⚠ 輸出目錄仍有殘留"
    ISSUES=$((ISSUES + 1))
else
    echo "  ✓ 輸出目錄已清除"
fi

# =============================================================================
# 完成
# =============================================================================

echo ""
echo "=========================================="
if [[ $ISSUES -eq 0 ]]; then
    echo "  ✅ 清除完成！環境已清理乾淨"
else
    echo "  ⚠️  清除完成，但有 $ISSUES 個項目需要檢查"
fi
echo "=========================================="
echo ""
echo "如需重新安裝:"
echo "  1. 上傳部署套件到 /var/tmp"
echo "  2. tar xzf rpz_local_processor_*.tar.gz"
echo "  3. cd rpz_local_processor_*"
echo "  4. bash install.sh"
echo ""
