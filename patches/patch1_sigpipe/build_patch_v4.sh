#!/bin/bash
# build_patch_v4.sh — 從 tracked source 組出 rpz_patch_sigpipe_v4.sh
# 在 macOS 上執行。產出物在 repo 的 patches/patch1_sigpipe/ 下。
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SRC=$REPO/scripts
OUT=$REPO/patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh
WORK=$(mktemp "${TMPDIR:-/tmp}/v4build.XXXXXX")

# ---- 原版 v1.2 md5: 審核核定常數（V4-03、R2-V4-03）----
# 來源: 審核核定的 GitHub baseline
#       （commit 27415940f03641ccd920e664797d79447bd91617, origin/main）。
# 這不是四台正式機的實測證據。每台正式機 apply 前必須先執行 check，
# 任一檔 md5 版本不明就停止（審核第 9 節 canary rule）。
# 不從 git HEAD 讀取: release commit 之後 HEAD 就是新版，git 讀法會失效。
OU=3cab6cbca952f3780350e9882e5f7c11
OP=bbe45c6f79b56922388d4af7aa6e7583
OG=35547d33ce109945d1ca17e8eb241e0a

# ---- 修正版 md5（防止 working tree 漂移）----
EXP_NU=b8294149dc978305e19bcd83fcb650e6
EXP_NP=cefa71b6623632dd51c60a51cdf72196
EXP_NG=9599755a54db53652c070cd70ae92652

NU=$(md5 -q "$SRC/utils.sh")
NP=$(md5 -q "$SRC/parse_rpz.sh")
NG=$(md5 -q "$SRC/generate_datagroup.sh")

[ "$NU" = "$EXP_NU" ] || { echo "FAIL: worktree utils.sh md5=$NU != $EXP_NU"; exit 1; }
[ "$NP" = "$EXP_NP" ] || { echo "FAIL: worktree parse_rpz.sh md5=$NP != $EXP_NP"; exit 1; }
[ "$NG" = "$EXP_NG" ] || { echo "FAIL: worktree generate_datagroup.sh md5=$NG != $EXP_NG"; exit 1; }

# delimiter 不得出現在內嵌檔案中
if grep -q '__RPZ_EMBED__' "$SRC/utils.sh" "$SRC/parse_rpz.sh" "$SRC/generate_datagroup.sh"; then
    echo "FAIL: 內嵌檔案含 __RPZ_EMBED__"; exit 1
fi

# ---- 組裝 ----
{
cat <<'LOGIC_PART1'
#!/bin/bash
# =============================================================================
# rpz_patch_sigpipe_v4.sh — RPZ Local Processor SIGPIPE(4096) 修正 patch
#
# 問題:
#   三處 `ls -t <glob> | head -1` 在 set -o pipefail 下，當 ls 輸出超過
#   4096 bytes（約 67 個檔案）時，ls 收到 SIGPIPE 以 141 結束，
#   set -e 讓腳本靜默中止，RPZ 黑名單停止更新。
#
# 修正（只換三個檔案，其他不動）:
#   utils.sh               新增 find_newest_file()（純新增函數）
#   parse_rpz.sh           改用 find_newest_file()
#   generate_datagroup.sh  改用 find_newest_file()，改為先解析全部再發布
#
# 用法:
#   bash rpz_patch_sigpipe_v4.sh check                # 只檢查版本，不改檔案
#   bash rpz_patch_sigpipe_v4.sh apply                # 備份後套用
#   bash rpz_patch_sigpipe_v4.sh rollback <備份目錄>   # 從備份還原
#
# 退出碼:
#   0  成功（含「已套用，無需動作」）
#   1  執行中發生錯誤
#   2  前置條件不符（版本不明 / RPZ 程序執行中 / 參數錯誤）
#
# 安全設計:
#   1. 先核對三個檔案的 md5。任一不是已知版本，整批中止，不改任何檔案。
#   2. 套用前備份到 /var/tmp/rpz_patch_backup_<時間>/，附 md5sums.txt。
#   3. 寫入用同目錄暫存檔 + mv。單一檔案的取代是原子動作。
#   4. 安裝順序 utils -> parse_rpz -> generate_datagroup。utils.sh 是純新增，
#      任何中斷點留下的組合都能正常運作。rollback 用相反順序。
#   5. 內嵌檔案抽出後先核對 md5，通過才放進目標位置。
#   6. 版本組合規則: 新版 parse_rpz/generate_datagroup 需要新版 utils.sh 的
#      find_newest_file()。utils 是舊版而 consumer 是新版的組合不可運作，
#      check 會以 RC=2 回報，apply 會警告並修復。
#   7. rollback 只接受純原版 v1.2 備份，且會先預檢目前檔案（版本不明或
#      缺少即拒絕）。兩種拒絕都發生在改任何檔案之前。
# =============================================================================
set -euo pipefail

SCRIPTS_DIR="/config/snmp/RPZ_Local_Processor/scripts"
BACKUP_ROOT="/var/tmp"
FILES=(utils.sh parse_rpz.sh generate_datagroup.sh)

# md5: v1.2 原版 -> 修正版
declare -A ORIG NEW
ORIG[utils.sh]="%ORIG_UTILS%"
ORIG[parse_rpz.sh]="%ORIG_PARSE%"
ORIG[generate_datagroup.sh]="%ORIG_GEN%"
NEW[utils.sh]="%NEW_UTILS%"
NEW[parse_rpz.sh]="%NEW_PARSE%"
NEW[generate_datagroup.sh]="%NEW_GEN%"

TMPF=""
trap 'rm -f "${TMPF:-}"' EXIT

log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die()  { log "錯誤: $*"; exit 1; }
die2() { log "中止: $*"; exit 2; }

md5of() { md5sum "$1" | awk '{print $1}'; }

state_of() {
    # 輸出 orig / new / unknown / missing
    local p="${SCRIPTS_DIR}/$1" h
    [[ -f "$p" ]] || { echo missing; return; }
    h=$(md5of "$p")
    if   [[ "$h" == "${ORIG[$1]}" ]]; then echo orig
    elif [[ "$h" == "${NEW[$1]}"  ]]; then echo new
    else echo unknown
    fi
}

state_zh() {
    case "$1" in
        orig)    echo "原版 v1.2" ;;
        new)     echo "已修正" ;;
        missing) echo "檔案不存在" ;;
        *)       echo "版本不明" ;;
    esac
}

dep_violation() {
    # 新版 consumer 需要新版 utils.sh 的 find_newest_file()
    local su sp sg
    su=$(state_of utils.sh)
    sp=$(state_of parse_rpz.sh)
    sg=$(state_of generate_datagroup.sh)
    [[ "$su" == orig && ( "$sp" == new || "$sg" == new ) ]]
}

guard_not_running() {
    local pat='RPZ_Local_Processor/scripts/[a-z_]+[.]sh|rpz_wrapper[.]sh'
    if pgrep -f "$pat" >/dev/null 2>&1; then
        log "偵測到以下程序:"
        pgrep -af "$pat" | sed 's/^/    /'
        die2 "RPZ 處理程序執行中。等它結束後重試（iCall 週期 300 秒，單次執行約 1-2 分鐘）"
    fi
}

place_file() {
    # place_file <檔名> <暫存檔> <期望md5>
    # 權限與擁有者沿用目標既有檔案，然後以 mv 原子取代
    local f="$1" tmp="$2" want="$3" tgt="${SCRIPTS_DIR}/${f}" got
    [[ -f "$tgt" ]] || die "目標檔案不存在: ${tgt}"
    got=$(md5of "$tmp")
    [[ "$got" == "$want" ]] || die "暫存檔 md5 不符: ${f} (got=${got} want=${want})"
    chmod --reference="$tgt" "$tmp"
    chown --reference="$tgt" "$tmp"
    mv -f "$tmp" "$tgt"
}

do_check() {
    local f p h s n_new=0 n_orig=0 n_bad=0
    log "目標目錄: ${SCRIPTS_DIR}"
    for f in "${FILES[@]}"; do
        p="${SCRIPTS_DIR}/${f}"
        if [[ -f "$p" ]]; then h=$(md5of "$p"); else h="-"; fi
        s=$(state_of "$f")
        printf '    %-24s %-34s %s\n' "$f" "$h" "$(state_zh "$s")"
        case "$s" in
            new)  n_new=$((n_new + 1)) ;;
            orig) n_orig=$((n_orig + 1)) ;;
            *)    n_bad=$((n_bad + 1)) ;;
        esac
    done
    if (( n_bad > 0 )); then
        die2 "有版本不明或缺少的檔案，禁止套用。請先人工比對差異。"
    fi
    if dep_violation; then
        die2 "版本組合不可運作: 新版 parse_rpz/generate_datagroup 需要新版 utils.sh（find_newest_file）。執行 apply 可修復為全新版。"
    fi
    if (( n_new == ${#FILES[@]} )); then
        log "判定: 已全部套用修正。"
    elif (( n_orig == ${#FILES[@]} )); then
        log "判定: 全部是原版 v1.2，可以套用。"
    else
        log "判定: 部分套用。再執行一次 apply 會補齊其餘檔案。"
    fi
}

do_apply() {
    local f s backup ts n_new=0
    declare -A S
    for f in "${FILES[@]}"; do
        s=$(state_of "$f")
        if [[ "$s" != orig && "$s" != new ]]; then
            die2 "檔案版本不明或缺少: ${SCRIPTS_DIR}/${f}（先執行 check 檢視）"
        fi
        S[$f]="$s"
        if [[ "$s" == new ]]; then n_new=$((n_new + 1)); fi
    done
    if (( n_new == ${#FILES[@]} )); then
        log "三個檔案都已是修正版，無需動作。"
        return 0
    fi
    if dep_violation; then
        log "警告: 目前版本組合不可運作（新版 consumer 缺 find_newest_file）。apply 將修復為全新版。"
        log "警告: 本次產生的備份是混合狀態，rollback 會拒絕它。退回原版請用純原版備份。"
    fi
    guard_not_running

    ts=$(date '+%Y%m%d_%H%M%S')
    backup="${BACKUP_ROOT}/rpz_patch_backup_${ts}"
    mkdir "$backup"
    for f in "${FILES[@]}"; do
        cp -p "${SCRIPTS_DIR}/${f}" "${backup}/${f}"
    done
    ( cd "$backup" && md5sum "${FILES[@]}" > md5sums.txt )
    log "備份完成: ${backup}"

    for f in "${FILES[@]}"; do
        if [[ "${S[$f]}" == new ]]; then
            log "略過（已是修正版）: ${f}"
            continue
        fi
        TMPF=$(mktemp "${SCRIPTS_DIR}/.${f}.XXXXXX")
        emit_new "$f" > "$TMPF"
        place_file "$f" "$TMPF" "${NEW[$f]}"
        TMPF=""
        log "已安裝: ${f}"
    done

    for f in "${FILES[@]}"; do
        if [[ "$(state_of "$f")" != new ]]; then
            die "安裝後驗證失敗: ${f}"
        fi
    done
    log "套用完成。三個檔案 md5 驗證通過。"
    log "還原指令: bash $0 rollback ${backup}"
}

do_rollback() {
    local backup="${1:-}" f want d s
    if [[ -z "$backup" ]]; then
        log "用法: bash $0 rollback <備份目錄>"
        log "現有備份目錄:"
        for d in "${BACKUP_ROOT}"/rpz_patch_backup_*/; do
            if [[ -d "$d" ]]; then printf '    %s\n' "${d%/}"; fi
        done
        exit 2
    fi
    [[ -d "$backup" ]] || die2 "備份目錄不存在: ${backup}"
    [[ -f "${backup}/md5sums.txt" ]] || die2 "備份缺少 md5sums.txt: ${backup}"
    ( cd "$backup" && md5sum -c md5sums.txt >/dev/null 2>&1 ) \
        || die2 "備份檔案 md5 驗證失敗: ${backup}"

    # 只接受純原版 v1.2 備份（V4-02）: 混合備份在改任何檔案前就拒絕
    for f in "${FILES[@]}"; do
        want=$(awk -v f="$f" '$2 == f {print $1}' "${backup}/md5sums.txt")
        [[ -n "$want" ]] || die2 "md5sums.txt 缺少 ${f} 的記錄"
        [[ "$want" == "${ORIG[$f]}" ]] \
            || die2 "備份不是純原版 v1.2: ${f}（${want}）。拒絕還原。請改用純原版備份目錄。"
    done

    # 目前檔案預檢（R2-V4-02）: 只接受 orig/new。版本不明或缺少即拒絕，
    # 不覆寫未經確認的本機改動。依賴違規組合（各檔皆為已知版本）可通過，
    # 由純原版還原修復。
    for f in "${FILES[@]}"; do
        s=$(state_of "$f")
        [[ "$s" == orig || "$s" == new ]] \
            || die2 "目前檔案版本不明或缺少: ${SCRIPTS_DIR}/${f}（$(state_zh "$s")）。rollback 拒絕覆寫，請先人工確認。"
    done
    guard_not_running

    # 還原順序與安裝相反
    for f in generate_datagroup.sh parse_rpz.sh utils.sh; do
        TMPF=$(mktemp "${SCRIPTS_DIR}/.${f}.XXXXXX")
        cat "${backup}/${f}" > "$TMPF"
        place_file "$f" "$TMPF" "${ORIG[$f]}"
        TMPF=""
        log "已還原: ${f}"
    done
    for f in "${FILES[@]}"; do
        [[ "$(state_of "$f")" == orig ]] || die "還原後驗證失敗: ${f}"
    done
    log "還原完成。目前狀態:"
    do_check
}

# ===== 內嵌檔案（由 build_patch_v4.sh 自 tracked source 產生，勿手改）=====

LOGIC_PART1

emit_embed() {
    # emit_embed <函數名> <來源檔>
    printf '%s() {\n' "$1"
    printf "cat <<'__RPZ_EMBED__'\n"
    cat "$2"
    printf '__RPZ_EMBED__\n}\n\n'
}
emit_embed embed_utils_sh               "$SRC/utils.sh"
emit_embed embed_parse_rpz_sh           "$SRC/parse_rpz.sh"
emit_embed embed_generate_datagroup_sh  "$SRC/generate_datagroup.sh"

cat <<'LOGIC_PART2'
emit_new() {
    case "$1" in
        utils.sh)              embed_utils_sh ;;
        parse_rpz.sh)          embed_parse_rpz_sh ;;
        generate_datagroup.sh) embed_generate_datagroup_sh ;;
        *) die "emit_new: 未知檔案 $1" ;;
    esac
}

usage() {
    cat <<'USAGE'
用法:
  bash rpz_patch_sigpipe_v4.sh check                # 只檢查版本，不改檔案
  bash rpz_patch_sigpipe_v4.sh apply                # 備份後套用
  bash rpz_patch_sigpipe_v4.sh rollback <備份目錄>   # 從備份還原
USAGE
}

case "${1:-}" in
    check)    do_check ;;
    apply)    do_apply ;;
    rollback) shift; do_rollback "${1:-}" ;;
    *)        usage; exit 2 ;;
esac
LOGIC_PART2
} > "$WORK"

# ---- 置換 md5 佔位符 ----
sed -e "s/%ORIG_UTILS%/$OU/" -e "s/%ORIG_PARSE%/$OP/" -e "s/%ORIG_GEN%/$OG/" \
    -e "s/%NEW_UTILS%/$NU/"  -e "s/%NEW_PARSE%/$NP/"  -e "s/%NEW_GEN%/$NG/" \
    "$WORK" > "$OUT"
rm -f "$WORK"

# ---- 驗證 1: 語法 ----
bash -n "$OUT"
echo "PASS: bash -n"

# ---- 驗證 2: round-trip（抽出內嵌檔案，md5 必須等於 source）----
extract_block() {
    awk -v want="$1" '
        /^cat <<'\''__RPZ_EMBED__'\''$/ { n++; inb=1; next }
        /^__RPZ_EMBED__$/               { inb=0; next }
        inb && n == want                { print }
    ' "$OUT"
}
[ "$(extract_block 1 | md5)" = "$NU" ] || { echo "FAIL: round-trip utils.sh"; exit 1; }
[ "$(extract_block 2 | md5)" = "$NP" ] || { echo "FAIL: round-trip parse_rpz.sh"; exit 1; }
[ "$(extract_block 3 | md5)" = "$NG" ] || { echo "FAIL: round-trip generate_datagroup.sh"; exit 1; }
echo "PASS: round-trip x3"

# ---- 驗證 3: 佔位符不得殘留 ----
if grep -n '%ORIG_\|%NEW_' "$OUT"; then echo "FAIL: 佔位符殘留"; exit 1; fi
echo "PASS: 無佔位符殘留"

# ---- sha256 sidecar ----
H=$(shasum -a 256 "$OUT" | awk '{print $1}')
printf '%s  rpz_patch_sigpipe_v4.sh\n' "$H" > "$OUT.sha256"

# ---- 統計 ----
TOTAL=$(wc -l < "$OUT")
EMBED=$(( $(wc -l < "$SRC/utils.sh") + $(wc -l < "$SRC/parse_rpz.sh") + $(wc -l < "$SRC/generate_datagroup.sh") + 12 ))
echo "----------------------------------------"
echo "產出: $OUT"
echo "總行數: $TOTAL  內嵌: $EMBED  邏輯: $((TOTAL - EMBED))"
echo "SHA-256: $H"
