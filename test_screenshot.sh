#!/bin/bash

# ==============================================================================
# TWM iRule 測試腳本 - 單一設備測試版本
# 用法: ./test_screenshot.sh <DNS_IP>
# 例如: ./test_screenshot.sh 10.8.38.6
# ==============================================================================

# 檢查參數
if [ -z "$1" ]; then
    echo "錯誤: 請提供 DNS 服務器 IP"
    echo "用法: $0 <DNS_IP>"
    echo ""
    echo "範例:"
    echo "  $0 10.8.38.6     # 環境1 (F5 DataGroup + rpzdg_v9)"
    echo "  $0 10.8.38.235   # 環境2 (F5 DNS Express + RPZv4)"
    echo "  $0 10.8.38.99    # 環境3 (BIND DNS + RPZ)"
    exit 1
fi

DNS_IP="$1"

echo "================================================================================"
echo "                    TWM iRule 修正專案 - DNS 測試結果"
echo "                         測試時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo "                         測試對象: $DNS_IP"
echo "================================================================================"
echo ""

# 測試案例定義（12個測試案例）
# 格式: "域名|預期結果|預期類型"
declare -a test_cases=(
    "www.google.com|通過|PASS"
    "www.123google.com|通過|PASS"
    "www.xxxgoogle.com|回應黑名單對應IP|BLOCK"
    "data.originmood.com|通過|PASS"
    "wwww.www.www.mood.com|回應RPZ Landing IP|BLOCK"
    "www.azure.com|通過|PASS"
    "azure.com|通過|PASS"
    "www.123azure.com|通過|PASS"
    "abc.com|回應RPZ Landing IP|BLOCK"
    "www.abc.com|通過|PASS"
    "www.ryantseng.work|回應RPZ Landing IP|BLOCK"
    "ryantseng.work|通過|PASS"
)

# 黑名單阻擋 IP（用於判定）
BLOCK_IPS=("210.64.24.25" "34.102.218.71" "182.173.0.170" "112.121.114.76" "182.173.0.181" "210.69.155.3" "35.206.236.238")

# 執行所有測試
echo "正在執行測試，請稍候..."
echo ""

declare -a results
declare -a pass_status

for i in "${!test_cases[@]}"; do
    IFS='|' read -r domain expected expected_type <<< "${test_cases[$i]}"

    result=$(dig @${DNS_IP} ${domain} +short +time=2 2>/dev/null | head -1)

    # 處理空結果
    if [ -z "$result" ]; then
        result="NXDOMAIN"
    fi

    results[$i]="$result"

    # 判定是否通過
    pass="❌"
    if [ "$expected_type" == "PASS" ]; then
        # 預期通過：結果不應該是阻擋 IP 或 NXDOMAIN
        is_blocked=0
        for block_ip in "${BLOCK_IPS[@]}"; do
            if [ "$result" == "$block_ip" ]; then
                is_blocked=1
                break
            fi
        done

        if [ $is_blocked -eq 0 ] && [ "$result" != "NXDOMAIN" ]; then
            pass="✅"
        fi
    elif [ "$expected_type" == "BLOCK" ]; then
        # 預期阻擋：結果應該是阻擋 IP
        for block_ip in "${BLOCK_IPS[@]}"; do
            if [ "$result" == "$block_ip" ]; then
                pass="✅"
                break
            fi
        done
    fi

    pass_status[$i]="$pass"
done

# 顯示結果
echo "================================================================================"
echo "                              測試結果"
echo "================================================================================"
echo ""
printf "%-30s | %-25s | %-20s | %-10s\n" "測試FQDN" "預期結果" "測試結果" "是否通過"
echo "--------------------------------------------------------------------------------"

for i in "${!test_cases[@]}"; do
    IFS='|' read -r domain expected expected_type <<< "${test_cases[$i]}"
    result="${results[$i]}"
    pass="${pass_status[$i]}"

    printf "%-30s | %-25s | %-20s | %-10s\n" "$domain" "$expected" "$result" "$pass"
done

echo ""
echo "================================================================================"

# 計算通過率
total_tests=${#test_cases[@]}
passed_tests=0
for pass in "${pass_status[@]}"; do
    if [ "$pass" == "✅" ]; then
        ((passed_tests++))
    fi
done

pass_rate=$((passed_tests * 100 / total_tests))

echo ""
echo "測試統計："
echo "  總測試數: $total_tests"
echo "  通過數: $passed_tests"
echo "  失敗數: $((total_tests - passed_tests))"
echo "  通過率: ${pass_rate}%"
echo ""
echo "================================================================================"
echo ""
echo "註解："
echo "  210.64.24.25    : RPZ 阻擋 (Landing IP)"
echo "  34.102.218.71   : 本地黑名單阻擋 (Landing IP)"
echo "  182.173.0.170   : PhishTW 阻擋 (Landing IP)"
echo "  NXDOMAIN        : 域名不存在"
echo "  其他 IP         : 正常解析（放行）"
echo ""
echo "================================================================================"
