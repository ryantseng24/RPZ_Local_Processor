#!/bin/bash
# =============================================================================
# iCall 自動更新設定腳本
# =============================================================================
# 功能：在 F5 上建立 iCall periodic handler，定期執行 RPZ 更新
# =============================================================================

set -euo pipefail

# 配置參數
SCRIPT_PATH="/var/tmp/RPZ_Local_Processor/scripts/main.sh"
INTERVAL="${INTERVAL:-300}"  # 預設 5 分鐘 (300 秒)

echo "=========================================="
echo "  設定 RPZ 自動更新 (iCall)"
echo "=========================================="
echo "執行間隔: ${INTERVAL} 秒"
echo "腳本路徑: ${SCRIPT_PATH}"
echo ""

# 檢查腳本是否存在
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "錯誤: 找不到主腳本 $SCRIPT_PATH"
    exit 1
fi

# 建立 iCall script
echo "步驟 1: 建立 iCall Script..."
tmsh create sys icall script rpz_processor_script definition \{
    exec bash ${SCRIPT_PATH}
\}

echo "✓ iCall Script 已建立"

# 建立 iCall periodic handler
echo "步驟 2: 建立 iCall Periodic Handler..."
tmsh create sys icall handler periodic rpz_processor_handler \
    interval ${INTERVAL} \
    script rpz_processor_script

echo "✓ iCall Periodic Handler 已建立"

# 儲存配置
echo "步驟 3: 儲存配置..."
tmsh save sys config

echo "✓ 配置已儲存"
echo ""
echo "=========================================="
echo "  設定完成！"
echo "=========================================="
echo ""
echo "檢查狀態:"
echo "  tmsh list sys icall handler periodic rpz_processor_handler"
echo "  tmsh list sys icall script rpz_processor_script"
echo ""
echo "執行記錄:"
echo "  tail -f /var/log/ltm | grep RPZ"
echo ""
echo "停用/啟用:"
echo "  tmsh modify sys icall handler periodic rpz_processor_handler status inactive"
echo "  tmsh modify sys icall handler periodic rpz_processor_handler status active"
echo ""
echo "移除:"
echo "  tmsh delete sys icall handler periodic rpz_processor_handler"
echo "  tmsh delete sys icall script rpz_processor_script"
echo ""
