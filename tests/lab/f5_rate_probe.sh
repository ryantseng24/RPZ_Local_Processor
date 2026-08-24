#!/bin/bash
# =============================================================================
# f5_rate_probe.sh
# 目的: 用真實的 parse_rpz.sh，在不同 raw/ 檔案數下量測失敗率。
#       不經任何自製 harness，直接看 production 程式碼的行為。
#
# 安全性: 輸出全在 /var/tmp，不寫 /config，不呼叫 tmsh。
# 用法:   ./f5_rate_probe.sh [每個 n 的重複次數]
# =============================================================================

REPS="${1:-30}"
SCRIPTS=/config/snmp/RPZ_Local_Processor/scripts
OUT=/var/tmp/rpz_e2e_probe_dirs      # 27 bytes，與 production 同長
SAMPLE=/var/tmp/dnsxdump_small.out

# 小樣本：讓成功的 parse 很快跑完。ls|head 的行為與樣本大小無關。
if [ ! -s "$SAMPLE" ]; then
    # 不用 `grep | head`：head 提早關閉 pipe 會讓 grep 收到 SIGPIPE。
    # sed 的 400q 會自行結束，不留下懸空的寫入端。
    sed -n '/\tIN\t\(A\|CNAME\|SOA\)\t/{p;}' /var/tmp/dnsxdump_sample.out 2>/dev/null \
        | sed -n '1,400p' > "$SAMPLE"
fi
[ -s "$SAMPLE" ] || { echo "缺 $SAMPLE"; exit 1; }
echo "樣本: $SAMPLE ($(wc -l < "$SAMPLE") 行)"
echo "每個 n 重複 $REPS 次，呼叫 $SCRIPTS/parse_rpz.sh"
echo

rm -rf "$OUT"; mkdir -p "$OUT/raw" "$OUT/parsed"
printf 'raw 前綴長度 = %s (production 32)\n\n' "$(( ${#OUT} + 5 ))"

i=0
printf '%-6s %-9s %-8s %-8s %s\n' "n" "ls輸出" "失敗" "失敗率" "退出碼分布"
for n in 5 30 67 80 100 110 120 125 141 169 179 300; do
    while [ "$i" -lt $((n - 1)) ]; do
        i=$((i + 1))
        : > "$OUT/raw/$(printf 'dnsxdump_2026%04d_%06d.out' "$i" "$i")"
    done
    cp "$SAMPLE" "$OUT/raw/dnsxdump_20260820_120501.out"

    bytes=$(ls -t "$OUT"/raw/dnsxdump_*.out | wc -c)
    fail=0; codes=""
    for t in $(seq 1 "$REPS"); do
        rm -rf "$OUT/parsed"; mkdir -p "$OUT/parsed"
        OUTPUT_DIR="$OUT" bash "$SCRIPTS/parse_rpz.sh" >/dev/null 2>&1
        rc=$?
        if [ "$rc" -ne 0 ]; then
            fail=$((fail + 1))
            case " $codes " in *" $rc "*) ;; *) codes="$codes $rc" ;; esac
        fi
    done
    printf '%-6s %-9s %-8s %-8s %s\n' "$n" "${bytes}B" "$fail/$REPS" \
        "$(awk "BEGIN{printf \"%.0f%%\", 100*$fail/$REPS}")" "${codes:- -}"
done

rm -rf "$OUT"
echo
echo "(測試目錄 $OUT 已刪除)"
