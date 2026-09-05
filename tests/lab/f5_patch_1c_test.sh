#!/bin/bash
# =============================================================================
# f5_patch_1c_test.sh — Phase 1C patch 的 LAB 迴歸測試
# 涵蓋: patch 機制（M1-M8）、syslog 事件功能（F1-F3）。
# 安全性: fixture 在 /var/tmp/rpz_1c_test；patch 以 sed 副本改指 fixture；
#         功能測試的 logger 行會進真實 /var/log/ltm（LAB 限定，良性）。
# 前置: /var/tmp/origsrc/scripts（v1.2 原版）、/var/tmp/rpz_patch_phase1b_v1.sh
#       （抽出 1B 版 main.sh 作為 1C 的部署前版本）。
# 用法: bash f5_patch_1c_test.sh [patch路徑]
# =============================================================================
set -u

PATCH_SRC="${1:-/var/tmp/rpz_patch_phase1c_v1.sh}"
P1B_SRC="${2:-/var/tmp/rpz_patch_phase1b_v1.sh}"
ORIGSRC=/var/tmp/origsrc/scripts
REAL=/config/snmp/RPZ_Local_Processor/scripts
R=/var/tmp/rpz_1c_test
TGT="$R/scripts"; BK="$R/backups"; NEWSRC="$R/newsrc"; ORIG1C="$R/orig1c"; OUTF="$R/out"; PT="$R/patch_test.sh"
LTM=/var/log/ltm

OM=d1e1f688d939a5a5e87282605d0e3eed
OE=62aeaf053b08f3411fe530f33555c414
OUP=f8b038bc06df1c07050cd2922a91c5aa
NM=9d8538a68480a1a0489058be6b1d6622
NE=fea7c2e29f5380ab22611f7b2cc97fbc
NUP=67227cb39028dc2bf17b14ef9c871bc4

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }
md5f(){ md5sum "$1" 2>/dev/null | awk '{print $1}'; }
cleanup_all(){ rm -rf "$R"; }
trap cleanup_all EXIT

# ---------- 前置 ----------
[ -s "$PATCH_SRC" ] || { echo "缺 patch: $PATCH_SRC"; exit 2; }
[ -s "$P1B_SRC" ] || { echo "缺 1B patch: $P1B_SRC"; exit 2; }
[ "$(md5f "$ORIGSRC/extract_rpz.sh")" = "$OE" ] || { echo "origsrc extract md5 不符"; exit 2; }
[ "$(md5f "$ORIGSRC/update_datagroup.sh")" = "$OUP" ] || { echo "origsrc update md5 不符"; exit 2; }

rm -rf "$R"; mkdir -p "$TGT" "$BK" "$NEWSRC" "$ORIG1C" "$OUTF/raw" "$OUTF/parsed" "$OUTF/final"

xblock(){ # xblock <file> <n> <out>
    awk -v want="$2" '
        /^cat <<'\''__RPZ_EMBED__'\''$/ { n++; inb=1; next }
        /^__RPZ_EMBED__$/               { inb=0; next }
        inb && n == want                { print }
    ' "$1" > "$3"
}
# 1C 的部署前版本組
xblock "$P1B_SRC" 1 "$ORIG1C/main.sh"
[ "$(md5f "$ORIG1C/main.sh")" = "$OM" ] || { echo "1B 內嵌 main md5 不符"; exit 2; }
cp -p "$ORIGSRC/extract_rpz.sh" "$ORIG1C/"
cp -p "$ORIGSRC/update_datagroup.sh" "$ORIG1C/"
# 1C 修正版組
xblock "$PATCH_SRC" 1 "$NEWSRC/main.sh"
xblock "$PATCH_SRC" 2 "$NEWSRC/extract_rpz.sh"
xblock "$PATCH_SRC" 3 "$NEWSRC/update_datagroup.sh"
[ "$(md5f "$NEWSRC/main.sh")" = "$NM" ] || { echo "抽出 main md5 不符"; exit 2; }
[ "$(md5f "$NEWSRC/extract_rpz.sh")" = "$NE" ] || { echo "抽出 extract md5 不符"; exit 2; }
[ "$(md5f "$NEWSRC/update_datagroup.sh")" = "$NUP" ] || { echo "抽出 update md5 不符"; exit 2; }
cp -p "$REAL/utils.sh" "$NEWSRC/utils.sh"

sed -e 's|^SCRIPTS_DIR="/config/snmp/RPZ_Local_Processor/scripts"$|SCRIPTS_DIR="'"$TGT"'"|' \
    -e 's|^BACKUP_ROOT="/var/tmp"$|BACKUP_ROOT="'"$BK"'"|' "$PATCH_SRC" > "$PT"
grep -q "^SCRIPTS_DIR=\"$TGT\"" "$PT" || { echo "sed 失敗"; exit 2; }
bash -n "$PT" || exit 2
echo "fixture 就緒"
echo

reset_tgt(){
    rm -rf "$TGT" "$BK"; mkdir -p "$TGT" "$BK"
    local f
    for f in main.sh extract_rpz.sh update_datagroup.sh; do cp -p "$ORIG1C/$f" "$TGT/$f"; done
}
wait_quiet(){
    local i=0
    while pgrep -f "RPZ_Local_Processor/scripts/[a-z_]+[.]sh|rpz_wrapper[.]sh" >/dev/null 2>&1; do
        i=$((i+1)); [ "$i" -gt 90 ] && return 1; sleep 2
    done
    return 0
}
run_pt(){
    case "$1" in apply|rollback) wait_quiet; sleep 1 ;; esac
    OUT=$(bash "$PT" "$@" 2>&1); RC=$?
    if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q "RPZ 處理程序執行中"; then
        wait_quiet; sleep 1; OUT=$(bash "$PT" "$@" 2>&1); RC=$?
    fi
}
expect_rc(){ [ "$RC" = "$2" ] && ok "$1: RC=$RC" || { bad "$1: RC=$RC 應為 $2"; printf '%s\n' "$OUT" | tail -3 | sed 's/^/      /'; } }
expect_out(){ printf '%s' "$OUT" | grep -q "$2" && ok "$1: 訊息含「$2」" || bad "$1: 訊息缺「$2」"; }
st3(){ printf '%s/%s/%s' "$(md5f "$TGT/main.sh")" "$(md5f "$TGT/extract_rpz.sh")" "$(md5f "$TGT/update_datagroup.sh")"; }

# ---------- M1: 部署前版本 check ----------
echo "== M1: check（部署前版本）=="
reset_tgt
run_pt check; expect_rc M1 0; expect_out M1 "全部是部署前版本"

# ---------- M2: 正常 apply ----------
echo "== M2: apply =="
run_pt apply; expect_rc M2 0
[ "$(st3)" = "$NM/$NE/$NUP" ] && ok "M2: 三檔皆修正版" || bad "M2: 狀態錯 $(st3)"
B1=""; for d in "$BK"/rpz_patch1c_backup_*; do [ -d "$d" ] && B1="$d"; done
[ "$(md5f "$B1/main.sh")" = "$OM" ] && ok "M2: 備份為純部署前版本" || bad "M2: 備份錯"
n=$(find "$TGT" -maxdepth 1 -name ".*" -type f | wc -l | tr -d ' ')
[ "$n" = 0 ] && ok "M2: 無殘留暫存檔" || bad "M2: 殘留 ${n}"

# ---------- M3: 冪等 ----------
echo "== M3: 重複 apply =="
run_pt apply; expect_rc M3 0; expect_out M3 "無需動作"

# ---------- M4: 版本不明拒絕 ----------
echo "== M4: 版本不明 =="
echo "# x" >> "$TGT/main.sh"
run_pt check; expect_rc M4-check 2
run_pt apply; expect_rc M4-apply 2

# ---------- M5: rollback ----------
echo "== M5: rollback =="
reset_tgt
run_pt apply
B1=""; for d in "$BK"/rpz_patch1c_backup_*; do [ -d "$d" ] && B1="$d"; done
run_pt rollback "$B1"; expect_rc M5 0
[ "$(st3)" = "$OM/$OE/$OUP" ] && ok "M5: 已還原部署前版本" || bad "M5: 狀態錯"

# ---------- M6: 混合備份拒絕 ----------
echo "== M6: 混合備份拒絕 =="
run_pt apply
BX="$BK/manual_mixed"; mkdir -p "$BX"
cp -p "$NEWSRC/main.sh" "$BX/main.sh"; cp -p "$ORIG1C/extract_rpz.sh" "$BX/"; cp -p "$ORIG1C/update_datagroup.sh" "$BX/"
( cd "$BX" && md5sum main.sh extract_rpz.sh update_datagroup.sh > md5sums.txt )
run_pt rollback "$BX"; expect_rc M6 2; expect_out M6 "不是純部署前版本"
[ "$(st3)" = "$NM/$NE/$NUP" ] && ok "M6: 狀態不變" || bad "M6: 狀態被改"

# ---------- M7: 目前檔案缺失拒絕 ----------
echo "== M7: 目前檔案缺失 =="
BP="$BK/manual_pure"; mkdir -p "$BP"
for f in main.sh extract_rpz.sh update_datagroup.sh; do cp -p "$ORIG1C/$f" "$BP/$f"; done
( cd "$BP" && md5sum main.sh extract_rpz.sh update_datagroup.sh > md5sums.txt )
rm -f "$TGT/extract_rpz.sh"
run_pt rollback "$BP"; expect_rc M7 2; expect_out M7 "版本不明或缺少"
[ "$(md5f "$TGT/main.sh")" = "$NM" ] && ok "M7: 其餘檔案未被改動" || bad "M7: 檔案被改動"

# ---------- M8: chattr 注入與續跑（extract 上鎖，安裝順序 main->extract->update）----------
echo "== M8: apply 失敗注入與續跑 =="
reset_tgt
chattr +i "$TGT/extract_rpz.sh" || bad "M8: chattr 失敗"
run_pt apply; expect_rc M8-lock 1
[ "$(st3)" = "$NM/$OE/$OUP" ] && ok "M8-lock: 中間狀態 n/o/o" || bad "M8-lock: 狀態錯 $(st3)"
chattr -i "$TGT/extract_rpz.sh"
run_pt apply; expect_rc M8-resume 0
[ "$(st3)" = "$NM/$NE/$NUP" ] && ok "M8-resume: 補齊" || bad "M8-resume: 狀態錯"

# =============================================================================
# 功能測試: syslog 事件（fixture OUTPUT_DIR；logger 行進真實 ltm，用行數基準）
# =============================================================================
echo "== F1: NO_UPDATE 路徑的 notice 事件 =="
printf '#!/bin/bash\necho "NO_UPDATE"\n' > "$NEWSRC/check_soa.sh"; chmod +x "$NEWSRC/check_soa.sh"
LTM0=$(wc -l < "$LTM" | tr -d ' ')
OUT=$(env OUTPUT_DIR="$OUTF" bash "$NEWSRC/main.sh" 2>&1); RC=$?
expect_rc F1 0
sleep 1
NEWLINES=$(tail -n "+$((LTM0 + 1))" "$LTM")
printf '%s' "$NEWLINES" | grep -q "notice RPZLocal\[[0-9]*\]: RPZ SOA not changed, skip update" \
    && ok "F1: ltm 有 notice 事件（F5 原生格式 + RPZLocal tag）" || bad "F1: ltm 缺 notice 事件"
printf '%s' "$NEWLINES" | grep "RPZLocal" | grep -qE "INFO:|ERROR:| $(uname -n) (INFO|ERROR)" \
    && bad "F1: 訊息殘留自帶前綴（重複時間戳/主機名）" || ok "F1: 無重複前綴"

echo "== F2: 失敗路徑的 err 事件 =="
LTM0=$(wc -l < "$LTM" | tr -d ' ')
OUT=$(env OUTPUT_DIR="$OUTF" DNSXDUMP_CMD=/bin/false bash "$NEWSRC/main.sh" --force 2>&1); RC=$?
expect_rc F2 1
sleep 1
NEWLINES=$(tail -n "+$((LTM0 + 1))" "$LTM")
printf '%s' "$NEWLINES" | grep -q "err RPZLocal\[[0-9]*\]: dnsxdump execution failed" \
    && ok "F2: extract 的 err 事件進 ltm" || bad "F2: 缺 extract err 事件"
printf '%s' "$NEWLINES" | grep -q "err RPZLocal\[[0-9]*\]: RPZ extraction failed" \
    && ok "F2: main 的 err 事件進 ltm" || bad "F2: 缺 main err 事件"

echo "== F4: parsing 失敗事件（審核第 6.4 節永久保護）=="
# NEWSRC 刻意不含 parse_rpz.sh: 步驟 2 成功後，步驟 3 必失敗
LTM0=$(wc -l < "$LTM" | tr -d ' ')
OUT=$(env OUTPUT_DIR="$OUTF" bash "$NEWSRC/main.sh" --force 2>&1); RC=$?
expect_rc F4 1
sleep 1
NEWLINES=$(tail -n "+$((LTM0 + 1))" "$LTM")
printf '%s' "$NEWLINES" | grep -q "err RPZLocal\[[0-9]*\]: RPZ parsing failed" \
    && ok "F4: parsing failed 的 err 事件進 ltm" || bad "F4: 缺 parsing failed 事件"
echo "== F5: logger 失敗不影響主流程（審核第 6.4 節永久保護）=="
FAKEBIN="$R/bin"; mkdir -p "$FAKEBIN"
printf '#!/bin/bash\nexit 42\n' > "$FAKEBIN/logger"; chmod +x "$FAKEBIN/logger"
OUT=$(env OUTPUT_DIR="$OUTF" PATH="$FAKEBIN:$PATH" bash "$NEWSRC/main.sh" 2>&1); RC=$?
expect_rc F5 0
printf '%s' "$OUT" | grep -q "處理完成\|SOA Serial 未變更" && ok "F5: 主流程正常完成" || bad "F5: 主流程異常"

echo "== F3: 事件不再以檔案直寫產生 =="
n=$(grep -Fc '>> "$LOG_FILE"' "$NEWSRC/main.sh" "$NEWSRC/extract_rpz.sh" "$NEWSRC/update_datagroup.sh" | awk -F: '{s+=$2} END{print s}')
[ "$n" = 0 ] && ok "F3: 三檔皆無 ltm 直寫" || bad "F3: 仍有 ${n} 處直寫"

echo
echo "=============================================================="
printf ' PASS=%s  FAIL=%s\n' "$PASS" "$FAIL"
echo "=============================================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
