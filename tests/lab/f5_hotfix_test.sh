#!/bin/bash
# =============================================================================
# f5_hotfix_test.sh — SIGPIPE hotfix 行為驗收矩陣
#
# 用法: ./f5_hotfix_test.sh <scripts_dir> <orig|fixed> [重複次數]
#
# 對指定的 scripts 目錄跑 T1~T9，依 variant 套用對應的預期值。
# 任一 assertion 失敗即回傳非 0。
#
# 安全性: 全程在 mktemp -d 建立的隔離目錄，不讀寫 /config/snmp/rpz_datagroups，
#         不呼叫 tmsh。可在 LAB 或本機執行。
#
# 對應 CODE_REVIEW_20260821.md 的 CR-01、CR-02、7.1 節。
# =============================================================================

SCRIPTS="${1:?用法: $0 <scripts_dir> <orig|fixed> [reps]}"
VARIANT="${2:?variant 必須是 orig 或 fixed}"
REPS="${3:-20}"

case "${VARIANT}" in orig|fixed) ;; *) echo "variant 必須是 orig 或 fixed"; exit 2 ;; esac

# REPS 必須是正整數，否則 REPS=0 會讓 T8/T9 完全不執行卻回報成功 (R2-05)
case "${REPS}" in
    ''|*[!0-9]*) echo "REPS 必須是正整數，目前是 '${REPS}'"; exit 2 ;;
esac
if [ "${REPS}" -lt 1 ];    then echo "REPS 必須 >= 1（目前 ${REPS}）"; exit 2; fi
if [ "${REPS}" -gt 1000 ]; then echo "REPS 上限 1000（目前 ${REPS}）"; exit 2; fi
for s in utils.sh parse_rpz.sh generate_datagroup.sh; do
    [ -f "$SCRIPTS/$s" ] || { echo "找不到 $SCRIPTS/$s"; exit 2; }
done

FIX_RPZTW=400
FIX_PHISHTW=150

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }
note() { printf '         %s\n' "$*"; }

# --- 隔離工作區，OUTPUT_DIR 長度湊到 production 的 27 bytes ---------------
BASE=$(mktemp -d /var/tmp/rpzhf.XXXXXX) || exit 2
trap 'rm -rf "$BASE"' EXIT
want=$(( 27 - ${#BASE} - 1 ))
if [ "$want" -ge 1 ]; then
    sub=$(printf '%0*d' "$want" 0)
else
    sub=o; echo "警告: BASE 太長 (${#BASE})，OUTPUT_DIR 無法湊到 27 bytes"
fi
OUT="$BASE/$sub"
mkdir -p "$OUT" || exit 2

echo "=============================================================="
echo " f5_hotfix_test  variant=$VARIANT  reps=$REPS"
echo " 主機: $(uname -n)   時間: $(date '+%F %T')"
echo " scripts: $SCRIPTS"
echo " OUTPUT_DIR: $OUT  (長度 ${#OUT}，production 為 27)"
echo "=============================================================="
md5sum "$SCRIPTS"/utils.sh "$SCRIPTS"/parse_rpz.sh "$SCRIPTS"/generate_datagroup.sh 2>/dev/null \
    | sed "s|$SCRIPTS/||; s/^/ /"
echo

ZONELIST="$BASE/zonelist.txt"
printf 'rpztw\nphishtw\n' > "$ZONELIST"

SAMPLE="$BASE/sample.out"
build_sample() {
    local i
    {
        printf 'rpztw.\t900\tIN\tSOA\tinfoblox.localdomain please_set_email 1 60 60 900 900\n'
        printf 'phishtw.\t900\tIN\tSOA\tinfoblox.localdomain please_set_email 1 60 60 900 900\n'
        i=0; while [ $i -lt 200 ]; do i=$((i+1))
            printf 's%dt%d.rpztw.\t60\tIN\tA\t10.0.0.1\n' "$i" "$i"
            printf '*.s%dw%d.rpztw.\t60\tIN\tA\t10.0.0.2\n' "$i" "$i"
        done
        i=0; while [ $i -lt 150 ]; do i=$((i+1))
            printf 's%dp%d.phishtw.\t60\tIN\tA\t10.0.0.3\n' "$i" "$i"
        done
    } > "$SAMPLE"
}
build_sample || { echo "無法建立 sample"; exit 2; }

reset_dirs() { rm -rf "$OUT/raw" "$OUT/parsed" "$OUT/final"; mkdir -p "$OUT/raw" "$OUT/parsed" "$OUT/final"; }

fill_raw() {   # fill_raw <佔位檔數>  最新的一份是真樣本
    local n="$1" i=0
    while [ "$i" -lt "$n" ]; do i=$((i+1))
        : > "$OUT/raw/$(printf 'dnsxdump_2026%04d_%06d.out' "$i" "$i")"
        touch -t 202601010000 "$OUT/raw/$(printf 'dnsxdump_2026%04d_%06d.out' "$i" "$i")"
    done
    cp "$SAMPLE" "$OUT/raw/dnsxdump_20990101_000001.out"
    touch "$OUT/raw/dnsxdump_20990101_000001.out"
}

fill_parsed() {  # fill_parsed <每zone佔位檔數> [跳過的zone]
    local n="$1" skip="${2:-}" z i
    for z in rpztw phishtw rpzip; do
        [ "$z" = "$skip" ] && continue
        i=0; while [ "$i" -lt "$n" ]; do i=$((i+1))
            : > "$OUT/parsed/$(printf '%s_2026%04d_%06d.txt' "$z" "$i" "$i")"
            touch -t 202601010000 "$OUT/parsed/$(printf '%s_2026%04d_%06d.txt' "$z" "$i" "$i")"
        done
    done
    [ "$skip" != "rpztw" ]   && { printf '"a.example" := "1.1.1.1",\n' > "$OUT/parsed/rpztw_20990101_000001.txt"; }
    [ "$skip" != "phishtw" ] && { printf '"b.example" := "2.2.2.2",\n' > "$OUT/parsed/phishtw_20990101_000001.txt"; }
    [ "$skip" != "rpzip" ]   && { : > "$OUT/parsed/rpzip_20990101_000001.txt"; }
}

seed_final() {
    printf '"old.example" := "9.9.9.9",\n' > "$OUT/final/rpztw.txt"
    printf '"old.example" := "9.9.9.9",\n' > "$OUT/final/phishtw.txt"
    : > "$OUT/final/rpzip.txt"
}

final_sig() { md5sum "$OUT/final"/*.txt 2>/dev/null | awk '{print $1}' | tr '\n' ' '; }

run_parse() { OUTPUT_DIR="$OUT" ZONELIST_FILE="$ZONELIST" bash "$SCRIPTS/parse_rpz.sh" >"$BASE/p.log" 2>&1; }
run_gen()   { OUTPUT_DIR="$OUT" ZONELIST_FILE="$ZONELIST" bash "$SCRIPTS/generate_datagroup.sh" >"$BASE/g.log" 2>&1; }

# ---------------------------------------------------------------- T1
echo "T1  正常 parse：exit 0、產出 3 個 parsed、筆數符合 fixture"
reset_dirs; fill_raw 3
if run_parse; then
    n=$(ls -1 "$OUT/parsed" 2>/dev/null | wc -l | tr -d ' ')
    r=$(wc -l < "$OUT/parsed"/rpztw_*.txt 2>/dev/null | tr -d ' ')
    p=$(wc -l < "$OUT/parsed"/phishtw_*.txt 2>/dev/null | tr -d ' ')
    z=$(wc -l < "$OUT/parsed"/rpzip_*.txt 2>/dev/null | tr -d ' ')
    [ "$n" = 3 ] && ok "產出 3 個 parsed" || bad "parsed 檔數=${n}，預期 3"
    [ "$r" = "$FIX_RPZTW" ]   && ok "rpztw $r 筆"   || bad "rpztw=${r}，預期 $FIX_RPZTW"
    [ "$p" = "$FIX_PHISHTW" ] && ok "phishtw $p 筆" || bad "phishtw=${p}，預期 $FIX_PHISHTW"
    [ "$z" = 0 ] && ok "rpzip 0 筆" || bad "rpzip=${z}，預期 0"
else
    bad "parse 退出碼非 0"
fi

# ---------------------------------------------------------------- T2
echo "T2  取最新 raw：使用的必須是 mtime 最新的那一份"
reset_dirs; fill_raw 5
if run_parse && grep -q 'dnsxdump_20990101_000001.out' "$BASE/p.log"; then
    ok "選中最新的 dnsxdump_20990101_000001.out"
else
    bad "沒有選中最新檔"; note "$(grep -m1 'dnsxdump' "$BASE/p.log")"
fi

# ---------------------------------------------------------------- T3
echo "T3  raw 空：parse 必須非零，且不得產出 parsed"
reset_dirs
if run_parse; then bad "parse 退出碼 0，應為非零"
else
    ok "parse 退出碼非零 ($?)"
    n=$(ls -1 "$OUT/parsed" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" = 0 ] && ok "parsed 無產出" || bad "parsed 有 $n 個檔"
fi

# ---------------------------------------------------------------- T4
echo "T4  正常 generate：exit 0、final 3 檔、rpztw 內容來自最新 parsed"
reset_dirs; seed_final; fill_parsed 3
if run_gen; then
    ok "generate 退出碼 0"
    a=$(md5sum "$OUT/final/rpztw.txt" | awk '{print $1}')
    b=$(md5sum "$OUT/parsed/rpztw_20990101_000001.txt" | awk '{print $1}')
    [ "$a" = "$b" ] && ok "final/rpztw.txt 來自最新 parsed" || bad "final/rpztw.txt 不是最新 parsed"
    n=$(ls -1 "$OUT/final" | wc -l | tr -d ' ')
    [ "$n" = 3 ] && ok "final 3 檔" || bad "final $n 檔"
else
    bad "generate 退出碼非 0"; note "$(tail -2 "$BASE/g.log")"
fi

# ---------------------------------------------------------------- T5
echo "T5  parsed 全空：generate 必須非零，final 完全不變"
reset_dirs; seed_final; before=$(final_sig)
if run_gen; then bad "generate 退出碼 0，應為非零"; else ok "generate 退出碼非零"; fi
after=$(final_sig)
[ "$before" = "$after" ] && ok "final 未變動" || bad "final 被改動：$before -> $after"

# ---------------------------------------------------------------- T6
echo "T6  只缺 phishtw：generate 必須非零，且不得部分發布"
reset_dirs; seed_final; fill_parsed 3 phishtw; before=$(final_sig)
run_gen; rc=$?
after=$(final_sig)
[ "$rc" -ne 0 ] && ok "generate 退出碼非零 ($rc)" || bad "generate 退出碼 0，應為非零"
if [ "$VARIANT" = fixed ]; then
    [ "$before" = "$after" ] && ok "final 完全未變動（無部分發布）" \
        || bad "final 被部分發布：$before -> $after"
else
    if [ "$before" = "$after" ]; then note "原版 final 未變動"
    else note "原版發生部分發布（已知缺陷）：$before -> $after"; fi
fi

# ---------------------------------------------------------------- T7
echo "T7  rpzip artifact 存在但 0 bytes：generate 必須成功"
reset_dirs; seed_final; fill_parsed 3
if run_gen; then ok "generate 退出碼 0"; else bad "generate 退出碼非 0"; note "$(tail -2 "$BASE/g.log")"; fi

# ---------------------------------------------------------------- T8
echo "T8  raw 300 檔 × $REPS 次：SIGPIPE 失敗數"
reset_dirs; fill_raw 300
b8=$(ls -t "$OUT"/raw/dnsxdump_*.out | wc -c | tr -d ' ')
f8=0; t=0
while [ $t -lt "$REPS" ]; do t=$((t+1))
    rm -rf "$OUT/parsed"; mkdir -p "$OUT/parsed"
    run_parse || f8=$((f8+1))
done
note "ls 輸出 ${b8}B，失敗 $f8/$REPS"
if [ "$VARIANT" = fixed ]; then
    [ "$f8" = 0 ] && ok "修正版 0 失敗" || bad "修正版仍有 $f8 次失敗"
else
    [ "$f8" -gt 0 ] && ok "原版如預期會失敗（$f8 次），測試環境有效" \
        || bad "原版 0 失敗，測試環境未觸發缺陷，T8/T9 結果不可信"
fi

# ---------------------------------------------------------------- T9
echo "T9  parsed 每 zone 300 檔 × $REPS 次：SIGPIPE 失敗數"
reset_dirs; seed_final; fill_parsed 300
b9=$(ls -t "$OUT"/parsed/rpztw_*.txt | wc -c | tr -d ' ')
f9=0; t=0
while [ $t -lt "$REPS" ]; do t=$((t+1)); run_gen || f9=$((f9+1)); done
note "ls 輸出 ${b9}B，失敗 $f9/$REPS"
if [ "$VARIANT" = fixed ]; then
    [ "$f9" = 0 ] && ok "修正版 0 失敗" || bad "修正版仍有 $f9 次失敗"
else
    [ "$f9" -gt 0 ] && ok "原版如預期會失敗（$f9 次）" || bad "原版 0 失敗，環境未觸發"
fi

echo
echo "=============================================================="
printf ' variant=%s  PASS=%s  FAIL=%s\n' "$VARIANT" "$PASS" "$FAIL"
echo "=============================================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
