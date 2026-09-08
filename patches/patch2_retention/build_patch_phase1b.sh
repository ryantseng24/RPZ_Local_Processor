#!/bin/bash
# build_patch_phase1b.sh — 從 tracked source 組出 rpz_patch_phase1b_v1.sh
# 在 macOS 開發機執行。產出物在 repo 的 patches/patch2_retention/ 下。
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SRC=$REPO/scripts
OUT=$REPO/patches/patch2_retention/rpz_patch_phase1b_v1.sh
WORK=$(mktemp "${TMPDIR:-/tmp}/p1bbuild.XXXXXX")

# ---- 原版 main.sh md5: 審核核定常數 ----
# 來源: 審核核定的 GitHub baseline
#       （commit 27415940f03641ccd920e664797d79447bd91617, origin/main）。
# 這不是四台正式機的實測證據。每台正式機 apply 前必須先執行 check。
OM=0041c1d74e5b8514dea506608607b8c6

# ---- 修正版 main.sh md5（防止 working tree 漂移）----
EXP_NM=d1e1f688d939a5a5e87282605d0e3eed
NM=$(md5 -q "$SRC/main.sh")
[ "$NM" = "$EXP_NM" ] || { echo "FAIL: worktree main.sh md5=$NM != $EXP_NM"; exit 1; }

# delimiter 不得出現在內嵌檔案中
if grep -q '__RPZ_EMBED__' "$SRC/main.sh"; then
    echo "FAIL: 內嵌檔案含 __RPZ_EMBED__"; exit 1
fi

# ---- 組裝 ----
{
cat <<'LOGIC_PART1'
#!/bin/bash
# =============================================================================
# rpz_patch_phase1b_v1.sh — RPZ Local Processor 暫存檔保留策略 patch（Phase 1B）
#
# 前提:
#   先套用 rpz_patch_sigpipe_v4（4096/SIGPIPE 修正）。本 patch 與 v4 沒有
#   程式碼相依，可各自 rollback。Phase 1B 不是 4096 修正。
#
# 變更（只換一個檔案 main.sh）:
#   1. cleanup 的 find 範圍縮小到 raw/ 與 parsed/（-maxdepth 1）。
#      final/ 是 DataGroup 來源，從此不在任何刪除範圍內。
#   2. 新增數量上限: 每個檔案家族保留最新 24 個（RPZ_KEEP_COUNT 可調）。
#      與 8 天的天數上限並用，取先到者。
#   3. trap EXIT: 成功、NO_UPDATE、失敗路徑都會清理。流程停滯時
#      下一個 iCall tick（300 秒）就會清理，不再累積到磁碟告警。
#
# 用法:
#   bash rpz_patch_phase1b_v1.sh check                # 只檢查版本，不改檔案
#   bash rpz_patch_phase1b_v1.sh apply                # 備份後套用
#   bash rpz_patch_phase1b_v1.sh rollback <備份目錄>   # 從備份還原
#
# 退出碼:
#   0  成功（含「已套用，無需動作」）
#   1  執行中發生錯誤
#   2  前置條件不符（版本不明 / 備份不是純原版 / RPZ 程序執行中 / 參數錯誤）
#
# 安全設計（與 v4 相同）:
#   1. 先核對 md5。目標檔不是已知版本就中止，不改任何檔案。
#   2. 套用前備份到 /var/tmp/rpz_patch1b_backup_<時間>/，附 md5sums.txt。
#   3. 寫入用同目錄暫存檔 + mv，取代是原子動作。
#   4. rollback 只接受純原版 v1.2 備份，且先預檢目前檔案
#      （版本不明或缺少即拒絕）。兩種拒絕都在改任何檔案之前。
#   5. 內嵌檔案抽出後先核對 md5，通過才放進目標位置。
# =============================================================================
set -euo pipefail

SCRIPTS_DIR="/config/snmp/RPZ_Local_Processor/scripts"
BACKUP_ROOT="/var/tmp"
FILES=(main.sh)

# md5: v1.2 原版 -> 修正版
declare -A ORIG NEW
ORIG[main.sh]="%ORIG_MAIN%"
NEW[main.sh]="%NEW_MAIN%"

TMPF=""
trap 'rm -f "${TMPF:-}"' EXIT

log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die()  { log "錯誤: $*"; exit 1; }
die2() { log "中止: $*"; exit 2; }

md5of() { md5sum "$1" | awk '{print $1}'; }

state_of() {
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
    elif (( n_new == ${#FILES[@]} )); then
        log "判定: 已套用 Phase 1B 修正。"
    else
        log "判定: 原版 v1.2，可以套用。"
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
        log "已是 Phase 1B 修正版，無需動作。"
        return 0
    fi
    guard_not_running

    ts=$(date '+%Y%m%d_%H%M%S')
    backup="${BACKUP_ROOT}/rpz_patch1b_backup_${ts}"
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
    log "套用完成。md5 驗證通過。"
    log "還原指令: bash $0 rollback ${backup}"
}

do_rollback() {
    local backup="${1:-}" f want d s
    if [[ -z "$backup" ]]; then
        log "用法: bash $0 rollback <備份目錄>"
        log "現有備份目錄:"
        for d in "${BACKUP_ROOT}"/rpz_patch1b_backup_*/; do
            if [[ -d "$d" ]]; then printf '    %s\n' "${d%/}"; fi
        done
        exit 2
    fi
    [[ -d "$backup" ]] || die2 "備份目錄不存在: ${backup}"
    [[ -f "${backup}/md5sums.txt" ]] || die2 "備份缺少 md5sums.txt: ${backup}"
    ( cd "$backup" && md5sum -c md5sums.txt >/dev/null 2>&1 ) \
        || die2 "備份檔案 md5 驗證失敗: ${backup}"

    # 只接受純原版 v1.2 備份: 混合備份在改任何檔案前就拒絕
    for f in "${FILES[@]}"; do
        want=$(awk -v f="$f" '$2 == f {print $1}' "${backup}/md5sums.txt")
        [[ -n "$want" ]] || die2 "md5sums.txt 缺少 ${f} 的記錄"
        [[ "$want" == "${ORIG[$f]}" ]] \
            || die2 "備份不是純原版 v1.2: ${f}（${want}）。拒絕還原。請改用純原版備份目錄。"
    done

    # 目前檔案預檢: 只接受 orig/new。版本不明或缺少即拒絕，
    # 不覆寫未經確認的本機改動。
    for f in "${FILES[@]}"; do
        s=$(state_of "$f")
        [[ "$s" == orig || "$s" == new ]] \
            || die2 "目前檔案版本不明或缺少: ${SCRIPTS_DIR}/${f}（$(state_zh "$s")）。rollback 拒絕覆寫，請先人工確認。"
    done
    guard_not_running

    for f in "${FILES[@]}"; do
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

# ===== 內嵌檔案（由 build_patch_phase1b.sh 自 tracked source 產生，勿手改）=====

LOGIC_PART1

printf 'embed_main_sh() {\n'
printf "cat <<'__RPZ_EMBED__'\n"
cat "$SRC/main.sh"
printf '__RPZ_EMBED__\n}\n\n'

cat <<'LOGIC_PART2'
emit_new() {
    case "$1" in
        main.sh) embed_main_sh ;;
        *) die "emit_new: 未知檔案 $1" ;;
    esac
}

usage() {
    cat <<'USAGE'
用法:
  bash rpz_patch_phase1b_v1.sh check                # 只檢查版本，不改檔案
  bash rpz_patch_phase1b_v1.sh apply                # 備份後套用
  bash rpz_patch_phase1b_v1.sh rollback <備份目錄>   # 從備份還原
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
sed -e "s/%ORIG_MAIN%/$OM/" -e "s/%NEW_MAIN%/$NM/" "$WORK" > "$OUT"
rm -f "$WORK"

# ---- 驗證 ----
bash -n "$OUT"
echo "PASS: bash -n"

extract_block() {
    awk -v want="$1" '
        /^cat <<'\''__RPZ_EMBED__'\''$/ { n++; inb=1; next }
        /^__RPZ_EMBED__$/               { inb=0; next }
        inb && n == want                { print }
    ' "$OUT"
}
[ "$(extract_block 1 | md5)" = "$NM" ] || { echo "FAIL: round-trip main.sh"; exit 1; }
echo "PASS: round-trip"

if grep -n '%ORIG_\|%NEW_' "$OUT"; then echo "FAIL: 佔位符殘留"; exit 1; fi
echo "PASS: 無佔位符殘留"

H=$(shasum -a 256 "$OUT" | awk '{print $1}')
printf '%s  rpz_patch_phase1b_v1.sh\n' "$H" > "$OUT.sha256"

TOTAL=$(wc -l < "$OUT")
EMBED=$(( $(wc -l < "$SRC/main.sh") + 4 ))
echo "----------------------------------------"
echo "產出: $OUT"
echo "總行數: $TOTAL  內嵌: $EMBED  邏輯: $((TOTAL - EMBED))"
echo "SHA-256: $H"
