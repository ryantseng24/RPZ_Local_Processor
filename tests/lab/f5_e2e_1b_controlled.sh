#!/bin/bash
# =============================================================================
# f5_e2e_1b_controlled.sh — Phase 1B 受控 e2e（fail-closed 版，P1B-01）
#
# 破壞性等級: 高。寫真實 /config/snmp/rpz_datagroups、停/啟 iCall handler、
# 套用 patch、tmsh save sys config。只准在 LAB 執行。
#
# 硬性防護（無 bypass 旗標）:
#   1) 第一個參數必須是 --lab-only
#   2) hostname 必須等於 cdns.ryantseng.work
#   3) 環境變數 E2E_CONFIRM 必須等於 I-UNDERSTAND-THIS-MODIFIES-cdns.ryantseng.work
#   4) handler 初始狀態必須 active / interval 300
# 全部通過前不做任何變更。
#
# 用法:
#   E2E_CONFIRM=I-UNDERSTAND-THIS-MODIFIES-cdns.ryantseng.work \
#       bash f5_e2e_1b_controlled.sh --lab-only
# =============================================================================
set -u

LAB_HOST="cdns.ryantseng.work"
CONFIRM_WANT="I-UNDERSTAND-THIS-MODIFIES-${LAB_HOST}"
S=/config/snmp/RPZ_Local_Processor/scripts
OUT=/config/snmp/rpz_datagroups
PAT='RPZ_Local_Processor/scripts/[a-z_]+[.]sh|rpz_wrapper[.]sh'
HANDLER="sys icall handler periodic rpz_processor_handler"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad(){ FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
refuse(){ echo "拒絕: $*"; exit 2; }

# ---------- 防護（改任何東西之前） ----------
[ "${1:-}" = "--lab-only" ] || refuse "需要參數 --lab-only"
# 用 uname -n: F5 非互動 shell 的 hostname 是 wrapper，stdout 為空
[ "$(uname -n)" = "$LAB_HOST" ] || refuse "主機 $(uname -n) 不是 ${LAB_HOST}"
[ "${E2E_CONFIRM:-}" = "$CONFIRM_WANT" ] || refuse "E2E_CONFIRM 未設定或不符（需為含完整主機名的確認字串）"
H0=$(tmsh list $HANDLER status interval 2>/dev/null)
printf '%s' "$H0" | grep -q 'status active' || refuse "handler 初始狀態不是 active"
printf '%s' "$H0" | grep -q 'interval 300'  || refuse "handler interval 不是 300"

# ---------- 從這裡開始有副作用，trap 為安全網 ----------
MANIFEST=()
on_exit(){
    local rc=$? f left=0
    if [ "${#MANIFEST[@]}" -gt 0 ]; then
        echo "[trap] 清除 ${#MANIFEST[@]} 個殘留合成檔"
        for f in "${MANIFEST[@]}"; do rm -f -- "$f"; done
        for f in "${MANIFEST[@]}"; do [ -e "$f" ] && left=$((left+1)); done
        [ "$left" = 0 ] || echo "[trap] 警告: 仍殘留 ${left} 個合成檔，需人工清除"
    fi
    if ! tmsh modify $HANDLER status active 2>/dev/null; then
        echo "[trap] 警告: handler 恢復 active 失敗，需人工處理"
    fi
    if ! tmsh save sys config >/dev/null 2>&1; then
        echo "[trap] 警告: save sys config 失敗，需人工處理"
    fi
    tmsh list $HANDLER status 2>/dev/null | grep -q 'status active' \
        || echo "[trap] 警告: 最終 handler 狀態非 active"
    exit "$rc"
}
trap on_exit EXIT
wait_quiet(){
    local i=0
    while pgrep -f "$PAT" >/dev/null 2>&1; do
        i=$((i+1)); [ "$i" -gt 90 ] && return 1
        sleep 2
    done
    return 0
}
die(){ echo "!! 中止: $*"; exit 1; }
dg_field(){ tmsh list sys file data-group rpztw | awk -v k="$1" '$1==k {print $2}'; }

echo "=== 1. 停 handler 並驗證 ==="
tmsh modify $HANDLER status inactive || die "handler inactive 指令失敗"
tmsh list $HANDLER status | grep -q 'status inactive' || die "handler 未進入 inactive"
ok "handler inactive"

echo "=== 2. 等 RPZ 靜止 ==="
wait_quiet || die "等待靜止逾時"
ok "RPZ 靜止"

echo "=== 3. apply + check（gate）==="
bash /var/tmp/rpz_patch_phase1b_v1.sh apply; APPLY_RC=$?
echo "APPLY_RC=$APPLY_RC"; [ "$APPLY_RC" = 0 ] || die "apply 失敗"
CHECK_OUT=$(bash /var/tmp/rpz_patch_phase1b_v1.sh check 2>&1); CHECK_RC=$?
echo "CHECK_RC=$CHECK_RC"
[ "$CHECK_RC" = 0 ] || die "check RC=$CHECK_RC"
printf '%s' "$CHECK_OUT" | grep -q "已套用 Phase 1B" || die "check 未確認已套用"
ok "apply/check RC=0 且已套用"

echo "=== 4. 播種合成檔（每一步都有 gate）==="
seed_one(){
    # 拒絕覆蓋既存路徑；建立與 touch 都要成功；建立後立刻記入 manifest
    local f="$1"
    [ -e "$f" ] && die "合成檔路徑已存在，拒絕覆蓋: $f"
    : > "$f" || die "無法建立合成檔: $f"
    MANIFEST+=("$f")
    touch -d "3 days ago" "$f" || die "touch 失敗（mtime 未設為 3 天前）: $f"
}
for i in $(seq 1 30); do
    d=$(( (i-1) % 28 + 1 ))
    seed_one "$OUT/raw/$(printf 'dnsxdump_202607%02d_%06d.out' "$d" "$i")"
    for z in rpztw phishtw rpzip; do
        seed_one "$OUT/parsed/$(printf '%s_202607%02d_%06d.txt' "$z" "$d" "$i")"
    done
done
NOW=$(date +%s); nfound=0
for f in "${MANIFEST[@]}"; do
    [ -f "$f" ] || die "合成檔不存在: $f"
    m=$(stat -c %Y "$f")
    [ "$m" -lt $((NOW - 172800)) ] || die "合成檔 mtime 不夠舊（可能被 pipeline 選中）: $f"
    nfound=$((nfound+1))
done
[ "$nfound" = 120 ] && ok "播種並驗證 120 個合成檔（存在 + mtime 早於 2 天前）" || die "合成檔數 ${nfound} != 120"

echo "=== 5. before 數值 ==="
REV0=$(dg_field revision); SIZE0=$(dg_field size); MT0=$(stat -c %Y "$OUT/final/rpztw.txt")
echo "REV0=$REV0 SIZE0=$SIZE0 MT0=$MT0"
[ -n "$REV0" ] && [ -n "$SIZE0" ] || die "無法取得 before 數值"

echo "=== 6. main.sh --force ==="
bash "$S/main.sh" --force > /var/tmp/e2e_1b_run.log 2>&1
MAIN_RC=$?
echo "main.sh RC=${MAIN_RC}"
[ "$MAIN_RC" = 0 ] && ok "MAIN_RC=0" || bad "MAIN_RC=$MAIN_RC"
grep -q "使用 dnsxdump 檔案" /var/tmp/e2e_1b_run.log && ok "診斷行: 使用 dnsxdump 檔案" || bad "缺診斷行: 使用 dnsxdump 檔案"
grep -q "處理完成" /var/tmp/e2e_1b_run.log && ok "診斷行: 處理完成" || bad "缺診斷行: 處理完成"
grep -q "dnsxdump_202607" /var/tmp/e2e_1b_run.log && bad "pipeline 選中合成檔" || ok "pipeline 未選中合成檔"
grep -E "數量上限清理" /var/tmp/e2e_1b_run.log | sed 's/^/    /'
rm -f /var/tmp/e2e_1b_run.log

echo "=== 7. after 數值與斷言 ==="
REV1=$(dg_field revision); SIZE1=$(dg_field size); MT1=$(stat -c %Y "$OUT/final/rpztw.txt")
echo "REV1=$REV1 SIZE1=$SIZE1 MT1=$MT1"
[ "$REV1" -gt "$REV0" ] && ok "revision ${REV0} -> ${REV1}（有增加）" || bad "revision 未增加（${REV0} -> ${REV1}）"
[ "$SIZE1" -gt 1000000 ] && ok "DataGroup size=${SIZE1}（非 0，量級正常）" || bad "DataGroup size=${SIZE1}"
[ "$MT1" -gt "$MT0" ] && ok "final/rpztw.txt mtime 有更新" || bad "final mtime 未更新"
fsz=$(stat -c %s "$OUT/final/rpztw.txt")
[ "$fsz" -gt 1000000 ] && ok "final/rpztw.txt=${fsz} bytes" || bad "final/rpztw.txt=${fsz} bytes"

echo "=== 8. 家族數量斷言（播種過的家族必須精確 = 24，0 不算通過）==="
n=$(ls "$OUT"/raw/dnsxdump_*.out 2>/dev/null | wc -l)
[ "$n" = 24 ] && ok "raw=24" || bad "raw=$n 應為 24"
for z in rpztw phishtw rpzip; do
    n=$(ls "$OUT/parsed/${z}_"*.txt 2>/dev/null | wc -l)
    [ "$n" = 24 ] && ok "${z}=24" || bad "${z}=$n 應為 24"
done

echo "=== 9. 只清 manifest 內的合成檔並驗證 ==="
left=0
for f in "${MANIFEST[@]}"; do
    rm -f -- "$f" || echo "  rm 失敗: $f"
done
for f in "${MANIFEST[@]}"; do [ -e "$f" ] && left=$((left+1)); done
if [ "$left" = 0 ]; then
    ok "合成檔全部清除"
    MANIFEST=()
else
    bad "殘留 ${left} 個合成檔（manifest 保留給 EXIT trap 重試）"
fi

echo "=== 10. 恢復 handler、存檔、驗證最終狀態 ==="
tmsh modify $HANDLER status active || die "handler active 指令失敗"
if tmsh save sys config >/dev/null 2>&1; then ok "save sys config 成功"; else bad "save sys config 失敗"; fi
HF=$(tmsh list $HANDLER status interval)
printf '%s' "$HF" | grep -q 'status active' && ok "最終 handler=active" || bad "最終 handler 非 active"
printf '%s' "$HF" | grep -q 'interval 300' && ok "最終 interval=300" || bad "最終 interval 非 300"

echo
echo "E2E PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] || exit 1
exit 0
