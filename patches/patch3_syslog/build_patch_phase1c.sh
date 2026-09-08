#!/bin/bash
# build_patch_phase1c.sh — 從 tracked source 組出 rpz_patch_phase1c_v1.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SRC=$REPO/scripts
OUT=$REPO/patches/patch3_syslog/rpz_patch_phase1c_v1.sh
WORK=$(mktemp "${TMPDIR:-/tmp}/p1cbuild.XXXXXX")

# ---- 部署前版本 md5（審核核定常數）----
# main.sh 的部署前版本 = Phase 1B 修正版（1C 只驗自己的三檔；v4 由 SOP 確認）。
# extract/update 的部署前版本 = GitHub baseline v1.2。
OM=d1e1f688d939a5a5e87282605d0e3eed
OE=62aeaf053b08f3411fe530f33555c414
OU=f8b038bc06df1c07050cd2922a91c5aa

# ---- 修正版 md5（防止 working tree 漂移）----
EXP_NM=9d8538a68480a1a0489058be6b1d6622
EXP_NE=fea7c2e29f5380ab22611f7b2cc97fbc
EXP_NU=67227cb39028dc2bf17b14ef9c871bc4
NM=$(md5 -q "$SRC/main.sh"); NE=$(md5 -q "$SRC/extract_rpz.sh"); NU=$(md5 -q "$SRC/update_datagroup.sh")
[ "$NM" = "$EXP_NM" ] || { echo "FAIL: main.sh md5=$NM"; exit 1; }
[ "$NE" = "$EXP_NE" ] || { echo "FAIL: extract_rpz.sh md5=$NE"; exit 1; }
[ "$NU" = "$EXP_NU" ] || { echo "FAIL: update_datagroup.sh md5=$NU"; exit 1; }
if grep -q '__RPZ_EMBED__' "$SRC/main.sh" "$SRC/extract_rpz.sh" "$SRC/update_datagroup.sh"; then
    echo "FAIL: 內嵌檔案含 delimiter"; exit 1
fi

{
cat <<'LOGIC_PART1'
#!/bin/bash
# =============================================================================
# rpz_patch_phase1c_v1.sh — RPZ Local Processor 系統事件 log 改走 syslog（Phase 1C）
#
# 需求來源:
#   客戶 TAC 需求（2026-09-03）: 腳本事件 log 原本以檔案直寫進 /var/log/ltm，
#   remote syslog（Splunk）收不到。改用 logger（facility local0）產生。
#   本機 ltm log 已在 LAB 驗證；遠端由設備既有的 remote syslog 設定轉送，
#   Splunk 收件由 canary 現場確認。時間格式為 F5 原生。
#
# 前提:
#   必須先套用 rpz_patch_sigpipe_v4 與 rpz_patch_phase1b_v1。
#   本 patch 的 check 只驗自己的三個檔案（main/extract/update），不讀取
#   v4 的三檔。main.sh 的「部署前版本」= Phase 1B 修正版，因此未套 1B
#   的設備 check 會拒絕；v4 是否已套用必須由 SOP 步驟確認。
#
# 變更（換三個檔案，共 17 處事件 log 改為 logger -t RPZLocal -p local0.*）:
#   main.sh               8 處（含修正兩處註解章節號的既有勘誤）
#   extract_rpz.sh        4 處
#   update_datagroup.sh   5 處
#   訊息文字不變；移除訊息內自帶的時間戳與主機名（syslog 會加 F5 原生格式）。
#
# 用法:
#   bash rpz_patch_phase1c_v1.sh check                # 只檢查版本，不改檔案
#   bash rpz_patch_phase1c_v1.sh apply                # 備份後套用
#   bash rpz_patch_phase1c_v1.sh rollback <備份目錄>   # 從備份還原
#
# 退出碼: 0=成功(含無需動作) 1=執行中錯誤 2=前置條件不符
#
# 安全設計（與 v4/1B 相同）:
#   1. 三檔 md5 整批核對，任一版本不明即拒絕，不改任何檔案。
#   2. 備份到 /var/tmp/rpz_patch1c_backup_<時間>/，附 md5sums.txt。
#   3. 同目錄暫存檔 + mv 原子取代；抽出內嵌檔先驗 md5。
#   4. rollback 只接受純部署前版本備份，且先預檢目前檔案
#      （版本不明或缺少即拒絕）。兩種拒絕都在改任何檔案之前。
# =============================================================================
set -euo pipefail

SCRIPTS_DIR="/config/snmp/RPZ_Local_Processor/scripts"
BACKUP_ROOT="/var/tmp"
FILES=(main.sh extract_rpz.sh update_datagroup.sh)

# md5: 部署前版本 -> Phase 1C 修正版
declare -A ORIG NEW
ORIG[main.sh]="%ORIG_MAIN%"
ORIG[extract_rpz.sh]="%ORIG_EXT%"
ORIG[update_datagroup.sh]="%ORIG_UPD%"
NEW[main.sh]="%NEW_MAIN%"
NEW[extract_rpz.sh]="%NEW_EXT%"
NEW[update_datagroup.sh]="%NEW_UPD%"

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
        orig)    echo "部署前版本" ;;
        new)     echo "已套用 Phase 1C" ;;
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
        die2 "有版本不明或缺少的檔案，禁止套用。main.sh 的部署前版本是 Phase 1B 修正版：請先確認 v4 與 1B 已套用。"
    elif (( n_new == ${#FILES[@]} )); then
        log "判定: 已套用 Phase 1C 修正。"
    elif (( n_orig == ${#FILES[@]} )); then
        log "判定: 全部是部署前版本，可以套用。"
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
        log "三個檔案都已是 Phase 1C 修正版，無需動作。"
        return 0
    fi
    guard_not_running

    ts=$(date '+%Y%m%d_%H%M%S')
    backup="${BACKUP_ROOT}/rpz_patch1c_backup_${ts}"
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
        for d in "${BACKUP_ROOT}"/rpz_patch1c_backup_*/; do
            if [[ -d "$d" ]]; then printf '    %s\n' "${d%/}"; fi
        done
        exit 2
    fi
    [[ -d "$backup" ]] || die2 "備份目錄不存在: ${backup}"
    [[ -f "${backup}/md5sums.txt" ]] || die2 "備份缺少 md5sums.txt: ${backup}"
    ( cd "$backup" && md5sum -c md5sums.txt >/dev/null 2>&1 ) \
        || die2 "備份檔案 md5 驗證失敗: ${backup}"

    # 只接受純部署前版本備份: 混合備份在改任何檔案前就拒絕
    for f in "${FILES[@]}"; do
        want=$(awk -v f="$f" '$2 == f {print $1}' "${backup}/md5sums.txt")
        [[ -n "$want" ]] || die2 "md5sums.txt 缺少 ${f} 的記錄"
        [[ "$want" == "${ORIG[$f]}" ]] \
            || die2 "備份不是純部署前版本: ${f}（${want}）。拒絕還原。請改用純部署前版本的備份目錄。"
    done

    # 目前檔案預檢: 只接受 orig/new。版本不明或缺少即拒絕。
    for f in "${FILES[@]}"; do
        s=$(state_of "$f")
        [[ "$s" == orig || "$s" == new ]] \
            || die2 "目前檔案版本不明或缺少: ${SCRIPTS_DIR}/${f}（$(state_zh "$s")）。rollback 拒絕覆寫，請先人工確認。"
    done
    guard_not_running

    # 還原順序與安裝相反
    for f in update_datagroup.sh extract_rpz.sh main.sh; do
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

# ===== 內嵌檔案（由 build_patch_phase1c.sh 自 tracked source 產生，勿手改）=====

LOGIC_PART1

emit_embed() {
    printf '%s() {\n' "$1"
    printf "cat <<'__RPZ_EMBED__'\n"
    cat "$2"
    printf '__RPZ_EMBED__\n}\n\n'
}
emit_embed embed_main_sh              "$SRC/main.sh"
emit_embed embed_extract_rpz_sh       "$SRC/extract_rpz.sh"
emit_embed embed_update_datagroup_sh  "$SRC/update_datagroup.sh"

cat <<'LOGIC_PART2'
emit_new() {
    case "$1" in
        main.sh)              embed_main_sh ;;
        extract_rpz.sh)       embed_extract_rpz_sh ;;
        update_datagroup.sh)  embed_update_datagroup_sh ;;
        *) die "emit_new: 未知檔案 $1" ;;
    esac
}

usage() {
    cat <<'USAGE'
用法:
  bash rpz_patch_phase1c_v1.sh check                # 只檢查版本，不改檔案
  bash rpz_patch_phase1c_v1.sh apply                # 備份後套用
  bash rpz_patch_phase1c_v1.sh rollback <備份目錄>   # 從備份還原
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

sed -e "s/%ORIG_MAIN%/$OM/" -e "s/%ORIG_EXT%/$OE/" -e "s/%ORIG_UPD%/$OU/" \
    -e "s/%NEW_MAIN%/$NM/"  -e "s/%NEW_EXT%/$NE/"  -e "s/%NEW_UPD%/$NU/" \
    "$WORK" > "$OUT"
rm -f "$WORK"

bash -n "$OUT"; echo "PASS: bash -n"
extract_block() {
    awk -v want="$1" '
        /^cat <<'\''__RPZ_EMBED__'\''$/ { n++; inb=1; next }
        /^__RPZ_EMBED__$/               { inb=0; next }
        inb && n == want                { print }
    ' "$OUT"
}
[ "$(extract_block 1 | md5)" = "$NM" ] || { echo "FAIL: round-trip main"; exit 1; }
[ "$(extract_block 2 | md5)" = "$NE" ] || { echo "FAIL: round-trip extract"; exit 1; }
[ "$(extract_block 3 | md5)" = "$NU" ] || { echo "FAIL: round-trip update"; exit 1; }
echo "PASS: round-trip x3"
if grep -n '%ORIG_\|%NEW_' "$OUT"; then echo "FAIL: 佔位符殘留"; exit 1; fi
echo "PASS: 無佔位符殘留"

H=$(shasum -a 256 "$OUT" | awk '{print $1}')
printf '%s  rpz_patch_phase1c_v1.sh\n' "$H" > "$OUT.sha256"
TOTAL=$(wc -l < "$OUT")
EMBED=$(( $(wc -l < "$SRC/main.sh") + $(wc -l < "$SRC/extract_rpz.sh") + $(wc -l < "$SRC/update_datagroup.sh") + 12 ))
echo "----------------------------------------"
echo "產出: $OUT"
echo "總行數: $TOTAL  內嵌: $EMBED  邏輯: $((TOTAL - EMBED))"
echo "SHA-256: $H"
