#!/bin/bash
# =============================================================================
# f5_e2e_1c_controlled.sh — Phase 1C 受控 e2e（fail-closed，僅限指定 LAB）
# 破壞性等級: 高。套用 patch、停/啟 handler、真實資料執行、save sys config。
# 防護與 f5_e2e_1b_controlled.sh 相同（--lab-only、主機名、E2E_CONFIRM、
# handler 初始 active/300），無 bypass。
# 用法:
#   E2E_CONFIRM=I-UNDERSTAND-THIS-MODIFIES-cdns.ryantseng.work \
#       bash f5_e2e_1c_controlled.sh --lab-only
# =============================================================================
set -u
LAB_HOST="cdns.ryantseng.work"
CONFIRM_WANT="I-UNDERSTAND-THIS-MODIFIES-${LAB_HOST}"
S=/config/snmp/RPZ_Local_Processor/scripts
LTM=/var/log/ltm
PAT='RPZ_Local_Processor/scripts/[a-z_]+[.]sh|rpz_wrapper[.]sh'
HANDLER="sys icall handler periodic rpz_processor_handler"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad(){ FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
refuse(){ echo "拒絕: $*"; exit 2; }

[ "${1:-}" = "--lab-only" ] || refuse "需要參數 --lab-only"
[ "$(uname -n)" = "$LAB_HOST" ] || refuse "主機 $(uname -n) 不是 ${LAB_HOST}"
[ "${E2E_CONFIRM:-}" = "$CONFIRM_WANT" ] || refuse "E2E_CONFIRM 未設定或不符"
H0=$(tmsh list $HANDLER status interval 2>/dev/null); H0_RC=$?
[ "$H0_RC" = 0 ] || refuse "tmsh 查詢 handler 失敗（rc=${H0_RC}）"
ST0=$(printf '%s\n' "$H0" | awk '$1=="status"{print $2; exit}')
IV0=$(printf '%s\n' "$H0" | awk '$1=="interval"{print $2; exit}')
[ "$ST0" = "active" ] || refuse "handler 初始狀態不是 active（實際: ${ST0:-無}）"
[ "$IV0" = "300" ]    || refuse "handler interval 不是 300（實際: ${IV0:-無}）"

on_exit(){
    local rc=$?
    tmsh modify $HANDLER status active 2>/dev/null || echo "[trap] 警告: handler 恢復失敗"
    tmsh save sys config >/dev/null 2>&1 || echo "[trap] 警告: save 失敗"
    exit "$rc"
}
trap on_exit EXIT
die(){ echo "!! 中止: $*"; exit 1; }
wait_quiet(){
    local i=0 rc
    while :; do
        pgrep -f "$PAT" >/dev/null 2>&1; rc=$?
        case "$rc" in
            0) : ;;                                  # 有程序，繼續等
            1) return 0 ;;                           # 沒有程序
            *) die "pgrep 查詢失敗（rc=${rc}），不得當成沒有程序" ;;
        esac
        i=$((i+1)); [ "$i" -gt 90 ] && return 1
        sleep 2
    done
}
dg_field(){
    # 查詢失敗（tmsh 非零）時回傳非零，呼叫端必須 die；不得用失敗輸出當證據
    local out rc
    out=$(tmsh list sys file data-group rpztw 2>/dev/null); rc=$?
    [ "$rc" = 0 ] || return "$rc"
    printf '%s\n' "$out" | awk -v k="$1" '$1==k {print $2; exit}'
}

echo "=== 1. 停 handler 並驗證 ==="
tmsh modify $HANDLER status inactive || die "inactive 失敗"
H1=$(tmsh list $HANDLER status 2>/dev/null); H1_RC=$?
[ "$H1_RC" = 0 ] || die "tmsh 查詢失敗（rc=${H1_RC}）"
ST1=$(printf '%s\n' "$H1" | awk '$1=="status"{print $2; exit}')
[ "$ST1" = "inactive" ] || die "未進入 inactive（實際: ${ST1:-無}）"
ok "handler inactive"

echo "=== 2. 等 RPZ 靜止 ==="
wait_quiet || die "等待靜止逾時"
ok "RPZ 靜止"

echo "=== 3. apply + check（gate）==="
bash /var/tmp/rpz_patch_phase1c_v1.sh apply; APPLY_RC=$?
echo "APPLY_RC=$APPLY_RC"; [ "$APPLY_RC" = 0 ] || die "apply 失敗"
CHECK_OUT=$(bash /var/tmp/rpz_patch_phase1c_v1.sh check 2>&1); CHECK_RC=$?
echo "CHECK_RC=$CHECK_RC"; [ "$CHECK_RC" = 0 ] || die "check RC=$CHECK_RC"
printf '%s' "$CHECK_OUT" | grep -q "已套用 Phase 1C" || die "check 未確認已套用"
ok "apply/check RC=0 且已套用 Phase 1C"

echo "=== 4. before 數值與 ltm 基準 ==="
REV0=$(dg_field revision) || die "tmsh 查詢 revision 失敗"
SIZE0=$(dg_field size)     || die "tmsh 查詢 size 失敗"
LTM0=$(wc -l < "$LTM" | tr -d ' ')
echo "REV0=$REV0 SIZE0=$SIZE0 LTM_BASE=$LTM0"
[ -n "$REV0" ] && [ -n "$SIZE0" ] || die "before 數值為空"

echo "=== 5. main.sh --force（真實資料）==="
bash "$S/main.sh" --force > /var/tmp/e2e_1c_run.log 2>&1
MAIN_RC=$?
echo "main.sh RC=${MAIN_RC}"
[ "$MAIN_RC" = 0 ] && ok "MAIN_RC=0" || bad "MAIN_RC=$MAIN_RC"
grep -q "使用 dnsxdump 檔案" /var/tmp/e2e_1c_run.log && ok "wrapper 診斷行仍存在" || bad "缺 wrapper 診斷行"
rm -f /var/tmp/e2e_1c_run.log

echo "=== 6. syslog 事件斷言（本次新增的 ltm 行）==="
sleep 1
NEWL=$(tail -n "+$((LTM0 + 1))" "$LTM" | grep "RPZLocal")
printf '%s\n' "$NEWL" | sed 's/^/    /'
printf '%s' "$NEWL" | grep -q "notice RPZLocal\[[0-9]*\]: dnsxdump exported" && ok "extract 事件（notice）" || bad "缺 extract 事件"
printf '%s' "$NEWL" | grep -q "notice RPZLocal\[[0-9]*\]: updated DataGroup rpztw" && ok "update 事件（notice）" || bad "缺 update 事件"
printf '%s' "$NEWL" | grep -q "notice RPZLocal\[[0-9]*\]: RPZ processing completed in" && ok "completed 事件（notice）" || bad "缺 completed 事件"
printf '%s' "$NEWL" | grep -qE "INFO:|ERROR:" && bad "事件殘留自帶前綴" || ok "無重複前綴（F5 原生格式）"

echo "=== 7. after 數值斷言 ==="
REV1=$(dg_field revision) || die "tmsh 查詢 revision 失敗"
SIZE1=$(dg_field size)     || die "tmsh 查詢 size 失敗"
echo "REV1=$REV1 SIZE1=$SIZE1"
[ "$REV1" -gt "$REV0" ] && ok "revision ${REV0} -> ${REV1}" || bad "revision 未增加"
[ "$SIZE1" -gt 1000000 ] && ok "size=${SIZE1}" || bad "size=${SIZE1}"
n=$(ls /config/snmp/rpz_datagroups/raw/dnsxdump_*.out 2>/dev/null | wc -l)
[ "$n" -le 24 ] && ok "raw=${n}（保留策略仍有效）" || bad "raw=${n} 超過 24"

echo "=== 8. 恢復 handler、存檔、驗證 ==="
tmsh modify $HANDLER status active || die "active 失敗"
if tmsh save sys config >/dev/null 2>&1; then ok "save sys config 成功"; else bad "save 失敗"; fi
HF=$(tmsh list $HANDLER status interval 2>/dev/null); HF_RC=$?
[ "$HF_RC" = 0 ] || die "tmsh 查詢失敗（rc=${HF_RC}）"
STF=$(printf '%s\n' "$HF" | awk '$1=="status"{print $2; exit}')
IVF=$(printf '%s\n' "$HF" | awk '$1=="interval"{print $2; exit}')
[ "$STF" = "active" ] && ok "最終 handler=active" || bad "最終 handler=${STF:-無}"
[ "$IVF" = "300" ]    && ok "最終 interval=300"   || bad "最終 interval=${IVF:-無}"

echo
echo "E2E PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" = 0 ]; then
    # 正常完成且已核對恢復狀態: 解除 trap，不再重複執行未納入判定的恢復動作
    trap - EXIT
    exit 0
fi
exit 1
