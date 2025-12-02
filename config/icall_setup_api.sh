#!/bin/bash
# =============================================================================
# iCall 自動更新設定腳本 (REST API 版本)
# =============================================================================
# 功能：使用 F5 iControl REST API 建立 iCall periodic handler
# 優勢：避免 tmsh brace escaping 問題，更適合自動化部署
# =============================================================================

set -euo pipefail

# 配置參數
F5_HOST="${F5_HOST:-localhost}"
F5_USER="${F5_USER:-admin}"
F5_PASS="${F5_PASS:-admin}"
SCRIPT_PATH="/config/snmp/RPZ_Local_Processor/scripts/main.sh"
WRAPPER_PATH="/config/snmp/rpz_wrapper.sh"
INTERVAL="${INTERVAL:-300}"  # 預設 5 分鐘 (300 秒)

# API 端點
API_BASE="https://${F5_HOST}/mgmt/tm/sys/icall"
SCRIPT_ENDPOINT="${API_BASE}/script"
HANDLER_ENDPOINT="${API_BASE}/handler/periodic"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

echo "=========================================="
echo "  設定 RPZ 自動更新 (iCall - API 版本)"
echo "=========================================="
echo "F5 Host: ${F5_HOST}"
echo "執行間隔: ${INTERVAL} 秒"
echo "腳本路徑: ${SCRIPT_PATH}"
echo "Wrapper: ${WRAPPER_PATH}"
echo ""

# 檢查腳本是否存在
if [[ ! -f "$SCRIPT_PATH" ]]; then
    log_error "找不到主腳本 $SCRIPT_PATH"
    exit 1
fi

# 步驟 1: 建立 wrapper script (用於除錯)
log_info "步驟 1: 建立 Wrapper Script..."
cat > "$WRAPPER_PATH" << 'WRAPPER_EOF'
#!/bin/bash
{
    echo "=== $(date) - Wrapper Start ==="
    bash /config/snmp/RPZ_Local_Processor/scripts/main.sh
    exit_code=$?
    echo "=== $(date) - Exit Code: $exit_code ==="
    exit $exit_code
} >> /config/snmp/rpz_wrapper.log 2>&1
WRAPPER_EOF

chmod +x "$WRAPPER_PATH"
log_info "✓ Wrapper Script 已建立: $WRAPPER_PATH"
echo ""

# 步驟 2: 刪除舊的 iCall 配置 (如果存在)
log_info "步驟 2: 清理舊的 iCall 配置..."

# 刪除舊的 handler
if curl -sk -u "${F5_USER}:${F5_PASS}" \
    -X DELETE \
    "${HANDLER_ENDPOINT}/rpz_processor_handler" \
    2>/dev/null | grep -q "code"; then
    log_warn "舊的 handler 已刪除或不存在"
else
    log_info "無舊的 handler 需要刪除"
fi

# 刪除舊的 script
if curl -sk -u "${F5_USER}:${F5_PASS}" \
    -X DELETE \
    "${SCRIPT_ENDPOINT}/rpz_processor_script" \
    2>/dev/null | grep -q "code"; then
    log_warn "舊的 script 已刪除或不存在"
else
    log_info "無舊的 script 需要刪除"
fi

echo ""

# 步驟 3: 建立 iCall script (使用 REST API)
log_info "步驟 3: 建立 iCall Script (via REST API)..."

# 構建 JSON payload
# 注意：definition 中的特殊字元需要 JSON escape
SCRIPT_JSON=$(cat <<EOF
{
    "name": "rpz_processor_script",
    "definition": "exec bash ${WRAPPER_PATH}"
}
EOF
)

# 發送 API 請求
SCRIPT_RESPONSE=$(curl -sk -u "${F5_USER}:${F5_PASS}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "${SCRIPT_JSON}" \
    "${SCRIPT_ENDPOINT}")

# 檢查回應
if echo "$SCRIPT_RESPONSE" | grep -q '"name":"rpz_processor_script"'; then
    log_info "✓ iCall Script 已建立"
else
    log_error "iCall Script 建立失敗"
    echo "API Response:"
    echo "$SCRIPT_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$SCRIPT_RESPONSE"
    exit 1
fi

echo ""

# 步驟 4: 建立 iCall periodic handler (使用 REST API)
log_info "步驟 4: 建立 iCall Periodic Handler (via REST API)..."

HANDLER_JSON=$(cat <<EOF
{
    "name": "rpz_processor_handler",
    "interval": ${INTERVAL},
    "script": "rpz_processor_script"
}
EOF
)

HANDLER_RESPONSE=$(curl -sk -u "${F5_USER}:${F5_PASS}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "${HANDLER_JSON}" \
    "${HANDLER_ENDPOINT}")

# 檢查回應
if echo "$HANDLER_RESPONSE" | grep -q '"name":"rpz_processor_handler"'; then
    log_info "✓ iCall Periodic Handler 已建立"
else
    log_error "iCall Periodic Handler 建立失敗"
    echo "API Response:"
    echo "$HANDLER_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$HANDLER_RESPONSE"
    exit 1
fi

echo ""

# 步驟 5: 儲存配置
log_info "步驟 5: 儲存配置..."

SAVE_JSON='{"command":"save"}'
SAVE_RESPONSE=$(curl -sk -u "${F5_USER}:${F5_PASS}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "${SAVE_JSON}" \
    "https://${F5_HOST}/mgmt/tm/sys/config")

if echo "$SAVE_RESPONSE" | grep -q '"command":"save"'; then
    log_info "✓ 配置已儲存"
else
    log_warn "配置儲存可能失敗，但 iCall 已建立"
fi

echo ""
echo "=========================================="
echo "  設定完成！"
echo "=========================================="
echo ""
echo "檢查狀態:"
echo "  # 使用 tmsh"
echo "  tmsh list sys icall handler periodic rpz_processor_handler"
echo "  tmsh list sys icall script rpz_processor_script"
echo ""
echo "  # 使用 REST API"
echo "  curl -sku ${F5_USER}:PASS ${HANDLER_ENDPOINT}/rpz_processor_handler | python3 -m json.tool"
echo ""
echo "執行記錄:"
echo "  tail -f /var/log/ltm | grep RPZ"
echo "  tail -f /config/snmp/rpz_wrapper.log"
echo ""
echo "停用/啟用:"
echo "  # 使用 tmsh"
echo "  tmsh modify sys icall handler periodic rpz_processor_handler status inactive"
echo "  tmsh modify sys icall handler periodic rpz_processor_handler status active"
echo ""
echo "  # 使用 REST API"
echo "  curl -sku ${F5_USER}:PASS -H 'Content-Type: application/json' \\"
echo "    -X PATCH -d '{\"status\":\"inactive\"}' \\"
echo "    ${HANDLER_ENDPOINT}/rpz_processor_handler"
echo ""
echo "移除:"
echo "  # 使用 tmsh"
echo "  tmsh delete sys icall handler periodic rpz_processor_handler"
echo "  tmsh delete sys icall script rpz_processor_script"
echo "  rm -f /config/snmp/rpz_wrapper.sh /config/snmp/rpz_wrapper.log"
echo ""
echo "  # 使用 REST API"
echo "  curl -sku ${F5_USER}:PASS -X DELETE ${HANDLER_ENDPOINT}/rpz_processor_handler"
echo "  curl -sku ${F5_USER}:PASS -X DELETE ${SCRIPT_ENDPOINT}/rpz_processor_script"
echo ""
