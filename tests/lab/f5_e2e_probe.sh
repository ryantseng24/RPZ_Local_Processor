#!/bin/bash
# =============================================================================
# f5_e2e_probe.sh
# 目的: 用「真實的 parse_rpz.sh / generate_datagroup.sh」重現步驟 3、步驟 4 失敗，
#       並用 bash -x 印出確切死在哪一行。
#
# 安全性:
#   - 全程用 OUTPUT_DIR 環境變數把輸出導到 /var/tmp，不寫 /config
#   - OUTPUT_DIR 路徑長度刻意等於 production 的 27 bytes，
#     所以 ls 輸出的每行位元組數與 production 完全相同
#   - 不執行 update_datagroup.sh、不呼叫 tmsh、不碰真的 DataGroup
#   - 不碰 /config/snmp/.*_soa_serial.last
#
# 用法:
#   ./f5_e2e_probe.sh <dnsxdump 樣本檔> [腳本目錄]
# 例:
#   ./f5_e2e_probe.sh /var/tmp/dnsxdump_all.txt /config/snmp/RPZ_Local_Processor/scripts
# =============================================================================

SAMPLE="$1"
SCRIPTS="${2:-/config/snmp/RPZ_Local_Processor/scripts}"

# production: /config/snmp/rpz_datagroups = 27 bytes
# 以下長度也是 27 bytes，確保 ls 輸出行長一致
OUT=/var/tmp/rpz_e2e_probe_dirs
TRACE=/var/tmp/rpz_e2e_trace

if [ -z "$SAMPLE" ] || [ ! -s "$SAMPLE" ]; then
    echo "用法: $0 <dnsxdump 樣本檔> [腳本目錄]"
    echo "樣本檔要是真實 dnsxdump 格式（可從別台複製，或用專案內的 dnsxdump_all.txt）"
    exit 1
fi
for s in parse_rpz.sh generate_datagroup.sh utils.sh; do
    [ -f "$SCRIPTS/$s" ] || { echo "找不到 $SCRIPTS/$s"; exit 1; }
done

echo "=============================================================="
echo " f5_e2e_probe  主機: $(hostname)  時間: $(date '+%F %T')"
echo " OUTPUT_DIR = $OUT  (長度 ${#OUT}，production 為 27)"
echo " 樣本檔 = $SAMPLE ($(wc -l < "$SAMPLE") 行)"
echo "=============================================================="
echo

mkdir -p "$TRACE" || exit 1

prepare_raw() {
    # prepare_raw <總檔數>  最新的一個是真實樣本，其餘是 0 bytes 佔位
    local total="$1" i name
    rm -rf "$OUT"
    mkdir -p "$OUT/raw" "$OUT/parsed" "$OUT/final"
    i=0
    while [ "$i" -lt $((total - 1)) ]; do
        i=$((i + 1))
        name=$(printf 'dnsxdump_2026%04d_%06d.out' "$i" "$i")
        : > "$OUT/raw/$name"
        touch -t 202608010000 "$OUT/raw/$name"
    done
    cp "$SAMPLE" "$OUT/raw/dnsxdump_20260820_120501.out"
    touch "$OUT/raw/dnsxdump_20260820_120501.out"
}

prepare_parsed() {
    # prepare_parsed <每個 zone 的檔數>
    local total="$1" i name
    rm -rf "$OUT/parsed"; mkdir -p "$OUT/parsed"
    for z in rpztw phishtw rpzip; do
        i=0
        while [ "$i" -lt $((total - 1)) ]; do
            i=$((i + 1))
            name=$(printf '%s_2026%04d_%06d.txt' "$z" "$i" "$i")
            : > "$OUT/parsed/$name"
            touch -t 202608010000 "$OUT/parsed/$name"
        done
    done
    # 最新的一份放真資料，讓 cp 有東西可複製
    head -20000 "$SAMPLE" > "$OUT/parsed/rpztw_20260820_120501.txt"
    echo '"example.invalid" := "127.0.0.1",' > "$OUT/parsed/phishtw_20260820_120501.txt"
    : > "$OUT/parsed/rpzip_20260820_120501.txt"
}

run_step3() {
    local n="$1" log="$TRACE/step3_n${n}.log"
    prepare_raw "$n"
    OUTPUT_DIR="$OUT" bash -x "$SCRIPTS/parse_rpz.sh" > "$log" 2>&1
    local rc=$?
    local parsed_cnt
    parsed_cnt=$(ls -1 "$OUT/parsed" 2>/dev/null | wc -l)
    printf '步驟3  raw檔數=%-5s exit=%-4s parsed產出=%-4s trace=%s\n' \
        "$n" "$rc" "$parsed_cnt" "$log"
    if [ "$rc" -ne 0 ]; then
        echo "  --- trace 最後 12 行 ---"
        tail -12 "$log" | cut -c1-180 | sed 's/^/    /'
    fi
}

run_step4() {
    local n="$1" log="$TRACE/step4_n${n}.log"
    prepare_parsed "$n"
    OUTPUT_DIR="$OUT" bash -x "$SCRIPTS/generate_datagroup.sh" > "$log" 2>&1
    local rc=$?
    printf '步驟4  每zone檔數=%-5s exit=%-4s final內容: %s\n' \
        "$n" "$rc" "$(ls -1 "$OUT/final" 2>/dev/null | tr '\n' ' ')"
    if [ "$rc" -ne 0 ]; then
        echo "  --- trace 最後 12 行 ---"
        tail -12 "$log" | cut -c1-180 | sed 's/^/    /'
    fi
}

echo "===== 步驟 3（parse_rpz.sh）：raw/ 檔數逐步增加 ====="
for n in 5 67 125 141 169 179 300 600; do run_step3 "$n"; done
echo

echo "===== 步驟 4（generate_datagroup.sh）：parsed/ 每 zone 檔數逐步增加 ====="
for n in 5 67 95 141 200 300; do run_step4 "$n"; done
echo

echo "===== 清除 ====="
echo "  刪除 $OUT"
rm -rf "$OUT"
echo "  trace 保留在 ${TRACE}（在 /var/tmp，與 /config 不同分割區）"
echo
echo "判讀: exit=141 就是 SIGPIPE，trace 的最後一行會顯示是哪一行 ls|head。"
echo "      若各 n 都 exit=0，代表這一行不是失敗點，要換方向找。"
