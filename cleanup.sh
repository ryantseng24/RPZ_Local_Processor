#!/bin/bash
# =============================================================================
# cleanup.sh - RPZ Local Processor 完整清理腳本
# =============================================================================
# 用途: 完全清理 F5 設備上的 RPZ Local Processor 相關配置與檔案
# 用法: bash cleanup.sh
# =============================================================================

set -euo pipefail

echo "=========================================="
echo "  RPZ Local Processor 完整清理"
echo "=========================================="
echo ""
echo "⚠️  警告: 此腳本將刪除所有 RPZ Local Processor 相關配置與資料"
echo ""
read -p "確定要繼續嗎? (yes/N): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "已取消清理操作"
    exit 0
fi

echo ""
echo "=== 開始清理程序 ==="
echo ""

# ============================================
# 步驟 1: 停用並刪除 iCall 配置
# ============================================
echo "[1/7] 處理 iCall 配置..."

# 1.1 停用 iCall Handler (避免執行中被刪除)
echo "  → 停用 iCall Handler..."
tmsh modify sys icall handler periodic rpz_processor_handler status inactive 2>/dev/null || echo "    (Handler 不存在或已停用)"

# 等待可能正在執行的任務完成
sleep 2

# 1.2 刪除 iCall Handler
echo "  → 刪除 iCall Handler..."
tmsh delete sys icall handler periodic rpz_processor_handler 2>/dev/null && echo "    ✓ Handler 已刪除" || echo "    (Handler 不存在)"

# 1.3 刪除 iCall Script
echo "  → 刪除 iCall Script..."
tmsh delete sys icall script rpz_processor_script 2>/dev/null && echo "    ✓ Script 已刪除" || echo "    (Script 不存在)"

# 1.4 儲存配置
echo "  → 儲存配置..."
tmsh save sys config 2>/dev/null && echo "    ✓ 配置已儲存" || echo "    (儲存失敗或無需儲存)"

echo ""

# ============================================
# 步驟 2: 刪除 DataGroups
# ============================================
echo "[2/7] 刪除 DataGroups..."

# 2.1 刪除 rpztw External DataGroup
echo "  → 刪除 rpztw external data-group..."
tmsh delete ltm data-group external rpztw 2>/dev/null && echo "    ✓ rpztw 已刪除" || echo "    (rpztw 不存在)"

# 2.2 刪除 phishtw External DataGroup
echo "  → 刪除 phishtw external data-group..."
tmsh delete ltm data-group external phishtw 2>/dev/null && echo "    ✓ phishtw 已刪除" || echo "    (phishtw 不存在)"

# 2.3 刪除 rpzip External DataGroup (如果有)
echo "  → 刪除 rpzip external data-group..."
tmsh delete ltm data-group external rpzip 2>/dev/null && echo "    ✓ rpzip 已刪除" || echo "    (rpzip 不存在)"

# 2.4 刪除 DataGroup Files
echo "  → 刪除 data-group files..."
tmsh delete sys file data-group rpztw 2>/dev/null && echo "    ✓ rpztw file 已刪除" || echo "    (rpztw file 不存在)"
tmsh delete sys file data-group phishtw 2>/dev/null && echo "    ✓ phishtw file 已刪除" || echo "    (phishtw file 不存在)"
tmsh delete sys file data-group rpzip 2>/dev/null && echo "    ✓ rpzip file 已刪除" || echo "    (rpzip file 不存在)"

# 2.5 儲存配置
echo "  → 儲存配置..."
tmsh save sys config 2>/dev/null && echo "    ✓ 配置已儲存" || echo "    (儲存失敗或無需儲存)"

echo ""

# ============================================
# 步驟 3: 刪除專案目錄
# ============================================
echo "[3/7] 刪除專案目錄..."

if [[ -d "/var/tmp/RPZ_Local_Processor" ]]; then
    echo "  → 刪除 /var/tmp/RPZ_Local_Processor..."
    rm -rf /var/tmp/RPZ_Local_Processor
    echo "    ✓ 專案目錄已刪除"
else
    echo "    (專案目錄不存在)"
fi

echo ""

# ============================================
# 步驟 4: 刪除輸出目錄
# ============================================
echo "[4/7] 刪除輸出目錄..."

if [[ -d "/var/tmp/rpz_datagroups" ]]; then
    echo "  → 刪除 /var/tmp/rpz_datagroups..."
    # 顯示目錄大小
    du -sh /var/tmp/rpz_datagroups 2>/dev/null || echo "    (無法計算大小)"
    rm -rf /var/tmp/rpz_datagroups
    echo "    ✓ 輸出目錄已刪除"
else
    echo "    (輸出目錄不存在)"
fi

echo ""

# ============================================
# 步驟 5: 刪除 Wrapper 相關檔案
# ============================================
echo "[5/7] 刪除 Wrapper 相關檔案..."

# 5.1 刪除 wrapper script
if [[ -f "/var/tmp/rpz_wrapper.sh" ]]; then
    echo "  → 刪除 /var/tmp/rpz_wrapper.sh..."
    rm -f /var/tmp/rpz_wrapper.sh
    echo "    ✓ Wrapper script 已刪除"
else
    echo "    (Wrapper script 不存在)"
fi

# 5.2 刪除 wrapper log
if [[ -f "/var/tmp/rpz_wrapper.log" ]]; then
    echo "  → 刪除 /var/tmp/rpz_wrapper.log..."
    # 顯示日誌檔案大小
    ls -lh /var/tmp/rpz_wrapper.log 2>/dev/null || echo "    (無法顯示檔案資訊)"
    rm -f /var/tmp/rpz_wrapper.log
    echo "    ✓ Wrapper log 已刪除"
else
    echo "    (Wrapper log 不存在)"
fi

echo ""

# ============================================
# 步驟 6: 刪除部署套件
# ============================================
echo "[6/7] 刪除部署套件..."

if [[ -f "/var/tmp/RPZ_Local_Processor.tar.gz" ]]; then
    echo "  → 刪除 /var/tmp/RPZ_Local_Processor.tar.gz..."
    ls -lh /var/tmp/RPZ_Local_Processor.tar.gz 2>/dev/null || echo "    (無法顯示檔案資訊)"
    rm -f /var/tmp/RPZ_Local_Processor.tar.gz
    echo "    ✓ 部署套件已刪除"
else
    echo "    (部署套件不存在)"
fi

echo ""

# ============================================
# 步驟 7: 驗證清理結果
# ============================================
echo "[7/7] 驗證清理結果..."
echo ""

# 7.1 檢查 iCall 配置
echo "  → 檢查 iCall 配置..."
ICALL_COUNT=$(tmsh list sys icall handler periodic 2>/dev/null | grep -c "rpz_processor" || echo "0")
if [[ "$ICALL_COUNT" == "0" ]]; then
    echo "    ✓ 無 RPZ iCall 配置"
else
    echo "    ⚠ 仍有 $ICALL_COUNT 個 iCall 配置殘留"
fi

# 7.2 檢查 DataGroups
echo "  → 檢查 DataGroups..."
DG_COUNT=$(tmsh list ltm data-group external 2>/dev/null | grep -E "rpztw|phishtw|rpzip" | grep -c "ltm data-group" || echo "0")
if [[ "$DG_COUNT" == "0" ]]; then
    echo "    ✓ 無 RPZ DataGroup"
else
    echo "    ⚠ 仍有 $DG_COUNT 個 DataGroup 殘留"
    echo "    殘留列表:"
    tmsh list ltm data-group external 2>/dev/null | grep -E "rpztw|phishtw|rpzip" || true
fi

# 7.3 檢查專案目錄
echo "  → 檢查專案目錄..."
if [[ -d "/var/tmp/RPZ_Local_Processor" ]]; then
    echo "    ⚠ 專案目錄仍然存在"
    ls -lh /var/tmp/RPZ_Local_Processor
else
    echo "    ✓ 專案目錄不存在"
fi

# 7.4 檢查輸出目錄
echo "  → 檢查輸出目錄..."
if [[ -d "/var/tmp/rpz_datagroups" ]]; then
    echo "    ⚠ 輸出目錄仍然存在"
    du -sh /var/tmp/rpz_datagroups
else
    echo "    ✓ 輸出目錄不存在"
fi

# 7.5 檢查 wrapper 檔案
echo "  → 檢查 wrapper 檔案..."
WRAPPER_COUNT=$(ls -1 /var/tmp/rpz_wrapper.* 2>/dev/null | wc -l)
if [[ "$WRAPPER_COUNT" == "0" ]]; then
    echo "    ✓ wrapper 檔案不存在"
else
    echo "    ⚠ 仍有 $WRAPPER_COUNT 個 wrapper 檔案殘留"
    ls -lh /var/tmp/rpz_wrapper.* 2>/dev/null || true
fi

# 7.6 檢查部署套件
echo "  → 檢查部署套件..."
if [[ -f "/var/tmp/RPZ_Local_Processor.tar.gz" ]]; then
    echo "    ⚠ 部署套件仍然存在"
    ls -lh /var/tmp/RPZ_Local_Processor.tar.gz
else
    echo "    ✓ 部署套件不存在"
fi

echo ""
echo "=========================================="
echo "  清理完成!"
echo "=========================================="
echo ""

# 檢查是否有任何殘留
TOTAL_ISSUES=$((ICALL_COUNT + DG_COUNT + WRAPPER_COUNT))
if [[ "$TOTAL_ISSUES" == "0" ]] && \
   [[ ! -d "/var/tmp/RPZ_Local_Processor" ]] && \
   [[ ! -d "/var/tmp/rpz_datagroups" ]] && \
   [[ ! -f "/var/tmp/RPZ_Local_Processor.tar.gz" ]]; then
    echo "✅ 環境已完全清理乾淨"
    echo ""
    echo "可以重新部署了:"
    echo "  bash deploy.sh <F5_IP> [password]"
else
    echo "⚠️  仍有部分項目未清理完成，請檢查上方的驗證結果"
fi

echo ""
