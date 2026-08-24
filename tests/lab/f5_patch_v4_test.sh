#!/bin/bash
# =============================================================================
# f5_patch_v4_test.sh — v4 patch 工具邏輯的 LAB 迴歸測試
# 對應審核 CODE_REVIEW_V4_STE100_20260822.md 第 7 節的 12 個案例，外加
# V4-02 的修復路徑案例。
#
# 安全性:
#   - 全部操作在 /var/tmp/rpz_v4_test fixture 目錄，絕不寫 /config
#   - 用 sed 產生 patch 副本，只改 SCRIPTS_DIR 與 BACKUP_ROOT 兩行
#   - production patch 檔案本身不修改
#   - 需要 /var/tmp/origsrc/scripts（原版三檔）
#
# 用法: bash f5_patch_v4_test.sh [patch路徑]
# =============================================================================
set -u

PATCH_SRC="${1:-/var/tmp/rpz_patch_sigpipe_v4.sh}"
ORIGSRC=/var/tmp/origsrc/scripts
R=/var/tmp/rpz_v4_test
TGT="$R/scripts"; BK="$R/backups"; NEWSRC="$R/newsrc"; PT="$R/patch_test.sh"

OU=3cab6cbca952f3780350e9882e5f7c11
OP=bbe45c6f79b56922388d4af7aa6e7583
OG=35547d33ce109945d1ca17e8eb241e0a
NU=b8294149dc978305e19bcd83fcb650e6
NP=cefa71b6623632dd51c60a51cdf72196
NG=9599755a54db53652c070cd70ae92652

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }
md5f(){ md5sum "$1" 2>/dev/null | awk '{print $1}'; }

cleanup(){
    local f
    for f in "$TGT"/*.sh; do chattr -i "$f" 2>/dev/null; done
    rm -rf "$R"
}
trap cleanup EXIT

# ---------- 前置 ----------
[ -s "$PATCH_SRC" ] || { echo "缺 patch: $PATCH_SRC"; exit 2; }
for f in utils.sh parse_rpz.sh generate_datagroup.sh; do
    [ -f "$ORIGSRC/$f" ] || { echo "缺 $ORIGSRC/$f"; exit 2; }
done
[ "$(md5f "$ORIGSRC/utils.sh")" = "$OU" ] || { echo "origsrc utils.sh md5 不符"; exit 2; }
[ "$(md5f "$ORIGSRC/parse_rpz.sh")" = "$OP" ] || { echo "origsrc parse_rpz.sh md5 不符"; exit 2; }
[ "$(md5f "$ORIGSRC/generate_datagroup.sh")" = "$OG" ] || { echo "origsrc generate_datagroup.sh md5 不符"; exit 2; }

rm -rf "$R"; mkdir -p "$TGT" "$BK" "$NEWSRC"

sed -e 's|^SCRIPTS_DIR="/config/snmp/RPZ_Local_Processor/scripts"$|SCRIPTS_DIR="'"$TGT"'"|' \
    -e 's|^BACKUP_ROOT="/var/tmp"$|BACKUP_ROOT="'"$BK"'"|' \
    "$PATCH_SRC" > "$PT"
grep -q "^SCRIPTS_DIR=\"$TGT\"" "$PT" || { echo "sed SCRIPTS_DIR 失敗"; exit 2; }
grep -q "^BACKUP_ROOT=\"$BK\"" "$PT" || { echo "sed BACKUP_ROOT 失敗"; exit 2; }
bash -n "$PT" || { echo "patch 副本語法錯誤"; exit 2; }

i=0
for f in utils.sh parse_rpz.sh generate_datagroup.sh; do
    i=$((i+1))
    awk -v want="$i" '
        /^cat <<'\''__RPZ_EMBED__'\''$/ { n++; inb=1; next }
        /^__RPZ_EMBED__$/               { inb=0; next }
        inb && n == want                { print }
    ' "$PATCH_SRC" > "$NEWSRC/$f"
done
[ "$(md5f "$NEWSRC/utils.sh")" = "$NU" ] || { echo "抽出 utils.sh md5 不符"; exit 2; }
[ "$(md5f "$NEWSRC/parse_rpz.sh")" = "$NP" ] || { echo "抽出 parse_rpz.sh md5 不符"; exit 2; }
[ "$(md5f "$NEWSRC/generate_datagroup.sh")" = "$NG" ] || { echo "抽出 generate_datagroup.sh md5 不符"; exit 2; }

echo "fixture 就緒: $R"
echo

# ---------- 工具 ----------
reset_orig(){
    rm -rf "$TGT" "$BK"; mkdir -p "$TGT" "$BK"
    local f
    for f in utils.sh parse_rpz.sh generate_datagroup.sh; do
        cp -p "$ORIGSRC/$f" "$TGT/$f"
    done
}
set_file(){ # set_file <檔名> <o|n>
    local src="$ORIGSRC"
    [ "$2" = n ] && src="$NEWSRC"
    cat "$src/$1" > "$TGT/$1"
}
want_md5(){ # want_md5 <檔名> <o|n>
    case "$1:$2" in
        utils.sh:o) echo "$OU";;              utils.sh:n) echo "$NU";;
        parse_rpz.sh:o) echo "$OP";;          parse_rpz.sh:n) echo "$NP";;
        generate_datagroup.sh:o) echo "$OG";; generate_datagroup.sh:n) echo "$NG";;
    esac
}
assert_state(){ # assert_state <label> <u> <p> <g>
    local okk=1
    [ "$(md5f "$TGT/utils.sh")" = "$(want_md5 utils.sh "$2")" ] || okk=0
    [ "$(md5f "$TGT/parse_rpz.sh")" = "$(want_md5 parse_rpz.sh "$3")" ] || okk=0
    [ "$(md5f "$TGT/generate_datagroup.sh")" = "$(want_md5 generate_datagroup.sh "$4")" ] || okk=0
    [ "$okk" = 1 ] && ok "$1: 狀態=$2$3$4" || bad "$1: 狀態應為 $2$3$4"
}
no_tmp(){
    local n
    n=$(find "$TGT" -maxdepth 1 -name ".*" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" = 0 ] && ok "$1: 無殘留暫存檔" || bad "$1: 有 ${n} 個殘留暫存檔"
}
backup_count(){ local n=0 d; for d in "$BK"/rpz_patch_backup_*; do [ -d "$d" ] && n=$((n+1)); done; echo "$n"; }
newest_backup(){ local d last=""; for d in "$BK"/rpz_patch_backup_*; do [ -d "$d" ] || continue; if [ -z "$last" ] || [ "$d" -nt "$last" ]; then last="$d"; fi; done; echo "$last"; }
wait_quiet(){
    local i=0
    while pgrep -f "RPZ_Local_Processor/scripts/[a-z_]+[.]sh|rpz_wrapper[.]sh" >/dev/null 2>&1; do
        i=$((i+1)); [ "$i" -gt 90 ] && { echo "等待 RPZ 靜止逾時"; return 1; }
        sleep 2
    done
    return 0
}
run_pt(){ # run_pt <子指令> [參數]  -> 設定 OUT / RC
    case "$1" in apply|rollback) wait_quiet; sleep 1 ;; esac
    OUT=$(bash "$PT" "$@" 2>&1); RC=$?
    if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q "RPZ 處理程序執行中"; then
        wait_quiet; sleep 1
        OUT=$(bash "$PT" "$@" 2>&1); RC=$?
    fi
}
expect_rc(){ [ "$RC" = "$2" ] && ok "$1: RC=$RC" || { bad "$1: RC=$RC 應為 $2"; printf '%s\n' "$OUT" | tail -4 | sed 's/^/      /'; } }
expect_out(){ printf '%s' "$OUT" | grep -q "$2" && ok "$1: 訊息含「$2」" || bad "$1: 訊息缺「$2」"; }

# ---------- 案例 1: 原版 check ----------
echo "== 案例 1: 原版 check =="
reset_orig
run_pt check;  expect_rc "1-check" 0; expect_out "1-check" "全部是原版"

# ---------- 案例 2: 正常 apply ----------
echo "== 案例 2: 正常 apply =="
run_pt apply;  expect_rc "2-apply" 0
assert_state "2-apply" n n n
[ "$(backup_count)" = 1 ] && ok "2-apply: 備份目錄 1 個" || bad "2-apply: 備份目錄 $(backup_count) 個"
B1=$(newest_backup)
( cd "$B1" && md5sum -c md5sums.txt >/dev/null 2>&1 ) && ok "2-apply: 備份 md5sums 驗證通過" || bad "2-apply: 備份 md5sums 驗證失敗"
[ "$(md5f "$B1/utils.sh")" = "$OU" ] && ok "2-apply: 備份為純原版" || bad "2-apply: 備份非原版"
no_tmp "2-apply"

# ---------- 案例 3: 重複 apply ----------
echo "== 案例 3: 重複 apply =="
run_pt apply;  expect_rc "3-repeat" 0; expect_out "3-repeat" "無需動作"
[ "$(backup_count)" = 1 ] && ok "3-repeat: 未新增備份" || bad "3-repeat: 備份數變 $(backup_count)"

# ---------- 案例 4+5: 各檔 apply 失敗與續跑 ----------
echo "== 案例 4+5: 各檔 apply 失敗（chattr +i）與續跑 =="
for tf in utils.sh:o,o,o parse_rpz.sh:n,o,o generate_datagroup.sh:n,n,o; do
    f="${tf%%:*}"; st="${tf#*:}"; u="${st%%,*}"; rest="${st#*,}"; pp="${rest%%,*}"; g="${rest#*,}"
    reset_orig
    chattr +i "$TGT/$f" || { bad "4-${f}: chattr +i 失敗"; continue; }
    run_pt apply; expect_rc "4-lock-${f}" 1
    assert_state "4-lock-${f}" "$u" "$pp" "$g"
    no_tmp "4-lock-${f}"
    chattr -i "$TGT/$f"
    run_pt apply; expect_rc "5-resume-${f}" 0
    assert_state "5-resume-${f}" n n n
done

# ---------- 案例 6: 正常 rollback ----------
echo "== 案例 6: 正常 rollback =="
reset_orig
run_pt apply; B1=$(newest_backup)
run_pt rollback "$B1"; expect_rc "6-rollback" 0
assert_state "6-rollback" o o o

# ---------- 案例 7+8: 各檔 rollback 失敗與續跑（還原順序 g -> p -> u）----------
echo "== 案例 7+8: 各檔 rollback 失敗（chattr +i）與續跑 =="
for tf in generate_datagroup.sh:n,n,n parse_rpz.sh:n,n,o utils.sh:n,o,o; do
    f="${tf%%:*}"; st="${tf#*:}"; u="${st%%,*}"; rest="${st#*,}"; pp="${rest%%,*}"; g="${rest#*,}"
    reset_orig
    run_pt apply; B1=$(newest_backup)
    chattr +i "$TGT/$f" || { bad "7-${f}: chattr +i 失敗"; continue; }
    run_pt rollback "$B1"; expect_rc "7-lock-${f}" 1
    assert_state "7-lock-${f}" "$u" "$pp" "$g"
    no_tmp "7-lock-${f}"
    chattr -i "$TGT/$f"
    run_pt rollback "$B1"; expect_rc "8-resume-${f}" 0
    assert_state "8-resume-${f}" o o o
done

# ---------- 案例 9: 全部八種組合的 check ----------
echo "== 案例 9: 八種 o/n 組合的 check（V4-02 依賴規則）=="
for u in o n; do for pp in o n; do for g in o n; do
    reset_orig
    set_file utils.sh "$u"; set_file parse_rpz.sh "$pp"; set_file generate_datagroup.sh "$g"
    want=0
    if [ "$u" = o ] && { [ "$pp" = n ] || [ "$g" = n ]; }; then want=2; fi
    run_pt check
    [ "$RC" = "$want" ] && ok "9-${u}${pp}${g}: RC=$RC" || bad "9-${u}${pp}${g}: RC=$RC 應為 $want"
    if [ "$want" = 2 ]; then expect_out "9-${u}${pp}${g}" "版本組合不可運作"; fi
done; done; done

# ---------- 案例 10: 手工純原版備份的 rollback ----------
echo "== 案例 10: 純原版備份驗證 =="
reset_orig
run_pt apply
BM="$BK/rpz_patch_backup_manual_pure"
mkdir -p "$BM"
for f in utils.sh parse_rpz.sh generate_datagroup.sh; do cp -p "$ORIGSRC/$f" "$BM/$f"; done
( cd "$BM" && md5sum utils.sh parse_rpz.sh generate_datagroup.sh > md5sums.txt )
run_pt rollback "$BM"; expect_rc "10-pure" 0
assert_state "10-pure" o o o

# ---------- 案例 11: 混合備份必須被拒絕，且拒絕發生在改檔之前 ----------
echo "== 案例 11: 混合備份拒絕（V4-02）=="
reset_orig
run_pt apply
BX="$BK/rpz_patch_backup_manual_mixed"
mkdir -p "$BX"
cp -p "$NEWSRC/utils.sh" "$BX/utils.sh"
cp -p "$ORIGSRC/parse_rpz.sh" "$BX/parse_rpz.sh"
cp -p "$ORIGSRC/generate_datagroup.sh" "$BX/generate_datagroup.sh"
( cd "$BX" && md5sum utils.sh parse_rpz.sh generate_datagroup.sh > md5sums.txt )
run_pt rollback "$BX"; expect_rc "11-mixed" 2; expect_out "11-mixed" "不是純原版"
assert_state "11-mixed" n n n

# ---------- 案例 13: 不可運作組合的 apply 修復路徑 ----------
echo "== 案例 13: 不可運作組合（舊 utils + 新 consumer）的修復 =="
reset_orig
set_file parse_rpz.sh n; set_file generate_datagroup.sh n
run_pt check; expect_rc "13-check" 2; expect_out "13-check" "版本組合不可運作"
run_pt apply; expect_rc "13-repair" 0; expect_out "13-repair" "警告"
assert_state "13-repair" n n n
BM2=$(newest_backup)
run_pt rollback "$BM2"; expect_rc "13-mixed-backup" 2

# ---------- 案例 14: 目前 target 版本不明 + 純原版備份，必須拒絕（R2-V4-02）----------
echo "== 案例 14: 目前 target 版本不明時 rollback 必須拒絕 =="
reset_orig
run_pt apply
BP="$BK/rpz_patch_backup_manual_pure14"
mkdir -p "$BP"
for f in utils.sh parse_rpz.sh generate_datagroup.sh; do cp -p "$ORIGSRC/$f" "$BP/$f"; done
( cd "$BP" && md5sum utils.sh parse_rpz.sh generate_datagroup.sh > md5sums.txt )
echo "# local-change-for-test" >> "$TGT/utils.sh"
U14=$(md5f "$TGT/utils.sh")
run_pt rollback "$BP"; expect_rc "14-unknown" 2; expect_out "14-unknown" "版本不明或缺少"
[ "$(md5f "$TGT/utils.sh")" = "$U14" ] && ok "14-unknown: utils.sh 未被覆寫" || bad "14-unknown: utils.sh 被改動"
[ "$(md5f "$TGT/parse_rpz.sh")" = "$NP" ] && ok "14-unknown: parse_rpz.sh 未變" || bad "14-unknown: parse_rpz.sh 被改動"
[ "$(md5f "$TGT/generate_datagroup.sh")" = "$NG" ] && ok "14-unknown: generate_datagroup.sh 未變" || bad "14-unknown: generate_datagroup.sh 被改動"

# ---------- 案例 15: 目前 target 缺檔 + 純原版備份，必須拒絕（R2-V4-02）----------
echo "== 案例 15: 目前 target 缺檔時 rollback 必須拒絕 =="
reset_orig
run_pt apply
BP="$BK/rpz_patch_backup_manual_pure15"
mkdir -p "$BP"
for f in utils.sh parse_rpz.sh generate_datagroup.sh; do cp -p "$ORIGSRC/$f" "$BP/$f"; done
( cd "$BP" && md5sum utils.sh parse_rpz.sh generate_datagroup.sh > md5sums.txt )
rm -f "$TGT/parse_rpz.sh"
run_pt rollback "$BP"; expect_rc "15-missing" 2; expect_out "15-missing" "版本不明或缺少"
[ "$(md5f "$TGT/utils.sh")" = "$NU" ] && ok "15-missing: utils.sh 未變" || bad "15-missing: utils.sh 被改動"
[ "$(md5f "$TGT/generate_datagroup.sh")" = "$NG" ] && ok "15-missing: generate_datagroup.sh 未變" || bad "15-missing: generate_datagroup.sh 被改動"
[ ! -f "$TGT/parse_rpz.sh" ] && ok "15-missing: 缺檔狀態未被部分還原" || bad "15-missing: 出現部分還原"

# ---------- 案例 16: 依賴違規組合 + 純原版備份，rollback 必須可修復（R2-V4-02）----------
echo "== 案例 16: 依賴違規組合（onn）的 rollback 修復 =="
reset_orig
set_file parse_rpz.sh n; set_file generate_datagroup.sh n
BP="$BK/rpz_patch_backup_manual_pure16"
mkdir -p "$BP"
for f in utils.sh parse_rpz.sh generate_datagroup.sh; do cp -p "$ORIGSRC/$f" "$BP/$f"; done
( cd "$BP" && md5sum utils.sh parse_rpz.sh generate_datagroup.sh > md5sums.txt )
run_pt rollback "$BP"; expect_rc "16-depfix" 0
assert_state "16-depfix" o o o

# ---------- 案例 12: 最終暫存檔掃描 ----------
echo "== 案例 12: 暫存檔清理 =="
no_tmp "12-final"

echo
echo "=============================================================="
printf ' PASS=%s  FAIL=%s\n' "$PASS" "$FAIL"
echo "=============================================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
