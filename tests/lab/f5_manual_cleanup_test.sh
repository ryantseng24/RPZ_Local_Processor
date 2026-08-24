#!/bin/bash
# =============================================================================
# f5_manual_cleanup_test.sh
#
# !!!!!!!!!!!!!!!!!!!!!!!!  DESTRUCTIVE — LAB ONLY  !!!!!!!!!!!!!!!!!!!!!!!!
#
# 變數契約（R3-07）：本專案的腳本用 OUTPUT_DIR 當資料目錄的環境變數名稱。
# 本測試一律使用 OUTPUT_DIR，並在【每一次】呼叫子腳本時明確傳入，避免
# guard 檢查一個路徑、子腳本卻用預設 /config/snmp/rpz_datagroups 的不一致。
#
# 用途: 驗證「人力手動刪檔」能否在套用 patch 之前恢復 pipeline。
#       必須在【原版 v1.2 腳本】的狀態下執行才有意義。
#
# 會做的事（全部使用同一組解析後的路徑變數，見下方 SCRIPTS_DIR / OUTPUT_DIR）:
#   - 刪除 OUTPUT_DIR/raw/dnsxdump_*.out
#   - 刪除 OUTPUT_DIR/parsed/rpztw_*.txt、phishtw_*.txt、rpzip_*.txt
#   - 執行 SCRIPTS_DIR/main.sh --force（會呼叫 tmsh modify data-group 與 tmsh save）
#
# 不會碰 OUTPUT_DIR/final/。
#
# 絕對不可在正式機執行。不可放進 deployment package。
# 對應 CODE_REVIEW_20260821.md CR-16 與
#      CODE_REVIEW_PHASE1A_ROUND2_20260821.md R2-03。
#
# 用法:
#   ./f5_manual_cleanup_test.sh --lab-only [--allow-production-marker]
#
#   --lab-only                 必填。表示你確認這是 LAB 主機。
#   --allow-production-marker  極高風險。僅在 final/rpztw.txt 非空但你確定是
#                              LAB 時使用。它【不會】放寬 hostname 檢查。
#
# 環境變數:
#   LAB_HOSTNAME     預期的 LAB hostname，預設 cdns.ryantseng.work。hostname
#                    不符一律拒絕，沒有任何旗標可以繞過。
#   RPZ_LAB_CONFIRM  非互動模式的確認值，必須精確等於實際 hostname。
#                    stdin 是 tty 時改用互動輸入。
#   INSTALL_DIR      預設 /config/snmp/RPZ_Local_Processor
#   OUTPUT_DIR       資料目錄，預設 /config/snmp/rpz_datagroups
#                    （與 main.sh / parse_rpz.sh / generate_datagroup.sh 同名）
#   REPS             每個情境的重複次數，預設 20
# =============================================================================

LAB_ONLY=0
ALLOW_PROD_MARKER=0
while [ $# -gt 0 ]; do
    case "$1" in
        --lab-only)                LAB_ONLY=1; shift ;;
        --allow-production-marker) ALLOW_PROD_MARKER=1; shift ;;
        -h|--help) sed -n '2,/^# ====/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知選項: $1"; exit 2 ;;
    esac
done

# -----------------------------------------------------------------------------
# 路徑只在這裡解析一次。guard、顯示、刪除、執行全部只用這兩個變數 (R2-03)
# -----------------------------------------------------------------------------
INSTALL_DIR="${INSTALL_DIR:-/config/snmp/RPZ_Local_Processor}"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"
ZONELIST_FILE="${ZONELIST_FILE:-${INSTALL_DIR}/config/zonelist.txt}"
LAB_HOSTNAME="${LAB_HOSTNAME:-cdns.ryantseng.work}"
REPS="${REPS:-20}"
HOST=$(uname -n)

MD5_ORIG_utils=3cab6cbca952f3780350e9882e5f7c11
MD5_ORIG_parse=bbe45c6f79b56922388d4af7aa6e7583
MD5_ORIG_generate=35547d33ce109945d1ca17e8eb241e0a

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }
die() { printf '\n拒絕執行：%s\n' "$*"; exit 2; }

echo "=============================================================="
echo " !!  DESTRUCTIVE LAB TEST  !!"
echo "=============================================================="
printf ' 主機:        %s\n' "$HOST"
printf ' 預期 LAB:    %s\n' "$LAB_HOSTNAME"
echo " 會被操作的確切路徑:"
printf '   %s/raw/dnsxdump_*.out          <- 刪除\n' "$OUTPUT_DIR"
printf '   %s/parsed/rpztw_*.txt          <- 刪除\n' "$OUTPUT_DIR"
printf '   %s/parsed/phishtw_*.txt        <- 刪除\n' "$OUTPUT_DIR"
printf '   %s/parsed/rpzip_*.txt          <- 刪除\n' "$OUTPUT_DIR"
printf '   %s/main.sh --force             <- 執行\n' "$SCRIPTS_DIR"
echo " 不會被操作:"
printf '   %s/final/                      <- 不動\n' "$OUTPUT_DIR"
echo "=============================================================="
echo

# -----------------------------------------------------------------------------
# Guard 1: 必須明確宣告 --lab-only
# -----------------------------------------------------------------------------
[ "$LAB_ONLY" -eq 1 ] || die "必須明確加上 --lab-only。這支腳本會刪檔並執行 main.sh --force。"

# -----------------------------------------------------------------------------
# Guard 2: hostname 必須精確相符。沒有旗標可以繞過。
# -----------------------------------------------------------------------------
[ "$HOST" = "$LAB_HOSTNAME" ] || \
    die "hostname '$HOST' 不等於預期的 LAB hostname '$LAB_HOSTNAME'。若 LAB hostname 不同，請設 LAB_HOSTNAME=<正確值>。"

# -----------------------------------------------------------------------------
# Guard 3: LAB marker 必須存在（與 hostname 是 AND 關係）
# -----------------------------------------------------------------------------
[ -d "$OUTPUT_DIR" ]     || die "找不到資料目錄 ${OUTPUT_DIR}"
[ -d "$SCRIPTS_DIR" ]  || die "找不到腳本目錄 $SCRIPTS_DIR"

# -----------------------------------------------------------------------------
# Guard 4: production marker。只有專屬旗標能放寬，不共用 --lab-only
# -----------------------------------------------------------------------------
if [ -s "$OUTPUT_DIR/final/rpztw.txt" ] && [ "$ALLOW_PROD_MARKER" -ne 1 ]; then
    die "偵測到 ${OUTPUT_DIR}/final/rpztw.txt 存在且非空，這看起來是有在服務的機器。確認是 LAB 請加 --allow-production-marker。"
fi

# -----------------------------------------------------------------------------
# Guard 5: 互動或環境變數的 exact-value 確認
# -----------------------------------------------------------------------------
if [ -t 0 ]; then
    printf '請輸入完整 hostname 以確認（%s）: ' "$LAB_HOSTNAME"
    read -r answer
else
    answer="${RPZ_LAB_CONFIRM:-}"
    printf '非互動模式，使用 RPZ_LAB_CONFIRM 確認\n'
fi
[ "$answer" = "$HOST" ] || die "確認值不符。需要精確輸入 '$HOST'（互動輸入或設 RPZ_LAB_CONFIRM）。"

# -----------------------------------------------------------------------------
# Guard 6: iCall handler 必須 inactive，且沒有執行中的 processor
# -----------------------------------------------------------------------------
if command -v tmsh >/dev/null 2>&1; then
    hstate=$(tmsh list sys icall handler periodic 2>/dev/null | grep -c 'status inactive')
    htotal=$(tmsh list sys icall handler periodic 2>/dev/null | grep -c '^sys icall handler')
    if [ "$htotal" -gt 0 ] && [ "$hstate" -lt "$htotal" ]; then
        die "有 iCall periodic handler 不是 inactive（$hstate/$htotal inactive）。請先停用：tmsh modify sys icall handler periodic <name> status inactive"
    fi
fi
procs=$(pgrep -f "rpz_wrapper|${SCRIPTS_DIR}/main.sh" 2>/dev/null | tr '\n' ' ')
[ -z "$procs" ] || die "偵測到執行中的 processor (PID: $procs)。請等待結束。"

# -----------------------------------------------------------------------------
# Guard 7: 三支腳本必須是本測試預期的原版 v1.2
# -----------------------------------------------------------------------------
md5f() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }
for pair in "utils.sh:$MD5_ORIG_utils" "parse_rpz.sh:$MD5_ORIG_parse" "generate_datagroup.sh:$MD5_ORIG_generate"; do
    f="${pair%%:*}"; want="${pair##*:}"; got=$(md5f "$SCRIPTS_DIR/$f")
    [ "$got" = "$want" ] || \
        die "$f 不是原版 v1.2（實際 ${got}，預期 ${want}）。本測試必須在原版狀態下執行，否則結果無意義。"
done

echo "七道防呆檢查全部通過，開始執行。"
echo

# =============================================================================
# 測試主體
# =============================================================================
S="$SCRIPTS_DIR"
D="$OUTPUT_DIR"

# 每一次子腳本呼叫都明確傳入同一組路徑，不依賴子腳本的預設值 (R3-07)
run_parse() { OUTPUT_DIR="$D" ZONELIST_FILE="$ZONELIST_FILE" bash "$S/parse_rpz.sh" >/dev/null 2>&1; }
run_gen()   { OUTPUT_DIR="$D" ZONELIST_FILE="$ZONELIST_FILE" bash "$S/generate_datagroup.sh" >/dev/null 2>&1; }
run_main()  { OUTPUT_DIR="$D" ZONELIST_FILE="$ZONELIST_FILE" bash "$S/main.sh" --force; }

fill_raw() { local n=$1 i=0 f
    find "$D/raw" -maxdepth 1 -name 'dnsxdump_*.out' -delete 2>/dev/null
    while [ "$i" -lt "$n" ]; do i=$((i+1))
        f="$D/raw/$(printf 'dnsxdump_2026%04d_%06d.out' "$i" "$i")"
        : > "$f"; touch -t 202608010000 "$f"
    done
}
fill_parsed() { local n=$1 z i f
    for z in rpztw phishtw rpzip; do
        find "$D/parsed" -maxdepth 1 -name "${z}_*.txt" -delete 2>/dev/null
        i=0; while [ "$i" -lt "$n" ]; do i=$((i+1))
            f="$D/parsed/$(printf '%s_2026%04d_%06d.txt' "$z" "$i" "$i")"
            : > "$f"; touch -t 202608010000 "$f"
        done
    done
}
report() {
    printf '  raw=%-4s(%-7s) parsed/zone=%-4s(%-7s)\n' \
      "$(ls -1 "$D"/raw/dnsxdump_*.out 2>/dev/null | wc -l | tr -d ' ')" \
      "$(ls -t "$D"/raw/dnsxdump_*.out 2>/dev/null | wc -c | tr -d ' ')B" \
      "$(ls -1 "$D"/parsed/rpztw_*.txt 2>/dev/null | wc -l | tr -d ' ')" \
      "$(ls -t "$D"/parsed/rpztw_*.txt 2>/dev/null | wc -c | tr -d ' ')B"
}
trial() {
    local label="$1" want3="$2" want4="$3" f3=0 f4=0 t
    for t in $(seq 1 "$REPS"); do
        run_parse || f3=$((f3+1))
        run_gen   || f4=$((f4+1))
    done
    printf '  %-30s 步驟3 %2s/%s   步驟4 %2s/%s\n' "$label" "$f3" "$REPS" "$f4" "$REPS"
    case "$want3" in
        zero) [ "$f3" -eq 0 ] && ok "$label 步驟3 為 0 失敗" || bad "$label 步驟3 有 $f3 次失敗" ;;
        some) [ "$f3" -gt 0 ] && ok "$label 步驟3 如預期會失敗" || bad "$label 步驟3 沒有失敗，環境未觸發缺陷" ;;
    esac
    case "$want4" in
        zero) [ "$f4" -eq 0 ] && ok "$label 步驟4 為 0 失敗" || bad "$label 步驟4 有 $f4 次失敗" ;;
        some) [ "$f4" -gt 0 ] && ok "$label 步驟4 如預期會失敗" || bad "$label 步驟4 沒有失敗" ;;
    esac
}

FSIG_BEFORE=$(md5sum "$D"/final/*.txt 2>/dev/null | awk '{print $1}' | tr '\n' ' ')

echo "=== 情境 A：raw/ 完全清空，跑完整 main.sh（步驟 2 應自動重建）==="
find "$D/raw" -maxdepth 1 -name 'dnsxdump_*.out' -delete 2>/dev/null
printf '  raw/ 的 dnsxdump 檔案數 = %s\n' "$(ls -1 "$D"/raw/dnsxdump_*.out 2>/dev/null | wc -l | tr -d ' ')"
if run_main >/var/tmp/caseA.log 2>&1; then
    ok "main.sh --force 退出碼 0"
    grep -qE '步驟 5/5' /var/tmp/caseA.log && ok "跑到步驟 5" || bad "沒有跑到步驟 5"
else
    bad "main.sh --force 退出碼非 0"
fi

echo
echo "=== 情境 B：只清 raw/ 到 60，parsed/ 不動（95/zone）==="
fill_raw 60; fill_parsed 95; report
trial "只清 raw" zero some

echo
echo "=== 情境 C：raw/ 與 parsed/ 都清到 60 ==="
fill_raw 60; fill_parsed 60; report
trial "raw + parsed 都清" zero zero

echo
echo "=== 情境 D：完全不清（模擬停滯最久設備的現況）==="
fill_raw 179; fill_parsed 95; report
trial "不清理" some some

echo
echo "=== final/ 的不變量檢查 ==="
# 情境 A~D 都會合法寫入 final/（generate 成功時就 cp），所以不能斷言 checksum
# 不變。真正的不變量是：三個檔案都在，rpztw/phishtw 非空。
for z in rpztw phishtw rpzip; do
    [ -f "$D/final/${z}.txt" ] && ok "final/${z}.txt 存在" || bad "final/${z}.txt 不見了"
done
[ -s "$D/final/rpztw.txt" ] \
    && ok "final/rpztw.txt 非空（$(wc -l < "$D/final/rpztw.txt" | tr -d " ") 筆）" \
    || bad "final/rpztw.txt 是空的"
[ -s "$D/final/phishtw.txt" ] \
    && ok "final/phishtw.txt 非空（$(wc -l < "$D/final/phishtw.txt" | tr -d " ") 筆）" \
    || bad "final/phishtw.txt 是空的"
printf '  final/ checksum: %s -> %s\n' "$FSIG_BEFORE" \
    "$(md5sum "$D"/final/*.txt 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"

echo
echo "=============================================================="
printf ' PASS=%s  FAIL=%s\n' "$PASS" "$FAIL"
echo "=============================================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
