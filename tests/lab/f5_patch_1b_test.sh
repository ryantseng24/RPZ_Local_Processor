#!/bin/bash
# =============================================================================
# f5_patch_1b_test.sh — Phase 1B patch 的 LAB 迴歸測試
# 涵蓋: patch 機制（M1-M10）、cleanup 功能（F1-F12）、trap 路徑（T1-T4）。
# 對應設計文件 docs/PHASE1B_DESIGN_20260823.md 第 6 節。
#
# 安全性:
#   - 全部操作在 /var/tmp/rpz_1b_test fixture，絕不寫 /config
#   - patch 以 sed 副本改指 fixture（只改 SCRIPTS_DIR 與 BACKUP_ROOT 兩行）
#   - 需要 /var/tmp/origsrc/scripts（原版 main.sh 與 utils.sh）
#
# 用法: bash f5_patch_1b_test.sh [patch路徑]
# =============================================================================
set -u

PATCH_SRC="${1:-/var/tmp/rpz_patch_phase1b_v1.sh}"
ORIGSRC=/var/tmp/origsrc/scripts
R=/var/tmp/rpz_1b_test
TGT="$R/scripts"; BK="$R/backups"; NEWSRC="$R/newsrc"; OUTF="$R/out"; PT="$R/patch_test.sh"

OM=0041c1d74e5b8514dea506608607b8c6
NM=d1e1f688d939a5a5e87282605d0e3eed
OU=3cab6cbca952f3780350e9882e5f7c11

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }
md5f(){ md5sum "$1" 2>/dev/null | awk '{print $1}'; }

cleanup_all(){
    local f
    for f in "$TGT"/*.sh "$OUTF"/raw/* "$OUTF"/parsed/*; do chattr -i "$f" 2>/dev/null; done
    rm -rf "$R"
}
trap cleanup_all EXIT

# ---------- 前置 ----------
[ -s "$PATCH_SRC" ] || { echo "缺 patch: $PATCH_SRC"; exit 2; }
[ -f "$ORIGSRC/main.sh" ] || { echo "缺 $ORIGSRC/main.sh"; exit 2; }
[ -f "$ORIGSRC/utils.sh" ] || { echo "缺 $ORIGSRC/utils.sh"; exit 2; }
[ "$(md5f "$ORIGSRC/main.sh")" = "$OM" ] || { echo "origsrc main.sh md5 不符"; exit 2; }
[ "$(md5f "$ORIGSRC/utils.sh")" = "$OU" ] || { echo "origsrc utils.sh md5 不符"; exit 2; }

rm -rf "$R"; mkdir -p "$TGT" "$BK" "$NEWSRC" "$OUTF"

sed -e 's|^SCRIPTS_DIR="/config/snmp/RPZ_Local_Processor/scripts"$|SCRIPTS_DIR="'"$TGT"'"|' \
    -e 's|^BACKUP_ROOT="/var/tmp"$|BACKUP_ROOT="'"$BK"'"|' \
    "$PATCH_SRC" > "$PT"
grep -q "^SCRIPTS_DIR=\"$TGT\"" "$PT" || { echo "sed SCRIPTS_DIR 失敗"; exit 2; }
grep -q "^BACKUP_ROOT=\"$BK\"" "$PT" || { echo "sed BACKUP_ROOT 失敗"; exit 2; }
bash -n "$PT" || { echo "patch 副本語法錯誤"; exit 2; }

awk '
    /^cat <<'\''__RPZ_EMBED__'\''$/ { n++; inb=1; next }
    /^__RPZ_EMBED__$/               { inb=0; next }
    inb && n == 1                   { print }
' "$PATCH_SRC" > "$NEWSRC/main.sh"
[ "$(md5f "$NEWSRC/main.sh")" = "$NM" ] || { echo "抽出 main.sh md5 不符"; exit 2; }
cp -p "$ORIGSRC/utils.sh" "$NEWSRC/utils.sh"

echo "fixture 就緒: $R"
echo

# ---------- 工具 ----------
reset_tgt(){
    local f
    for f in "$TGT"/*.sh; do chattr -i "$f" 2>/dev/null; done
    rm -rf "$TGT" "$BK"; mkdir -p "$TGT" "$BK"
    cp -p "$ORIGSRC/main.sh" "$TGT/main.sh"
}
wait_quiet(){
    local i=0
    while pgrep -f "RPZ_Local_Processor/scripts/[a-z_]+[.]sh|rpz_wrapper[.]sh" >/dev/null 2>&1; do
        i=$((i+1)); [ "$i" -gt 90 ] && { echo "等待 RPZ 靜止逾時"; return 1; }
        sleep 2
    done
    return 0
}
run_pt(){
    case "$1" in apply|rollback) wait_quiet; sleep 1 ;; esac
    OUT=$(bash "$PT" "$@" 2>&1); RC=$?
    if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q "RPZ 處理程序執行中"; then
        wait_quiet; sleep 1
        OUT=$(bash "$PT" "$@" 2>&1); RC=$?
    fi
}
expect_rc(){ [ "$RC" = "$2" ] && ok "$1: RC=$RC" || { bad "$1: RC=$RC 應為 $2"; printf '%s\n' "$OUT" | tail -3 | sed 's/^/      /'; } }
expect_out(){ printf '%s' "$OUT" | grep -q "$2" && ok "$1: 訊息含「$2」" || bad "$1: 訊息缺「$2」"; }
no_tmp(){
    local n
    n=$(find "$TGT" -maxdepth 1 -name ".*" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" = 0 ] && ok "$1: 無殘留暫存檔" || bad "$1: 有 ${n} 個殘留暫存檔"
}
backup_count(){ local n=0 d; for d in "$BK"/rpz_patch1b_backup_*; do [ -d "$d" ] && n=$((n+1)); done; echo "$n"; }
newest_backup(){ local d last=""; for d in "$BK"/rpz_patch1b_backup_*; do [ -d "$d" ] || continue; if [ -z "$last" ] || [ "$d" -nt "$last" ]; then last="$d"; fi; done; echo "$last"; }
craft_pure(){ mkdir -p "$1"; cp -p "$ORIGSRC/main.sh" "$1/main.sh"; ( cd "$1" && md5sum main.sh > md5sums.txt ); }

# ---------- M1: 原版 check ----------
echo "== M1: 原版 check =="
reset_tgt
run_pt check; expect_rc M1 0; expect_out M1 "原版 v1.2，可以套用"

# ---------- M2: 正常 apply ----------
echo "== M2: 正常 apply =="
run_pt apply; expect_rc M2 0
[ "$(md5f "$TGT/main.sh")" = "$NM" ] && ok "M2: main.sh 已修正" || bad "M2: main.sh md5 錯"
[ "$(backup_count)" = 1 ] && ok "M2: 備份 1 個" || bad "M2: 備份 $(backup_count) 個"
B1=$(newest_backup)
[ "$(md5f "$B1/main.sh")" = "$OM" ] && ok "M2: 備份為純原版" || bad "M2: 備份非原版"
no_tmp M2

# ---------- M3: 重複 apply ----------
echo "== M3: 重複 apply =="
run_pt apply; expect_rc M3 0; expect_out M3 "無需動作"
[ "$(backup_count)" = 1 ] && ok "M3: 未新增備份" || bad "M3: 備份數變 $(backup_count)"

# ---------- M4: apply 失敗注入與續跑 ----------
echo "== M4: apply 失敗（chattr +i）與續跑 =="
reset_tgt
chattr +i "$TGT/main.sh" && ok "M4: chattr +i" || bad "M4: chattr +i 失敗"
run_pt apply; expect_rc M4-lock 1
[ "$(md5f "$TGT/main.sh")" = "$OM" ] && ok "M4-lock: 仍為原版" || bad "M4-lock: 狀態錯"
no_tmp M4-lock
chattr -i "$TGT/main.sh"
run_pt apply; expect_rc M4-resume 0
[ "$(md5f "$TGT/main.sh")" = "$NM" ] && ok "M4-resume: 已修正" || bad "M4-resume: 狀態錯"

# ---------- M5: 正常 rollback ----------
echo "== M5: 正常 rollback =="
reset_tgt
run_pt apply; B1=$(newest_backup)
run_pt rollback "$B1"; expect_rc M5 0
[ "$(md5f "$TGT/main.sh")" = "$OM" ] && ok "M5: 已還原原版" || bad "M5: 狀態錯"

# ---------- M6: rollback 失敗注入與續跑 ----------
echo "== M6: rollback 失敗（chattr +i）與續跑 =="
reset_tgt
run_pt apply; B1=$(newest_backup)
chattr +i "$TGT/main.sh"
run_pt rollback "$B1"; expect_rc M6-lock 1
[ "$(md5f "$TGT/main.sh")" = "$NM" ] && ok "M6-lock: 仍為修正版" || bad "M6-lock: 狀態錯"
no_tmp M6-lock
chattr -i "$TGT/main.sh"
run_pt rollback "$B1"; expect_rc M6-resume 0
[ "$(md5f "$TGT/main.sh")" = "$OM" ] && ok "M6-resume: 已還原" || bad "M6-resume: 狀態錯"

# ---------- M7: 版本不明（check / apply / rollback 全拒絕）----------
echo "== M7: 版本不明 =="
reset_tgt
run_pt apply
echo "# local-change" >> "$TGT/main.sh"
U7=$(md5f "$TGT/main.sh")
run_pt check; expect_rc M7-check 2
run_pt apply; expect_rc M7-apply 2
BP="$BK/manual_pure_m7"; craft_pure "$BP"
run_pt rollback "$BP"; expect_rc M7-rollback 2; expect_out M7-rollback "版本不明或缺少"
[ "$(md5f "$TGT/main.sh")" = "$U7" ] && ok "M7: 檔案未被覆寫" || bad "M7: 檔案被改動"

# ---------- M8: 缺檔 ----------
echo "== M8: 目前檔案缺失 =="
reset_tgt
run_pt apply
BP="$BK/manual_pure_m8"; craft_pure "$BP"
rm -f "$TGT/main.sh"
run_pt rollback "$BP"; expect_rc M8 2; expect_out M8 "版本不明或缺少"

# ---------- M9: 混合備份拒絕 ----------
echo "== M9: 非純原版備份拒絕 =="
reset_tgt
run_pt apply
BX="$BK/manual_mixed_m9"; mkdir -p "$BX"
cp -p "$NEWSRC/main.sh" "$BX/main.sh"; ( cd "$BX" && md5sum main.sh > md5sums.txt )
run_pt rollback "$BX"; expect_rc M9 2; expect_out M9 "不是純原版"
[ "$(md5f "$TGT/main.sh")" = "$NM" ] && ok "M9: 狀態不變" || bad "M9: 狀態被改"

# ---------- M10: rollback 無參數 ----------
echo "== M10: rollback 無參數 =="
run_pt rollback; expect_rc M10 2; expect_out M10 "用法"

# =============================================================================
# 功能測試: cleanup（source 新版 main.sh，OUTPUT_DIR 指 fixture）
# =============================================================================
mk_out(){ rm -rf "$OUTF"; mkdir -p "$OUTF/raw" "$OUTF/parsed" "$OUTF/final"; }
seed(){ # seed <dir> <prefix> <suffix> <count> [old]
    local dir="$1" pre="$2" suf="$3" cnt="$4" old="${5:-}" i name
    for (( i=1; i<=cnt; i++ )); do
        name=$(printf '%s_2026%04d_%06d%s' "$pre" "$i" "$i" "$suf")
        : > "$dir/$name"
        [ -n "$old" ] && touch -t 202607010000 "$dir/$name"
    done
}
cnt(){ local n=0 f; for f in $1/$2; do [ -f "$f" ] && n=$((n+1)); done; echo "$n"; }
run_cleanup(){ # run_cleanup [額外環境變數...]
    OUT=$(env OUTPUT_DIR="$OUTF" NS="$NEWSRC" "$@" bash -c 'set --; source "$NS/main.sh"; cleanup' 2>&1); RC=$?
}

echo "== F1: 數量上限，保留最新 24（raw 100 + 3 家族各 100）=="
mk_out
seed "$OUTF/raw" dnsxdump .out 100
for z in rpztw phishtw rpzip; do seed "$OUTF/parsed" "$z" .txt 100; done
seed "$OUTF/final" keepme .txt 3 old
run_cleanup; expect_rc F1 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "F1: raw=24" || bad "F1: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"
for z in rpztw phishtw rpzip; do
    [ "$(cnt "$OUTF/parsed" "${z}_*.txt")" = 24 ] && ok "F1: ${z}=24" || bad "F1: ${z}=$(cnt "$OUTF/parsed" "${z}_*.txt")"
done
[ -f "$OUTF/raw/$(printf 'dnsxdump_2026%04d_%06d.out' 100 100)" ] && ok "F1: 最新檔保留" || bad "F1: 最新檔被刪"
[ ! -f "$OUTF/raw/$(printf 'dnsxdump_2026%04d_%06d.out' 1 1)" ] && ok "F1: 最舊檔已刪" || bad "F1: 最舊檔還在"
[ "$(cnt "$OUTF/final" '*')" = 3 ] && ok "F1: final/ 3 個全保留" || bad "F1: final/ 被動到"

echo "== F2: 天數上限（檔數<24 但 mtime 30 天前）=="
mk_out
seed "$OUTF/raw" dnsxdump .out 10 old
run_cleanup; expect_rc F2 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 0 ] && ok "F2: 舊檔全刪" || bad "F2: 還剩 $(cnt "$OUTF/raw" 'dnsxdump_*.out')"

echo "== F3: 無事可做時零輸出 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 10
run_cleanup; expect_rc F3 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 10 ] && ok "F3: 全保留" || bad "F3: 被誤刪"
[ -z "$OUT" ] && ok "F3: 零輸出" || bad "F3: 有輸出: $(printf '%s' "$OUT" | head -1)"

echo "== F5: 非本命名格式檔案 =="
mk_out
seed "$OUTF/parsed" rpztw .txt 30
: > "$OUTF/parsed/notes.txt"
: > "$OUTF/parsed/notes_old.txt"; touch -t 202607010000 "$OUTF/parsed/notes_old.txt"
run_cleanup; expect_rc F5 0
[ -f "$OUTF/parsed/notes.txt" ] && ok "F5: 新的外來檔保留（數量上限不動它）" || bad "F5: 新外來檔被刪"
[ ! -f "$OUTF/parsed/notes_old.txt" ] && ok "F5: 舊外來檔由天數上限刪除" || bad "F5: 舊外來檔還在"
[ "$(cnt "$OUTF/parsed" 'rpztw_*.txt')" = 24 ] && ok "F5: rpztw=24" || bad "F5: rpztw=$(cnt "$OUTF/parsed" 'rpztw_*.txt')"

echo "== F6: RPZ_KEEP_COUNT 非法值回退 24 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 30
run_cleanup RPZ_KEEP_COUNT=abc; expect_rc F6 0; expect_out F6 "非法或超出範圍"
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "F6: 用預設 24" || bad "F6: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"

echo "== F6b: RPZ_KEEP_COUNT=7 生效 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 30
run_cleanup RPZ_KEEP_COUNT=7; expect_rc F6b 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 7 ] && ok "F6b: 保留 7" || bad "F6b: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"

echo "== F7: CLEANUP_TEMP=false 全保留 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 30 old
run_cleanup CLEANUP_TEMP=false; expect_rc F7 0; expect_out F7 "跳過"
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 30 ] && ok "F7: 全保留" || bad "F7: 被刪"

echo "== F8: KEEP 邊界值（P1B-02）=="
for v in 0 100000 999999999999999999999999999999999999; do
    mk_out
    seed "$OUTF/raw" dnsxdump .out 30
    run_cleanup RPZ_KEEP_COUNT="$v"; expect_rc "F8-${v:0:8}" 0; expect_out "F8-${v:0:8}" "非法或超出範圍"
    [ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "F8-${v:0:8}: 回退 24" || bad "F8-${v:0:8}: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"
done
mk_out
seed "$OUTF/raw" dnsxdump .out 30
run_cleanup RPZ_KEEP_COUNT=99999; expect_rc "F8-max" 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 30 ] && ok "F8-max: 99999 有效，全保留" || bad "F8-max: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"
mk_out
seed "$OUTF/raw" dnsxdump .out 30
run_cleanup RPZ_KEEP_COUNT=24; expect_rc "F8-24" 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "F8-24: 明確 24 有效" || bad "F8-24: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"

echo "== F9: 不安全前綴不得跨家族刪除（P1B-03）=="
mk_out
seed "$OUTF/parsed" alpha .txt 30
seed "$OUTF/parsed" beta .txt 30
: > "$OUTF/parsed/*_20260101_000001.txt"
: > "$OUTF/parsed/?_20260101_000002.txt"
: > "$OUTF/parsed/[_20260101_000003.txt"
seed "$OUTF/final" keepme .txt 1 old
run_cleanup; expect_rc F9 0; expect_out F9 "不安全的家族前綴"
[ "$(cnt "$OUTF/parsed" 'alpha_*.txt')" = 24 ] && ok "F9: alpha=24（未被跨刪）" || bad "F9: alpha=$(cnt "$OUTF/parsed" 'alpha_*.txt')"
[ "$(cnt "$OUTF/parsed" 'beta_*.txt')" = 24 ] && ok "F9: beta=24" || bad "F9: beta=$(cnt "$OUTF/parsed" 'beta_*.txt')"
[ -f "$OUTF/parsed/*_20260101_000001.txt" ] && ok "F9: * 前綴檔保留" || bad "F9: * 前綴檔被刪"
[ -f "$OUTF/parsed/?_20260101_000002.txt" ] && ok "F9: ? 前綴檔保留" || bad "F9: ? 前綴檔被刪"
[ -f "$OUTF/parsed/[_20260101_000003.txt" ] && ok "F9: [ 前綴檔保留" || bad "F9: [ 前綴檔被刪"
[ "$(cnt "$OUTF/final" '*')" = 1 ] && ok "F9: final/ 不動" || bad "F9: final/ 被動到"

echo "== F10: 數量上限刪除失敗必須據實回報（P1B-04）=="
mk_out
seed "$OUTF/raw" dnsxdump .out 30
LOCK="$OUTF/raw/$(printf 'dnsxdump_2026%04d_%06d.out' 3 3)"
chattr +i "$LOCK" || bad "F10: chattr +i 失敗"
run_cleanup; expect_rc F10 0; expect_out F10 "實際刪除"; expect_out F10 "失敗 1 個"
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 25 ] && ok "F10: 實際 25 個（24+鎖住的 1 個）" || bad "F10: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"
chattr -i "$LOCK"
run_cleanup; expect_rc F10b 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "F10b: 解鎖後下一輪到 24" || bad "F10b: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"

echo "== F11: 天數上限刪除失敗必須 WARN（P1B-04）=="
mk_out
seed "$OUTF/raw" dnsxdump .out 5 old
LOCK="$OUTF/raw/$(printf 'dnsxdump_2026%04d_%06d.out' 2 2)"
chattr +i "$LOCK"
run_cleanup; expect_rc F11 0; expect_out F11 "天數上限清理失敗"
[ -f "$LOCK" ] && ok "F11: 鎖住的檔案還在" || bad "F11: 鎖住的檔案不見了"
chattr -i "$LOCK"
run_cleanup; expect_rc F11b 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 0 ] && ok "F11b: 解鎖後清空" || bad "F11b: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"

echo "== F12: 合法前綴重疊不得跨家族刪除（P1B-08）=="
mk_out
seed "$OUTF/parsed" alpha .txt 30
seed "$OUTF/parsed" alpha_beta .txt 30
seed "$OUTF/final" keepme .txt 1 old
run_cleanup; expect_rc F12 0
[ "$(cnt "$OUTF/parsed" 'alpha_[0-9]*_[0-9]*.txt')" = 24 ] && ok "F12: alpha=24" || bad "F12: alpha=$(cnt "$OUTF/parsed" 'alpha_[0-9]*_[0-9]*.txt')"
[ "$(cnt "$OUTF/parsed" 'alpha_beta_*.txt')" = 24 ] && ok "F12: alpha_beta=24" || bad "F12: alpha_beta=$(cnt "$OUTF/parsed" 'alpha_beta_*.txt')"
[ -f "$OUTF/parsed/$(printf 'alpha_2026%04d_%06d.txt' 30 30)" ] && ok "F12: alpha 最新檔保留" || bad "F12: alpha 最新檔被刪"
[ ! -f "$OUTF/parsed/$(printf 'alpha_2026%04d_%06d.txt' 1 1)" ] && ok "F12: alpha 最舊超額檔已刪" || bad "F12: alpha 最舊檔還在"
[ -f "$OUTF/parsed/$(printf 'alpha_beta_2026%04d_%06d.txt' 30 30)" ] && ok "F12: alpha_beta 最新檔保留" || bad "F12: alpha_beta 最新檔被刪"
[ ! -f "$OUTF/parsed/$(printf 'alpha_beta_2026%04d_%06d.txt' 1 1)" ] && ok "F12: alpha_beta 最舊超額檔已刪" || bad "F12: alpha_beta 最舊檔還在"
[ "$(cnt "$OUTF/final" '*')" = 1 ] && ok "F12: final/ 不動" || bad "F12: final/ 被動到"

# =============================================================================
# trap 路徑測試: 真實執行新版 main.sh，步驟 2 失敗（newsrc 沒有 extract_rpz.sh）
# =============================================================================
echo "== T1: 失敗路徑（exit 1）仍清理 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 30
seed "$OUTF/raw" olddump .out 10 old
seed "$OUTF/final" keepme .txt 3 old
OUT=$(env OUTPUT_DIR="$OUTF" LOG_FILE="$R/ltm.log" bash "$NEWSRC/main.sh" --force 2>&1); RC=$?
expect_rc T1 1
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "T1: 失敗路徑仍 prune 到 24" || bad "T1: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"
[ "$(cnt "$OUTF/raw" 'olddump_*.out')" = 0 ] && ok "T1: 舊檔由天數上限刪除" || bad "T1: 舊檔還在"
[ "$(cnt "$OUTF/final" '*')" = 3 ] && ok "T1: final/ 不動" || bad "T1: final/ 被動到"

echo "== T2: 失敗路徑 + --no-cleanup 不清理 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 30
OUT=$(env OUTPUT_DIR="$OUTF" LOG_FILE="$R/ltm.log" bash "$NEWSRC/main.sh" --force --no-cleanup 2>&1); RC=$?
expect_rc T2 1
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 30 ] && ok "T2: 全保留" || bad "T2: 被刪"

echo "== T3: NO_UPDATE 路徑（exit 0）仍清理 =="
printf '#!/bin/bash\necho "NO_UPDATE"\n' > "$NEWSRC/check_soa.sh"
chmod +x "$NEWSRC/check_soa.sh"
mk_out
seed "$OUTF/raw" dnsxdump .out 30
seed "$OUTF/final" keepme .txt 3 old
OUT=$(env OUTPUT_DIR="$OUTF" LOG_FILE="$R/ltm.log" bash "$NEWSRC/main.sh" 2>&1); RC=$?
expect_rc T3 0; expect_out T3 "SOA Serial 未變更"
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 24 ] && ok "T3: NO_UPDATE 路徑 prune 到 24" || bad "T3: raw=$(cnt "$OUTF/raw" 'dnsxdump_*.out')"
[ "$(cnt "$OUTF/final" '*')" = 3 ] && ok "T3: final/ 不動" || bad "T3: final/ 被動到"

echo "== T4: NO_UPDATE + --no-cleanup 不清理 =="
mk_out
seed "$OUTF/raw" dnsxdump .out 30
OUT=$(env OUTPUT_DIR="$OUTF" LOG_FILE="$R/ltm.log" bash "$NEWSRC/main.sh" --no-cleanup 2>&1); RC=$?
expect_rc T4 0
[ "$(cnt "$OUTF/raw" 'dnsxdump_*.out')" = 30 ] && ok "T4: 全保留" || bad "T4: 被刪"
rm -f "$NEWSRC/check_soa.sh"

echo
echo "=============================================================="
printf ' PASS=%s  FAIL=%s\n' "$PASS" "$FAIL"
echo "=============================================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
