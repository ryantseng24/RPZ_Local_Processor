#!/bin/bash
# =============================================================================
# rpz_patch_sigpipe_v3.sh
#
# 修正 RPZ_Local_Processor 的 SIGPIPE 缺陷。
#
# 【問題】
#   scripts/parse_rpz.sh:227          ls -t raw/dnsxdump_*.out   | head -1
#   scripts/generate_datagroup.sh:65  ls -t parsed/${zone}_*.txt | head -1
#   scripts/generate_datagroup.sh:82  ls -t parsed/rpzip_*.txt   | head -1
#
#   `ls` 對 pipe 的 stdio write buffer 是 4096 bytes，輸出超過就需要多次
#   write()。head -1 取到第一行即結束並關閉 pipe，ls 後續的 write() 收到
#   SIGPIPE 而以 141 結束。pipefail 讓管線回傳 141，set -e 隨即終止腳本，
#   且不留任何錯誤訊息。這是時序競態，機率隨檔案數上升。
#
#   BIG-IP 17.1.3.1 實測 (真實 parse_rpz.sh，每組 30 次):
#     67 檔 / 4087B ->   0% 失敗
#     80 檔 / 4880B ->  17% 失敗
#    141 檔 / 8601B ->  80% 失敗
#    179 檔 /10919B ->  87% 失敗
#    300 檔 /18300B -> 100% 失敗
#
# 【修正】
#   utils.sh 新增 find_newest_file()，純 bash 迴圈取最新檔，不用管線。
#   三處呼叫改用它，並在找不到 artifact 時明確 die，不把「找不到」轉成
#   成功控制流。generate_datagroup.sh 改為 resolve-then-publish 兩階段，
#   避免前面的 zone 已發布、後面的 zone 缺檔才失敗造成部分發布。
#
# 【v3 相對 v2 的修正】依 CODE_REVIEW_PHASE1A_ROUND2_20260821.md
#   R2-01  cleanup 的 zone 名稱驗證、canonical parent 檢查、DATA_DIR 驗證、
#          duplicate zone 拒絕、deleted != planned 回傳非零
#   R2-02  rollback 中途失敗時全部切回修正版，並輸出每檔實際狀態
#   R2-05  REPS 必須是 1..1000 的整數，在建立 fixture 前驗證
#
# 【依 CODE_REVIEW_PHASE1A_ROUND3_REV2_20260821.md 的修正】
#   R3-03  cleanup 前要求 raw/parsed/final 是實體目錄（非 symlink）；
#          列舉階段若出現不安全的候選，整體回傳非零且不進入刪除階段
#   R3-08  recovery 之後的訊息依實際 detect_state 判定，不再誤報 mixed
#
# 【v2 相對 v1 的修正】依 CODE_REVIEW_20260821.md
#   CR-01  missing artifact 從 false success 改回 hard fail，且不部分發布
#   CR-02  selftest 加入真正的 assertion，失敗會回傳非零
#   CR-04  apply/rollback 改為 staging + 全檔驗證 + atomic rename + 反序
#          rollback + 失敗自動復原
#   CR-05  KEEP 參數驗證、精確 scope、-maxdepth 1、記錄實際刪除數、
#          偵測執行中的 processor
#
# 【這個 patch 不會做的事】
#   不碰 final/、不碰 DataGroup、不呼叫 tmsh、不重啟服務、不改 iCall。
#   iCall 每次執行都重新讀取腳本，所以不需要重啟，下一輪自動生效。
#
# 【用法】
#   ./rpz_patch_sigpipe_v3.sh check         檢查版本與現況 (唯讀，預設)
#   ./rpz_patch_sigpipe_v3.sh apply         套用修正
#   ./rpz_patch_sigpipe_v3.sh selftest      驗證修正有效 (隔離目錄，不碰 production)
#   ./rpz_patch_sigpipe_v3.sh rollback      還原到最近一次備份
#   ./rpz_patch_sigpipe_v3.sh cleanup-dry   列出建議刪除的舊檔 (不刪)
#   ./rpz_patch_sigpipe_v3.sh cleanup       實際刪除舊檔，保留最新 KEEP 個
#
# 【建議順序】
#   1. tmsh modify sys icall handler periodic rpz_processor_handler status inactive
#   2. 確認沒有執行中的 processor
#   3. check -> apply -> selftest
#   4. bash <INSTALL_DIR>/scripts/main.sh --force  並驗證
#   5. handler 改回 active
#   6. tmsh save sys config
#
# 【環境變數】
#   INSTALL_DIR   預設 /config/snmp/RPZ_Local_Processor
#   DATA_DIR      預設 /config/snmp/rpz_datagroups
#   BACKUP_ROOT   預設 /var/tmp
#   KEEP          cleanup 保留數，預設 60，必須是 1..10000 的整數
#   REPS          selftest 每個情境的重複次數，預設 10
#   RPZ_PATCH_FORCE=1  偵測到執行中的 processor 時仍繼續 (不建議)
# =============================================================================

set -uo pipefail

INSTALL_DIR="${INSTALL_DIR:-/config/snmp/RPZ_Local_Processor}"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
DATA_DIR="${DATA_DIR:-/config/snmp/rpz_datagroups}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/tmp}"
KEEP="${KEEP:-60}"
FORCE="${RPZ_PATCH_FORCE:-0}"

# 安裝順序: provider 先，consumers 後
FILES_INSTALL="utils.sh parse_rpz.sh generate_datagroup.sh"
# 還原順序: consumers 先，provider 後 (CR-04)
FILES_ROLLBACK="parse_rpz.sh generate_datagroup.sh utils.sh"

PATCH_VERSION="v3"

# 預期的 md5
MD5_ORIG_utils="3cab6cbca952f3780350e9882e5f7c11"
MD5_NEW_utils="b8294149dc978305e19bcd83fcb650e6"
MD5_ORIG_parse_rpz="bbe45c6f79b56922388d4af7aa6e7583"
MD5_NEW_parse_rpz="cefa71b6623632dd51c60a51cdf72196"
MD5_ORIG_generate_datagroup="35547d33ce109945d1ca17e8eb241e0a"
MD5_NEW_generate_datagroup="9599755a54db53652c070cd70ae92652"

c_ok()   { printf '  [ OK ] %s\n' "$*"; }
c_warn() { printf '  [WARN] %s\n' "$*"; }
c_err()  { printf '  [FAIL] %s\n' "$*"; }
hr()     { printf '%s\n' "--------------------------------------------------------------"; }

md5of() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }

expected_md5() {
    local key
    key=$(printf '%s' "$1" | sed 's/\.sh$//')
    case "$2:$key" in
        orig:utils) printf %s "3cab6cbca952f3780350e9882e5f7c11" ;;
        new:utils)  printf %s "b8294149dc978305e19bcd83fcb650e6" ;;
        orig:parse_rpz) printf %s "bbe45c6f79b56922388d4af7aa6e7583" ;;
        new:parse_rpz)  printf %s "cefa71b6623632dd51c60a51cdf72196" ;;
        orig:generate_datagroup) printf %s "35547d33ce109945d1ca17e8eb241e0a" ;;
        new:generate_datagroup)  printf %s "9599755a54db53652c070cd70ae92652" ;;
        *) printf %s "" ;;
    esac
}

# -----------------------------------------------------------------------------
# 狀態偵測: orig / new / unknown
# -----------------------------------------------------------------------------
detect_state() {
    local f cur all_orig=1 all_new=1
    for f in $FILES_INSTALL; do
        cur=$(md5of "$SCRIPTS_DIR/$f")
        [ "$cur" = "$(expected_md5 "$f" orig)" ] || all_orig=0
        [ "$cur" = "$(expected_md5 "$f" new)" ]  || all_new=0
    done
    if [ "$all_orig" -eq 1 ]; then printf orig
    elif [ "$all_new" -eq 1 ]; then printf new
    else printf unknown; fi
}

# -----------------------------------------------------------------------------
# 偵測執行中的 processor (CR-05)
# -----------------------------------------------------------------------------
running_procs() {
    pgrep -f "rpz_wrapper|${INSTALL_DIR}/scripts/main.sh" 2>/dev/null | tr '\n' ' '
}

require_quiescent() {
    local r
    r=$(running_procs)
    if [ -n "$r" ]; then
        c_err "偵測到執行中的 processor (PID: $r)"
        echo "       請先停用 iCall handler 並等待執行結束："
        echo "         tmsh modify sys icall handler periodic rpz_processor_handler status inactive"
        if [ "$FORCE" = "1" ]; then
            c_warn "RPZ_PATCH_FORCE=1，仍然繼續（不建議）"
            return 0
        fi
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# 原子寫入: 同目錄 temp + rename (CR-04)
# -----------------------------------------------------------------------------
install_file() {
    local src="$1" dest="$2" tmp
    tmp=$(mktemp "${dest}.rpzpatch.XXXXXX") || return 1
    if ! cat "$src" > "$tmp"; then rm -f "$tmp"; return 1; fi
    chmod --reference="$dest" "$tmp" 2>/dev/null || chmod 755 "$tmp"
    chown --reference="$dest" "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
    return 0
}

emit_to() {
    case "$1" in
        utils.sh)              emit_utils_sh              > "$2" ;;
        parse_rpz.sh)          emit_parse_rpz_sh          > "$2" ;;
        generate_datagroup.sh) emit_generate_datagroup_sh > "$2" ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# check
# -----------------------------------------------------------------------------
do_check() {
    echo "=============================================================="
    echo " rpz_patch_sigpipe_$PATCH_VERSION  check"
    echo " 主機: $(uname -n)   時間: $(date '+%F %T')"
    echo "=============================================================="
    echo
    echo "安裝目錄: $INSTALL_DIR"
    echo "資料目錄: $DATA_DIR"
    echo
    hr; echo " 1. 磁碟"; hr
    df -h "$DATA_DIR" 2>/dev/null | sed 's/^/  /'
    echo
    hr; echo " 2. 檔案累積 (每個 glob 的 ls 輸出超過 4096 bytes 就有失敗風險)"; hr
    local d cnt
    for d in raw parsed final; do
        cnt=$(ls -1 "$DATA_DIR/$d" 2>/dev/null | wc -l | tr -d ' ')
        printf '  %-8s 檔案數=%-6s 大小=%s\n' "$d" "$cnt" "$(du -sh "$DATA_DIR/$d" 2>/dev/null | cut -f1)"
    done
    echo
    local spec dd pp n b
    if ! validate_data_dir; then
        c_err "DATA_DIR 驗證失敗，略過檔案累積統計"
    elif ! build_cleanup_specs; then
        c_err "zone 清單驗證失敗，略過檔案累積統計。cleanup 也會拒絕執行。"
    else
    for spec in $(cleanup_specs); do
        dd="$DATA_DIR/${spec%%:*}"; pp="${spec##*:}"
        n=$(ls -1 $dd/$pp 2>/dev/null | wc -l | tr -d ' ')
        b=$(ls -t $dd/$pp 2>/dev/null | wc -c | tr -d ' ')
        if [ "${b:-0}" -gt 4096 ]; then
            printf '  %-8s %-20s %5s 檔  %8s bytes   超過 4096\n' "${spec%%:*}" "$pp" "$n" "$b"
        else
            printf '  %-8s %-20s %5s 檔  %8s bytes   OK\n' "${spec%%:*}" "$pp" "$n" "$b"
        fi
    done
    fi
    echo
    echo "  final/ (mtime 代表 step 4 完成的時間，不等於 step 5 已成功):"
    ls -l --time-style=long-iso "$DATA_DIR/final" 2>/dev/null | tail -n +2 | sed 's/^/    /'
    md5sum "$DATA_DIR/final"/*.txt 2>/dev/null | sed 's/^/    /'
    echo
    hr; echo " 3. 腳本版本"; hr
    local f cur
    for f in $FILES_INSTALL; do
        cur=$(md5of "$SCRIPTS_DIR/$f")
        printf '  %-24s %s' "$f" "${cur:-<找不到檔案>}"
        if   [ "$cur" = "$(expected_md5 "$f" orig)" ]; then echo "  <- 原版 v1.2 (待修正)"
        elif [ "$cur" = "$(expected_md5 "$f" new)" ];  then echo "  <- 已修正 ($PATCH_VERSION)"
        else echo "  <- 未知版本"; fi
    done
    echo
    hr; echo " 4. 執行狀態"; hr
    local r
    r=$(running_procs)
    if [ -n "$r" ]; then c_warn "有執行中的 processor (PID: $r)"; else c_ok "沒有執行中的 processor"; fi
    if command -v tmsh >/dev/null 2>&1; then
        tmsh list sys icall handler periodic 2>/dev/null | sed 's/^/    /' | head -12
    fi
    echo
    hr; echo " 5. 判定"; hr
    # 退出碼讓 SOP 能自動判斷，不必解析文字：
    #   0 = orig（可 apply）或 new（已修正）
    #   2 = unknown/mixed，必須停止
    local check_rc=0
    case "$(detect_state)" in
        orig)    c_warn "三支腳本都是原版 v1.2，尚未修正。可以執行 apply。（退出碼 0）" ;;
        new)     c_ok   "三支腳本都已是修正版 ($PATCH_VERSION)。不需要再 apply。（退出碼 0）" ;;
        unknown) c_err  "版本不一致或有未知版本。停下來，不要 apply，先人工確認。（退出碼 2）"
                 report_file_states
                 check_rc=2 ;;
    esac
    echo
    echo "  殘餘的 ls|head 寫法 (排除註解):"
    grep -n 'ls -t.*| *head -1' "$SCRIPTS_DIR"/*.sh 2>/dev/null \
        | grep -v ':[0-9]*:[[:space:]]*#' \
        | sed "s|$SCRIPTS_DIR/||; s/^/    /" \
        || echo "    無"
    echo
    echo "  註: check_soa.sh:33 也有 head -1，但前面兩層 grep 已把輸出收斂到 1 行，"
    echo "      遠低於 4096 bytes，實測不會失敗。本 patch 不動它。"
    return $check_rc
}

# -----------------------------------------------------------------------------
# apply (CR-04: staging -> 全檔驗證 -> 原子安裝 -> 失敗自動復原)
# -----------------------------------------------------------------------------
do_apply() {
    echo "=============================================================="
    echo " rpz_patch_sigpipe_$PATCH_VERSION  apply"
    echo " 主機: $(uname -n)   時間: $(date '+%F %T')"
    echo "=============================================================="
    echo
    local state
    state=$(detect_state)
    case "$state" in
        new)     c_ok "已經是修正版，不需要動作。"; return 0 ;;
        unknown) c_err "版本不符預期，拒絕套用。請先跑 check 並人工確認。"; return 1 ;;
    esac

    require_quiescent || return 1

    local f stage bdir cur exp
    stage=$(mktemp -d "$BACKUP_ROOT/rpzstage.XXXXXX") || { c_err "無法建立 staging 目錄"; return 1; }
    bdir=$(mktemp -d "$BACKUP_ROOT/rpz_patch_backup_$(date '+%Y%m%d_%H%M%S').XXXXXX") \
        || { c_err "無法建立備份目錄"; rm -rf "$stage"; return 1; }

    # --- 1. 產生 staging 並全檔驗證，通過才開始替換 ---
    for f in $FILES_INSTALL; do
        if ! emit_to "$f" "$stage/$f"; then
            c_err "產生 staging/$f 失敗"; rm -rf "$stage"; rmdir "$bdir" 2>/dev/null; return 1
        fi
        cur=$(md5of "$stage/$f"); exp=$(expected_md5 "$f" new)
        if [ "$cur" != "$exp" ]; then
            c_err "staging/$f md5 不符 (得到 ${cur}，預期 $exp)"
            rm -rf "$stage"; rmdir "$bdir" 2>/dev/null; return 1
        fi
        if ! bash -n "$stage/$f"; then
            c_err "staging/$f 語法檢查失敗"; rm -rf "$stage"; rmdir "$bdir" 2>/dev/null; return 1
        fi
    done
    if ! grep -q '^find_newest_file()' "$stage/utils.sh"; then
        c_err "staging/utils.sh 缺少 find_newest_file()"; rm -rf "$stage"; rmdir "$bdir" 2>/dev/null; return 1
    fi
    c_ok "staging 三檔已產生並通過 md5 + 語法 + helper 檢查"

    # --- 2. 備份，並驗證備份是完整原版 ---
    for f in $FILES_INSTALL; do
        if ! cp -p "$SCRIPTS_DIR/$f" "$bdir/$f"; then
            c_err "備份 $f 失敗"; rm -rf "$stage" "$bdir"; return 1
        fi
        if [ "$(md5of "$bdir/$f")" != "$(expected_md5 "$f" orig)" ]; then
            c_err "備份的 $f 不是完整原版，中止"; rm -rf "$stage" "$bdir"; return 1
        fi
    done
    c_ok "已備份到 $bdir 並驗證為完整原版"

    # --- 3. 原子安裝，任一失敗就全部復原 ---
    local installed=""
    for f in $FILES_INSTALL; do
        if ! install_file "$stage/$f" "$SCRIPTS_DIR/$f"; then
            c_err "安裝 $f 失敗，開始復原"
            restore_from "$bdir" "$installed" || c_err "復原過程也有失敗"
            report_file_states
            rm -rf "$stage"; return 1
        fi
        cur=$(md5of "$SCRIPTS_DIR/$f")
        if [ "$cur" != "$(expected_md5 "$f" new)" ]; then
            c_err "$f 安裝後 md5 不符，開始復原"
            restore_from "$bdir" "$installed $f" || c_err "復原過程也有失敗"
            report_file_states
            rm -rf "$stage"; return 1
        fi
        installed="$installed $f"
        c_ok "$f 已安裝"
    done

    # --- 4. 最終狀態驗證 ---
    if [ "$(detect_state)" != "new" ]; then
        c_err "安裝後整體狀態不是修正版，開始復原"
        restore_from "$bdir" "$FILES_INSTALL" || c_err "復原過程也有失敗"
        report_file_states
        rm -rf "$stage"; return 1
    fi

    # 備份指標寫入失敗不可靜默，否則 rollback 會找不到正確的備份 (R2-02)
    if printf '%s\n' "$bdir" > "$BACKUP_ROOT/.rpz_patch_last_backup.tmp.$$" \
        && mv -f "$BACKUP_ROOT/.rpz_patch_last_backup.tmp.$$" "$BACKUP_ROOT/.rpz_patch_last_backup"; then
        c_ok "備份指標已寫入 $BACKUP_ROOT/.rpz_patch_last_backup"
    else
        rm -f "$BACKUP_ROOT/.rpz_patch_last_backup.tmp.$$" 2>/dev/null
        c_err "無法寫入備份指標。腳本已是修正版，但 rollback 必須用 BACKUP_DIR=$bdir 明確指定。"
        rm -rf "$stage"
        return 1
    fi

    echo
    hr; echo " 變更內容"; hr
    for f in $FILES_INSTALL; do
        echo "--- $f ---"
        diff -u "$bdir/$f" "$SCRIPTS_DIR/$f" | tail -n +3 | sed 's/^/  /'
    done
    rm -rf "$stage"
    echo
    c_ok "套用完成。備份: $bdir"
    echo "  建議接著跑: $0 selftest"
    echo "  需要還原:   $0 rollback"
    return 0
}

# 印出三支檔案目前的實際 md5 與分類，供混合狀態時人工判斷
report_file_states() {
    local f cur label
    echo "  目前每支檔案的實際狀態:"
    for f in $FILES_INSTALL; do
        cur=$(md5of "$SCRIPTS_DIR/$f")
        if   [ "$cur" = "$(expected_md5 "$f" orig)" ]; then label="orig"
        elif [ "$cur" = "$(expected_md5 "$f" new)" ];  then label="new"
        else label="unknown"; fi
        printf '    %-24s %s  %s\n' "$f" "${cur:-<找不到>}" "$label"
    done
    printf '    整體判定: %s\n' "$(detect_state)"
}

# restore_from <備份目錄> <要還原的檔案清單>  依 rollback 順序。
# 彙總失敗並回傳非零，caller 必須檢查。
restore_from() {
    local bdir="$1" want="$2" f rc=0
    for f in $FILES_ROLLBACK; do
        case " $want " in *" $f "*) ;; *) continue ;; esac
        if install_file "$bdir/$f" "$SCRIPTS_DIR/$f"; then
            c_warn "已復原 $f"
        else
            c_err "復原 $f 失敗，請手動從 $bdir 複製"
            rc=1
        fi
    done
    return $rc
}

# 把三支全部切回修正版。rollback 中途失敗時用，避免留下 orig/new 混合狀態。
# 參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md R2-02。
recover_to_new() {
    local nstage="$1" f rc=0
    for f in $FILES_INSTALL; do
        if install_file "$nstage/$f" "$SCRIPTS_DIR/$f"; then
            c_warn "已切回修正版: $f"
        else
            c_err "切回修正版失敗: $f"
            rc=1
        fi
    done
    if [ "$(detect_state)" != "new" ]; then
        c_err "recovery 後整體狀態不是修正版"
        rc=1
    fi
    return $rc
}

# -----------------------------------------------------------------------------
# rollback (CR-04: 反序 + 原子 + 狀態驗證)
# -----------------------------------------------------------------------------
do_rollback() {
    echo "=============================================================="
    echo " rpz_patch_sigpipe_$PATCH_VERSION  rollback"
    echo " 主機: $(uname -n)   時間: $(date '+%F %T')"
    echo "=============================================================="
    echo
    local bdir f state
    if [ -n "${BACKUP_DIR:-}" ]; then
        bdir="$BACKUP_DIR"
    elif [ -f "$BACKUP_ROOT/.rpz_patch_last_backup" ]; then
        bdir=$(cat "$BACKUP_ROOT/.rpz_patch_last_backup")
    else
        bdir=$(ls -d "$BACKUP_ROOT"/rpz_patch_backup_* 2>/dev/null | sort | tail -1)
    fi
    [ -n "$bdir" ] && [ -d "$bdir" ] || { c_err "找不到備份目錄。可用 BACKUP_DIR=... 指定。"; return 1; }
    echo "  使用備份: $bdir"

    state=$(detect_state)
    if [ "$state" = "orig" ]; then c_ok "目前已是原版，不需要還原。"; return 0; fi
    if [ "$state" = "unknown" ] && [ "$FORCE" != "1" ]; then
        c_err "目前是未知版本。若確定要強制還原，請設 RPZ_PATCH_FORCE=1。"
        return 1
    fi

    for f in $FILES_ROLLBACK; do
        [ -f "$bdir/$f" ] || { c_err "備份缺少 ${f}，中止（不做任何變更）"; return 1; }
        if [ "$(md5of "$bdir/$f")" != "$(expected_md5 "$f" orig)" ]; then
            c_err "備份的 $f 不是完整原版，中止（不做任何變更）"; return 1
        fi
    done
    c_ok "備份三檔已驗證為完整原版"

    require_quiescent || return 1

    # 準備 recovery staging：中途失敗時要能把三支全部切回修正版，
    # 不可留下 orig/new 混合狀態 (R2-02)
    local nstage
    nstage=$(mktemp -d "$BACKUP_ROOT/rpzrecov.XXXXXX") || {
        c_err "無法建立 recovery staging 目錄，拒絕開始還原"; return 1; }
    for f in $FILES_INSTALL; do
        if ! emit_to "$f" "$nstage/$f"; then
            c_err "產生 recovery staging/$f 失敗，拒絕開始還原"; rm -rf "$nstage"; return 1
        fi
        if [ "$(md5of "$nstage/$f")" != "$(expected_md5 "$f" new)" ]; then
            c_err "recovery staging/$f md5 不符，拒絕開始還原"; rm -rf "$nstage"; return 1
        fi
        if ! bash -n "$nstage/$f"; then
            c_err "recovery staging/$f 語法檢查失敗，拒絕開始還原"; rm -rf "$nstage"; return 1
        fi
    done
    c_ok "recovery staging 已就緒，中途失敗時可切回修正版"

    # 反序: consumers 先，provider 後
    local rb_failed=0
    for f in $FILES_ROLLBACK; do
        if ! install_file "$bdir/$f" "$SCRIPTS_DIR/$f"; then
            c_err "還原 $f 失敗"
            rb_failed=1
        elif [ "$(md5of "$SCRIPTS_DIR/$f")" != "$(expected_md5 "$f" orig)" ]; then
            c_err "$f 還原後 md5 不是原版"
            rb_failed=1
        else
            c_ok "$f 已還原"
            continue
        fi
        # 中途失敗：把三支全部切回修正版
        echo
        c_warn "rollback 中途失敗，開始把三支全部切回修正版"
        recover_to_new "$nstage" || c_err "recovery 過程有失敗"
        # 訊息依實際狀態判定，不依 recover_to_new 的回傳值 (R3-08)
        case "$(detect_state)" in
            new)  c_warn "已全部切回修正版。rollback 未完成，系統維持在修正版。" ;;
            orig) c_warn "目前是完整原版狀態。rollback 實際上已完成，但過程有錯誤。" ;;
            *)    c_err  "系統處於混合或未知狀態，需要人工處理" ;;
        esac
        report_file_states
        rm -rf "$nstage"
        return 1
    done
    rm -rf "$nstage"

    if [ "$(detect_state)" != "orig" ]; then
        c_err "還原後整體狀態不是原版"
        report_file_states
        return 1
    fi
    echo
    c_ok "還原完成，三檔 md5 皆為原版 v1.2。"
    return 0
}

# -----------------------------------------------------------------------------
# selftest (CR-02: 真正的 assertion，失敗回傳非零)
# -----------------------------------------------------------------------------
do_selftest() { ( _selftest_body ); }

_selftest_body() {
    local reps="${REPS:-10}"
    local pass=0 fail=0
    validate_reps "$reps" || return 1
    st_ok()  { pass=$((pass+1)); printf '  [PASS] %s\n' "$*"; }
    st_bad() { fail=$((fail+1)); printf '  [FAIL] %s\n' "$*"; }

    echo "=============================================================="
    echo " rpz_patch_sigpipe_$PATCH_VERSION  selftest   reps=$reps"
    echo " 全程在隔離目錄，不讀寫 ${DATA_DIR}，不呼叫 tmsh"
    echo "=============================================================="
    echo

    local state
    state=$(detect_state)
    if [ "$state" != "new" ]; then
        c_err "目前狀態是 '$state'，不是修正版。selftest 拒絕執行。"
        return 1
    fi
    c_ok "版本狀態確認為修正版"

    # 刻意不用 local: EXIT trap 在函數返回後才執行，local 變數屆時已出範圍，
    # 配合 set -u 會變成 unbound variable 而導致清理失敗。
    # 本函數整體在 subshell 內執行，所以這個變數不會外洩到父 shell。
    BASE=$(mktemp -d "$BACKUP_ROOT/rpzst.XXXXXX") || { c_err "無法建立測試目錄"; return 1; }
    trap 'rm -rf "${BASE:-}"' EXIT

    local want sub OUT
    want=$(( 27 - ${#BASE} - 1 ))
    if [ "$want" -ge 1 ]; then sub=$(printf '%0*d' "$want" 0); else sub=o; fi
    OUT="$BASE/$sub"
    mkdir -p "$OUT" || { c_err "無法建立 $OUT"; return 1; }
    printf '  OUTPUT_DIR=%s (長度 %s，production 為 27)\n' "$OUT" "${#OUT}"

    local ZL="$BASE/zonelist.txt" SAMPLE="$BASE/sample.out"
    printf 'rpztw\nphishtw\n' > "$ZL" || { c_err "無法建立 zonelist"; return 1; }

    local i=0
    {
        printf 'rpztw.\t900\tIN\tSOA\tns admin 1 60 60 900 900\n'
        printf 'phishtw.\t900\tIN\tSOA\tns admin 1 60 60 900 900\n'
        while [ $i -lt 200 ]; do i=$((i+1))
            printf 's%dt%d.rpztw.\t60\tIN\tA\t10.0.0.1\n' "$i" "$i"
            printf '*.s%dw%d.rpztw.\t60\tIN\tA\t10.0.0.2\n' "$i" "$i"
        done
        i=0
        while [ $i -lt 150 ]; do i=$((i+1))
            printf 's%dp%d.phishtw.\t60\tIN\tA\t10.0.0.3\n' "$i" "$i"
        done
    } > "$SAMPLE"
    [ -s "$SAMPLE" ] || { c_err "無法建立測試樣本"; return 1; }
    c_ok "測試樣本已建立 ($(wc -l < "$SAMPLE" | tr -d ' ') 行)"
    echo

    _reset()  { rm -rf "$OUT/raw" "$OUT/parsed" "$OUT/final"; mkdir -p "$OUT/raw" "$OUT/parsed" "$OUT/final"; }
    _fillraw() {
        local n="$1" k=0 f
        while [ "$k" -lt "$n" ]; do k=$((k+1))
            f="$OUT/raw/$(printf 'dnsxdump_2026%04d_%06d.out' "$k" "$k")"
            : > "$f"; touch -t 202601010000 "$f"
        done
        cp "$SAMPLE" "$OUT/raw/dnsxdump_20990101_000001.out"
        touch "$OUT/raw/dnsxdump_20990101_000001.out"
    }
    _fillparsed() {
        local n="$1" skip="${2:-}" z k f
        for z in rpztw phishtw rpzip; do
            [ "$z" = "$skip" ] && continue
            k=0; while [ "$k" -lt "$n" ]; do k=$((k+1))
                f="$OUT/parsed/$(printf '%s_2026%04d_%06d.txt' "$z" "$k" "$k")"
                : > "$f"; touch -t 202601010000 "$f"
            done
        done
        [ "$skip" != rpztw ]   && printf '"a.example" := "1.1.1.1",\n' > "$OUT/parsed/rpztw_20990101_000001.txt"
        [ "$skip" != phishtw ] && printf '"b.example" := "2.2.2.2",\n' > "$OUT/parsed/phishtw_20990101_000001.txt"
        [ "$skip" != rpzip ]   && : > "$OUT/parsed/rpzip_20990101_000001.txt"
        return 0
    }
    _seedfinal() {
        printf '"old.example" := "9.9.9.9",\n' > "$OUT/final/rpztw.txt"
        printf '"old.example" := "9.9.9.9",\n' > "$OUT/final/phishtw.txt"
        : > "$OUT/final/rpzip.txt"
    }
    _sig()   { md5sum "$OUT/final"/*.txt 2>/dev/null | awk '{print $1}' | tr '\n' ' '; }
    _parse() { OUTPUT_DIR="$OUT" ZONELIST_FILE="$ZL" bash "$SCRIPTS_DIR/parse_rpz.sh" >"$BASE/p.log" 2>&1; }
    _gen()   { OUTPUT_DIR="$OUT" ZONELIST_FILE="$ZL" bash "$SCRIPTS_DIR/generate_datagroup.sh" >"$BASE/g.log" 2>&1; }

    echo "S1  正常 parse：exit 0、3 個 parsed、筆數符合樣本"
    _reset; _fillraw 3
    if _parse; then
        local n r p z
        n=$(ls -1 "$OUT/parsed" | wc -l | tr -d ' ')
        r=$(wc -l < "$OUT/parsed"/rpztw_*.txt | tr -d ' ')
        p=$(wc -l < "$OUT/parsed"/phishtw_*.txt | tr -d ' ')
        z=$(wc -l < "$OUT/parsed"/rpzip_*.txt | tr -d ' ')
        [ "$n" = 3 ]   && st_ok "3 個 parsed"    || st_bad "parsed 檔數=$n 預期 3"
        [ "$r" = 400 ] && st_ok "rpztw 400 筆"   || st_bad "rpztw=$r 預期 400"
        [ "$p" = 150 ] && st_ok "phishtw 150 筆" || st_bad "phishtw=$p 預期 150"
        [ "$z" = 0 ]   && st_ok "rpzip 0 筆"     || st_bad "rpzip=$z 預期 0"
    else
        st_bad "parse 退出碼非 0"
    fi

    echo "S2  取最新 raw"
    _reset; _fillraw 5
    if _parse && grep -q 'dnsxdump_20990101_000001.out' "$BASE/p.log"; then
        st_ok "選中 mtime 最新的檔案"
    else
        st_bad "沒有選中最新檔"
    fi

    echo "S3  raw 空：parse 必須非零且不產出 parsed"
    _reset
    if _parse; then st_bad "parse 退出碼 0，應為非零"
    else
        st_ok "parse 退出碼非零"
        [ "$(ls -1 "$OUT/parsed" | wc -l | tr -d ' ')" = 0 ] \
            && st_ok "parsed 無產出" || st_bad "parsed 有產出"
    fi

    echo "S4  正常 generate：exit 0、final 來自最新 parsed"
    _reset; _seedfinal; _fillparsed 3
    if _gen; then
        st_ok "generate 退出碼 0"
        [ "$(md5of "$OUT/final/rpztw.txt")" = "$(md5of "$OUT/parsed/rpztw_20990101_000001.txt")" ] \
            && st_ok "final/rpztw.txt 來自最新 parsed" || st_bad "final/rpztw.txt 不是最新 parsed"
    else
        st_bad "generate 退出碼非 0"
    fi

    echo "S5  parsed 全空：generate 必須非零、final 不變"
    _reset; _seedfinal; local b5; b5=$(_sig)
    if _gen; then st_bad "generate 退出碼 0，應為非零"; else st_ok "generate 退出碼非零"; fi
    [ "$b5" = "$(_sig)" ] && st_ok "final 未變動" || st_bad "final 被改動"

    echo "S6  只缺 phishtw：generate 必須非零、不得部分發布"
    _reset; _seedfinal; _fillparsed 3 phishtw; local b6; b6=$(_sig)
    if _gen; then st_bad "generate 退出碼 0，應為非零"; else st_ok "generate 退出碼非零"; fi
    [ "$b6" = "$(_sig)" ] && st_ok "final 完全未變動" || st_bad "final 發生部分發布"

    echo "S7  rpzip 存在但 0 bytes：generate 必須成功"
    _reset; _seedfinal; _fillparsed 3
    if _gen; then st_ok "generate 退出碼 0"; else st_bad "generate 退出碼非 0"; fi

    echo "S8  規模測試：raw 300 檔 × $reps 次，必須 0 失敗"
    _reset; _fillraw 300
    local f8=0 t=0 b8
    b8=$(ls -t "$OUT"/raw/dnsxdump_*.out | wc -c | tr -d ' ')
    while [ $t -lt "$reps" ]; do t=$((t+1))
        rm -rf "$OUT/parsed"; mkdir -p "$OUT/parsed"
        _parse || f8=$((f8+1))
    done
    [ "$f8" = 0 ] && st_ok "ls 輸出 ${b8}B，0/$reps 失敗" || st_bad "ls 輸出 ${b8}B，$f8/$reps 失敗"

    echo "S9  規模測試：parsed 每 zone 300 檔 × $reps 次，必須 0 失敗"
    _reset; _seedfinal; _fillparsed 300
    local f9=0 b9
    b9=$(ls -t "$OUT"/parsed/rpztw_*.txt | wc -c | tr -d ' ')
    t=0; while [ $t -lt "$reps" ]; do t=$((t+1)); _gen || f9=$((f9+1)); done
    [ "$f9" = 0 ] && st_ok "ls 輸出 ${b9}B，0/$reps 失敗" || st_bad "ls 輸出 ${b9}B，$f9/$reps 失敗"

    echo
    hr
    printf ' PASS=%s  FAIL=%s\n' "$pass" "$fail"
    hr
    if [ "$fail" -ne 0 ]; then
        c_err "selftest 失敗，共 $fail 項"
        return 1
    fi
    c_ok "selftest 全部通過"
    return 0
}

# -----------------------------------------------------------------------------
# cleanup (CR-05 + R2-01)
# -----------------------------------------------------------------------------

# zone 名稱驗證。zone 會被當成檔名前綴展開成 glob，所以必須嚴格限制字元，
# 否則 zonelist.txt 裡的 `../final/evil` 之類的值可以讓搜尋範圍離開 parsed/。
# 參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md R2-01。
validate_zone() {
    local z="$1"
    case "$z" in
        "")   c_err "zone 名稱為空"; return 1 ;;
        -*)   c_err "zone 名稱不可以 '-' 開頭（會被當成指令選項）: '$z'"; return 1 ;;
        .|..) c_err "zone 名稱不可為 '.' 或 '..': '$z'"; return 1 ;;
        */*)  c_err "zone 名稱不可含路徑分隔符: '$z'"; return 1 ;;
        *..*) c_err "zone 名稱不可含 '..': '$z'"; return 1 ;;
        *:*)  c_err "zone 名稱不可含 ':': '$z'"; return 1 ;;
    esac
    case "$z" in
        *"*"*|*"?"*|*"["*|*"]"*)
              c_err "zone 名稱不可含 glob 字元 * ? [ ]: '$z'"; return 1 ;;
    esac
    case "$z" in
        *[!A-Za-z0-9._-]*)
              c_err "zone 名稱只允許 A-Z a-z 0-9 . _ - ，實際值: '$z'"; return 1 ;;
    esac
    return 0
}

# 讀取並驗證 zone 清單。任一 zone 不合法或重複就整體失敗，不做部分處理。
get_validated_zones() {
    local zl="$INSTALL_DIR/config/zonelist.txt" z seen=" " out=""
    [ -f "$zl" ] || { c_err "找不到 zone 清單: $zl"; return 1; }
    while IFS= read -r z || [ -n "$z" ]; do
        case "$z" in ""|"#"*) continue ;; esac
        z="${z#"${z%%[![:space:]]*}"}"
        z="${z%"${z##*[![:space:]]}"}"
        [ -n "$z" ] || continue
        validate_zone "$z" || return 1
        case "$seen" in
            *" $z "*) c_err "zone 清單有重複項目: '$z'"; return 1 ;;
        esac
        seen="$seen$z "
        out="$out$z "
    done < "$zl"
    [ -n "$out" ] || { c_err "zone 清單為空: $zl"; return 1; }
    printf '%s' "$out"
    return 0
}

# DATA_DIR 安全驗證，並解析出 canonical 路徑供後續比對
DATA_DIR_CANON=""
validate_data_dir() {
    case "$DATA_DIR" in
        /)  c_err "DATA_DIR 不可為 /"; return 1 ;;
        /*) ;;
        *)  c_err "DATA_DIR 必須是絕對路徑: '$DATA_DIR'"; return 1 ;;
    esac
    case "$DATA_DIR" in
        *..*) c_err "DATA_DIR 不可含 '..': '$DATA_DIR'"; return 1 ;;
    esac
    [ -d "$DATA_DIR" ] || { c_err "DATA_DIR 不是目錄: '$DATA_DIR'"; return 1; }
    DATA_DIR_CANON=$(cd "$DATA_DIR" 2>/dev/null && pwd -P) || {
        c_err "無法解析 DATA_DIR 的 canonical 路徑: '$DATA_DIR'"; return 1; }
    [ "$DATA_DIR_CANON" != "/" ] || { c_err "DATA_DIR 的 canonical 路徑是 /，拒絕"; return 1; }
    return 0
}

# 刪除前的最後一道防線：victim 的 canonical parent 必須精確等於允許的目錄。
# 不依賴字串 prefix，因為 $DATA_DIR/parsed/../final/x 的字串不以 final/ 開頭。
safe_victim() {
    local v="$1" sub="$2" pd base
    pd=$(cd "$(dirname "$v")" 2>/dev/null && pwd -P) || return 1
    [ "$pd" = "$DATA_DIR_CANON/$sub" ] || return 1
    base=$(basename "$v")
    case "$base" in ""|.|..) return 1 ;; esac
    return 0
}

# REPS 必須是正整數，否則 REPS=0 會讓壓力測試完全不執行卻回報成功。
# 參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md R2-05。
validate_reps() {
    local r="$1"
    case "$r" in
        ''|*[!0-9]*) c_err "REPS 必須是正整數，目前是 '$r'"; return 1 ;;
    esac
    if [ "$r" -lt 1 ];    then c_err "REPS 必須 >= 1（目前 ${r}）。REPS=0 會讓壓力測試不執行。"; return 1; fi
    if [ "$r" -gt 1000 ]; then c_err "REPS 上限 1000（目前 ${r}）"; return 1; fi
    return 0
}

# cleanup 只支援固定的 production layout：raw / parsed / final 都是 DATA_DIR
# 底下的實體目錄。子目錄若是 symlink，safe_victim 會拒絕所有候選，造成
# 「什麼都沒刪但回報成功」。這裡直接在列舉前擋掉。
# 參見 CODE_REVIEW_PHASE1A_ROUND3_REV2_20260821.md 第 4.2 節 / R3-03。
validate_data_subdirs() {
    local sub d rc=0
    for sub in raw parsed final; do
        d="$DATA_DIR_CANON/$sub"
        if [ -L "$d" ]; then
            c_err "$d 是 symlink。cleanup 只支援實體目錄，拒絕執行。"
            rc=1
        elif [ ! -d "$d" ]; then
            c_err "$d 不存在或不是目錄"
            rc=1
        fi
    done
    return $rc
}

validate_keep() {
    case "$KEEP" in
        ''|*[!0-9]*) c_err "KEEP 必須是非負整數，目前是 '$KEEP'"; return 1 ;;
    esac
    if [ "$KEEP" -lt 1 ];     then c_err "KEEP 必須 >= 1（目前 ${KEEP}）。KEEP=0 會刪掉最新的檔案。"; return 1; fi
    if [ "$KEEP" -gt 10000 ]; then c_err "KEEP 上限 10000（目前 ${KEEP}）"; return 1; fi
    return 0
}

# 精確 scope: raw 的 dnsxdump、zonelist 裡每個 zone 的 parsed、rpzip。永不含 final。
# zone 已由 get_validated_zones 驗證，不可能含路徑分隔符或 glob 字元。
CLEANUP_SPECS=""
build_cleanup_specs() {
    local zones z
    zones=$(get_validated_zones) || return 1
    CLEANUP_SPECS="raw:dnsxdump_*.out"
    for z in $zones; do
        CLEANUP_SPECS="$CLEANUP_SPECS parsed:${z}_*.txt"
    done
    CLEANUP_SPECS="$CLEANUP_SPECS parsed:rpzip_*.txt"
    return 0
}

cleanup_specs() { printf '%s\n' $CLEANUP_SPECS; }

# 列舉過程若出現不安全的候選，寫進這個檔案，讓 do_cleanup 能偵測並整體失敗。
# 只印 stderr 不會傳回 caller，那正是 R3-03 的 false-success 成因。
CLEANUP_UNSAFE_LOG=""

cleanup_victims() {   # cleanup_victims <子目錄> <glob>
    local sub="$1" pat="$2" d="$DATA_DIR_CANON/$1" f
    [ -d "$d" ] || return 0
    local -a cand=()
    for f in "$d"/$pat; do
        [ -f "$f" ] || continue
        if ! safe_victim "$f" "$sub"; then
            printf '  [FAIL] 拒絕越界的檔案: %s\n' "$f" >&2
            [ -n "$CLEANUP_UNSAFE_LOG" ] && printf '%s\n' "$f" >> "$CLEANUP_UNSAFE_LOG"
            continue
        fi
        cand+=("$f")
    done
    [ "${#cand[@]}" -gt 0 ] || return 0
    # 依 mtime 新到舊排序，跳過最新 KEEP 個。tail 讀到 EOF，不會造成 SIGPIPE
    ls -t "${cand[@]}" 2>/dev/null | tail -n +$((KEEP + 1))
}

do_cleanup() {
    local mode="$1"
    echo "=============================================================="
    echo " rpz_patch_sigpipe_$PATCH_VERSION  cleanup ($mode)"
    echo " 主機: $(uname -n)   時間: $(date '+%F %T')"
    echo " 保留每個 glob 最新 $KEEP 個。final/ 永不在刪除範圍。"
    echo "=============================================================="
    echo
    validate_keep || return 1
    validate_data_dir || return 1
    validate_data_subdirs || {
        c_err "資料子目錄檢查失敗，拒絕執行 cleanup（未列舉任何檔案，未刪除任何東西）"
        return 1
    }
    CLEANUP_UNSAFE_LOG=$(mktemp "${BACKUP_ROOT}/rpzunsafe.XXXXXX") || {
        c_err "無法建立暫存檔，拒絕執行 cleanup"; return 1; }
    if ! build_cleanup_specs; then
        c_err "zone 清單驗證失敗，拒絕執行 cleanup（未列舉任何檔案，未刪除任何東西）"
        rm -f "$CLEANUP_UNSAFE_LOG"; CLEANUP_UNSAFE_LOG=""
        return 1
    fi
    echo "  zone 清單驗證通過，scope:"
    for spec in $(cleanup_specs); do printf '    %s\n' "$spec"; done
    echo

    if [ "$mode" = real ]; then
        require_quiescent || return 1
    fi

    df -h "$DATA_DIR" 2>/dev/null | sed 's/^/  /'
    echo
    echo "  final/ 刪除前的 checksum:"
    md5sum "$DATA_DIR/final"/*.txt 2>/dev/null | sed 's/^/    /'
    local sig_before
    sig_before=$(md5sum "$DATA_DIR/final"/*.txt 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
    echo

    local spec d pat n total=0
    for spec in $(cleanup_specs); do
        d="${spec%%:*}"; pat="${spec##*:}"
        n=$(cleanup_victims "$d" "$pat" | wc -l | tr -d ' ')
        printf '  %-8s %-20s 待刪 %-6s / 共 %s\n' "$d" "$pat" "$n" \
            "$(ls -1 "$DATA_DIR/$d"/$pat 2>/dev/null | wc -l | tr -d ' ')"
        total=$((total + n))
    done
    echo

    # 列舉階段若出現任何不安全的候選，整體失敗，不進入刪除階段 (R3-03)
    if [ -s "$CLEANUP_UNSAFE_LOG" ]; then
        c_err "列舉階段發現 $(wc -l < "$CLEANUP_UNSAFE_LOG" | tr -d ' ') 個不安全的候選，拒絕繼續"
        sed 's/^/    /' "$CLEANUP_UNSAFE_LOG"
        rm -f "$CLEANUP_UNSAFE_LOG"; CLEANUP_UNSAFE_LOG=""
        return 1
    fi

    if [ "$mode" = dry ]; then
        echo "  這是預覽，沒有刪除任何東西。合計待刪 $total 個。"
        echo "  前 5 個會被刪的 raw 檔案:"
        cleanup_victims raw 'dnsxdump_*.out' | head -5 | sed 's/^/    /'
        echo "  確認後執行: $0 cleanup"
        rm -f "$CLEANUP_UNSAFE_LOG"; CLEANUP_UNSAFE_LOG=""
        return 0
    fi

    if [ "$total" -eq 0 ]; then
        c_ok "沒有需要刪除的檔案。"
        rm -f "$CLEANUP_UNSAFE_LOG"; CLEANUP_UNSAFE_LOG=""
        return 0
    fi

    local deleted=0 errors=0 victim
    for spec in $(cleanup_specs); do
        d="${spec%%:*}"; pat="${spec##*:}"
        while IFS= read -r victim; do
            [ -n "$victim" ] || continue
            # 第二次 canonical 檢查。列舉時已檢查過，這裡是刪除前的最後一道。
            if ! safe_victim "$victim" "$d"; then
                c_err "拒絕刪除越界的檔案: $victim"; errors=$((errors+1)); continue
            fi
            [ -f "$victim" ] || continue
            if rm -f "$victim"; then deleted=$((deleted+1)); else c_err "刪除失敗: $victim"; errors=$((errors+1)); fi
        done <<EOF_VICTIMS
$(cleanup_victims "$d" "$pat")
EOF_VICTIMS
    done

    echo "  預計刪除 $total 個，實際刪除 $deleted 個，錯誤 $errors 個"
    if [ "$deleted" -ne "$total" ]; then
        c_err "實際刪除數與預計不符（$deleted != ${total}）。可能有檔案在列舉後被其他程序刪除或新增，或被 canonical 檢查攔下。"
        errors=$((errors+1))
    fi
    echo
    df -h "$DATA_DIR" 2>/dev/null | sed 's/^/  /'
    echo
    echo "  final/ 刪除後的 checksum:"
    md5sum "$DATA_DIR/final"/*.txt 2>/dev/null | sed 's/^/    /'
    local sig_after
    sig_after=$(md5sum "$DATA_DIR/final"/*.txt 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
    if [ "$sig_before" = "$sig_after" ]; then c_ok "final/ checksum 未變動"
    else c_err "final/ checksum 變動了！請立即檢查"; errors=$((errors+1)); fi
    echo
    for spec in $(cleanup_specs); do
        d="${spec%%:*}"; pat="${spec##*:}"
        local b
        b=$(ls -t "$DATA_DIR/$d"/$pat 2>/dev/null | wc -c | tr -d ' ')
        printf '  %-8s %-20s 剩 %-6s 檔  ls 輸出 %s bytes\n' "$d" "$pat" \
            "$(ls -1 "$DATA_DIR/$d"/$pat 2>/dev/null | wc -l | tr -d ' ')" "$b"
    done
    echo
    if [ -s "$CLEANUP_UNSAFE_LOG" ]; then
        c_err "刪除階段又出現不安全的候選"
        errors=$((errors + 1))
    fi
    rm -f "$CLEANUP_UNSAFE_LOG"; CLEANUP_UNSAFE_LOG=""
    if [ "$errors" -ne 0 ]; then c_err "cleanup 有 $errors 個錯誤"; return 1; fi
    c_ok "cleanup 完成"
    return 0
}

# -----------------------------------------------------------------------------
main() {
    local f
    for f in $FILES_INSTALL; do
        [ -f "$SCRIPTS_DIR/$f" ] || { c_err "找不到 $SCRIPTS_DIR/${f}，請確認 INSTALL_DIR"; exit 1; }
    done
    case "${1:-check}" in
        check)       do_check ;;
        apply)       do_apply ;;
        selftest)    do_selftest ;;
        rollback)    do_rollback ;;
        cleanup-dry) do_cleanup dry ;;
        cleanup)     do_cleanup real ;;
        *) sed -n '/^# 【用法】/,/^# =====/p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
    esac
}

emit_utils_sh() {
cat <<'__RPZ_EMBED_UTILS_SH__'
#!/bin/bash
# =============================================================================
# utils.sh - 共用工具函數庫
# =============================================================================

# 顏色定義（在非互動環境中自動禁用，避免 ANSI 碼導致 iCall 誤報錯誤）
if [[ -t 2 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    # 有 TTY 且未禁用顏色
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[1;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_RESET='\033[0m'
else
    # 無 TTY（如 iCall 環境）或明確禁用顏色
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_RESET=''
fi

# 日誌等級
readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_WARN=2
readonly LOG_ERROR=3

# 預設日誌等級
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# =============================================================================
# 日誌函數
# =============================================================================

log_debug() {
    [[ $LOG_LEVEL -le $LOG_DEBUG ]] && echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $*" >&2 || true
}

log_info() {
    [[ $LOG_LEVEL -le $LOG_INFO ]] && echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*" >&2 || true
}

log_warn() {
    [[ $LOG_LEVEL -le $LOG_WARN ]] && echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2 || true
}

log_error() {
    [[ $LOG_LEVEL -le $LOG_ERROR ]] && echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2 || true
}

# =============================================================================
# 錯誤處理
# =============================================================================

die() {
    log_error "$*"
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || die "必要指令不存在: $1"
}

# =============================================================================
# 檔案操作
# =============================================================================

ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p "$dir" || die "無法建立目錄: $dir"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.$(date +%Y%m%d_%H%M%S).bak"
        cp "$file" "$backup" || log_warn "無法備份檔案: $file"
        log_debug "已備份: $file -> $backup"
    fi
}

# =============================================================================
# 配置讀取
# =============================================================================

read_config() {
    local config_file="$1"
    [[ -f "$config_file" ]] || die "配置檔案不存在: $config_file"

    # 讀取非註解、非空白行
    grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$'
}

# =============================================================================
# 時間戳記
# =============================================================================

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

timestamp_compact() {
    date '+%Y%m%d_%H%M%S'
}

# =============================================================================
# 效能測量
# =============================================================================

timer_start() {
    TIMER_START=$(date +%s)
}

timer_end() {
    local end=$(date +%s)
    local elapsed=$((end - TIMER_START))
    echo "$elapsed"
}

timer_format() {
    local seconds="$1"
    printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

# =============================================================================
# 資料驗證
# =============================================================================

is_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_valid_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

# =============================================================================
# 安全函數
# =============================================================================

sanitize_input() {
    local input="$1"
    # 移除潛在危險字元
    echo "$input" | tr -d ';&|$`<>()'
}

# =============================================================================
# 取得符合 glob 的最新檔案 (依 mtime)
# =============================================================================
# 刻意不使用 `ls -t <glob> | head -1`。在 set -o pipefail 下，ls 對 pipe 的
# stdio write buffer 是 4096 bytes，輸出超過就需要多次 write()。head -1 取到
# 第一行即結束並關閉 pipe，ls 後續的 write() 收到 SIGPIPE 而以 141 結束。
# pipefail 讓管線回傳 141，set -e 隨即終止腳本，且不留任何錯誤訊息。
# 這是時序競態，機率隨檔案數上升。
# BIG-IP 17.1.3.1 實測 (真實 parse_rpz.sh，每組 30 次):
#   67 檔/4087B 0%、80 檔/4880B 17%、141 檔/8601B 80%、179 檔/10919B 87%
#
# 用法:
#   if ! newest=$(find_newest_file "$dir"/glob_*.txt); then
#       die "找不到檔案"
#   fi
#
# 回傳 0 並輸出路徑；完全沒有符合的檔案時回傳 1 且不輸出。
# 呼叫端必須明確處理回傳 1 的情況，不要用 `|| var=""` 把「找不到」
# 轉成成功控制流 (參見 CODE_REVIEW_20260821.md CR-01)。

find_newest_file() {
    local newest="" f
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        if [[ -z "$newest" || "$f" -nt "$newest" ]]; then
            newest="$f"
        fi
    done
    [[ -n "$newest" ]] || return 1
    printf '%s\n' "$newest"
}

# =============================================================================
# 匯出函數 (如果被 source)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # 被 source 時匯出所有函數
    export -f log_debug log_info log_warn log_error
    export -f die check_command
    export -f ensure_dir backup_file read_config find_newest_file
    export -f timestamp timestamp_compact
    export -f timer_start timer_end timer_format
    export -f is_valid_ip is_valid_domain sanitize_input
fi
__RPZ_EMBED_UTILS_SH__
}

emit_parse_rpz_sh() {
cat <<'__RPZ_EMBED_PARSE_RPZ_SH__'
#!/bin/bash
# =============================================================================
# parse_rpz.sh - 解析 RPZ 記錄 (動態 Zone 支援)
# =============================================================================
# 功能:
# 1. 從 zonelist.txt 讀取要處理的 zones
# 2. 解析 FQDN 類型 RPZ 記錄 (A record) -> key := value 格式
# 3. 解析 IP 類型 RPZ 記錄 (CNAME with rpz-ip) -> network 格式
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
RAW_DATA_DIR="${OUTPUT_DIR}/raw"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
ZONELIST_FILE="${ZONELIST_FILE:-${PROJECT_ROOT}/config/zonelist.txt}"

# =============================================================================
# 讀取 Zone 清單
# =============================================================================

get_zone_list() {
    if [[ ! -f "$ZONELIST_FILE" ]]; then
        die "Zone 清單檔案不存在: $ZONELIST_FILE"
    fi

    # 讀取非註解、非空白行
    grep -v '^#' "$ZONELIST_FILE" | grep -v '^[[:space:]]*$' | xargs
}

# =============================================================================
# 將 zone 名稱轉換為正則表達式安全格式
# =============================================================================

escape_zone_for_regex() {
    local zone="$1"
    # 將 . 轉義為 \.
    echo "$zone" | sed 's/\./\\./g'
}

# =============================================================================
# AWK 動態解析邏輯
# =============================================================================
# 輸出格式:
# - FQDN: "domain" := "landing_ip",
# - IP:   network ip/mask,
# =============================================================================

parse_rpz_records() {
    local input_file="$1"
    local output_dir="$2"
    local timestamp="$3"
    shift 3
    local zones=("$@")

    log_info "解析 RPZ 記錄: $(basename "$input_file")"
    log_info "處理 Zones: ${zones[*]}"

    # 建立 AWK zones 參數 (用 | 分隔，包含原始名稱和 regex 安全格式)
    # 格式: zone1|escaped1 zone2|escaped2 ...
    local zone_list=""
    for zone in "${zones[@]}"; do
        local escaped_zone
        escaped_zone=$(escape_zone_for_regex "$zone")
        zone_list="${zone_list}${zone}|${escaped_zone} "
    done

    awk -v zone_list="$zone_list" \
        -v output_dir="$output_dir" \
        -v timestamp="$timestamp" '
    BEGIN {
        # 解析 zone 清單
        n = split(zone_list, zone_entries, " ")
        for (i = 1; i <= n; i++) {
            if (zone_entries[i] != "") {
                # 分割 zone|escaped_zone
                split(zone_entries[i], parts, "|")
                zone_name = parts[1]
                zone_escaped = parts[2]
                zone_names[zone_name] = zone_escaped
            }
        }
    }
    {
        # 僅處理 IN class 記錄
        if ($3 == "IN") {

            # ===== 處理 FQDN 類型 (A 記錄) =====
            if ($4 == "A") {
                # 遍歷所有 zones
                for (zone in zone_names) {
                    zone_escaped = zone_names[zone]
                    zone_pattern = "\\." zone_escaped "\\.$"

                    if ($1 ~ zone_pattern) {
                        # 移除 zone 後綴 (使用 escaped 版本)
                        sub("\\." zone_escaped "\\.$", "", $1)

                        # 構建 key (zone + SUBSEP + domain)
                        if (substr($1, 1, 2) == "*.") {
                            # 萬用字元記錄 - 加前綴點
                            domain = substr($1, 3)
                            key = zone SUBSEP "." domain
                        } else {
                            # 精確記錄
                            key = zone SUBSEP $1
                        }
                        zone_data[key] = $5
                        break
                    }
                }
            }

            # ===== 處理 IP 類型 (rpz-ip CNAME) =====
            else if ($4 == "CNAME") {
                for (zone in zone_names) {
                    zone_escaped = zone_names[zone]
                    ip_pattern = "rpz-ip\\." zone_escaped "\\."

                    if (index($1, "rpz-ip." zone ".") > 0) {
                        # 移除 rpz-ip.zone 後綴
                        sub("\\.rpz-ip\\." zone_escaped "\\.$", "", $1)

                        # 分割為 IP 部分
                        split($1, ip_parts, ".")

                        # 至少需要 5 個部分 (netmask + 4 個 IP octets)
                        if (length(ip_parts) >= 5) {
                            netmask = ip_parts[1]
                            reversed_ip = ip_parts[5] "." ip_parts[4] "." ip_parts[3] "." ip_parts[2]
                            iplist[reversed_ip "/" netmask] = 1
                        }
                        break
                    }
                }
            }
        }
    }
    END {
        # 輸出各 zone 的 FQDN (key := value 格式)
        for (zone in zone_names) {
            output_file = output_dir "/" zone "_" timestamp ".txt"
            count = 0

            # 遍歷所有 zone_data，找出屬於此 zone 的記錄
            for (key in zone_data) {
                # 分割 key 為 zone 和 domain
                split(key, key_parts, SUBSEP)
                if (key_parts[1] == zone) {
                    domain = key_parts[2]
                    ip = zone_data[key]
                    print "\"" domain "\" := \"" ip "\"," > output_file
                    count++
                }
            }

            if (count > 0) {
                printf "ZONE_COUNT:%s=%d\n", zone, count > "/dev/stderr"
            }
        }

        # 輸出 IP 網段 (network 格式)
        ip_output_file = output_dir "/rpzip_" timestamp ".txt"
        ip_count = 0
        for (n in iplist) {
            print "network " n "," > ip_output_file
            ip_count++
        }
        if (ip_count > 0) {
            printf "ZONE_COUNT:rpzip=%d\n", ip_count > "/dev/stderr"
        }
    }' "$input_file" 2>&1 | while read -r line; do
        if [[ "$line" =~ ^ZONE_COUNT:(.+)=([0-9]+)$ ]]; then
            local zname="${BASH_REMATCH[1]}"
            local zcount="${BASH_REMATCH[2]}"
            log_info "  - $zname: $zcount 筆"
        fi
    done

    # 確保所有輸出檔案都存在（即使為空）
    for zone in "${zones[@]}"; do
        touch "${output_dir}/${zone}_${timestamp}.txt"
    done
    touch "${output_dir}/rpzip_${timestamp}.txt"

    log_info "解析完成"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local timestamp_compact=$(timestamp_compact)

    log_info "=== 開始解析 RPZ 記錄 ==="

    # 讀取 zone 清單
    local zone_list_str
    zone_list_str=$(get_zone_list)

    if [[ -z "$zone_list_str" ]]; then
        die "Zone 清單為空"
    fi

    # 轉換為陣列
    read -ra ZONES <<< "$zone_list_str"
    log_info "載入 ${#ZONES[@]} 個 Zones: ${ZONES[*]}"

    # 建立輸出目錄
    ensure_dir "$PARSED_DATA_DIR"

    # 檢查是否有 dnsxdump 輸出
    local dnsxdump_file
    if [[ -n "${DNSXDUMP_FILE:-}" && -f "$DNSXDUMP_FILE" ]]; then
        dnsxdump_file="$DNSXDUMP_FILE"
    else
        # 尋找最新的 dnsxdump 檔案
        # 不用 ls|head，見 utils.sh 的 find_newest_file
        if ! dnsxdump_file=$(find_newest_file "${RAW_DATA_DIR}"/dnsxdump_*.out); then
            die "找不到 dnsxdump 輸出檔案: ${RAW_DATA_DIR}/dnsxdump_*.out"
        fi
        [[ -f "$dnsxdump_file" ]] || die "dnsxdump 輸出檔案不存在: $dnsxdump_file"
    fi

    log_info "使用 dnsxdump 檔案: $dnsxdump_file"

    # 執行 AWK 解析
    parse_rpz_records "$dnsxdump_file" "$PARSED_DATA_DIR" "$timestamp_compact" "${ZONES[@]}"

    log_info "=== 解析完成 ==="
    log_info "輸出目錄: $PARSED_DATA_DIR"

    # 設定全域變數供後續使用
    export PARSED_TIMESTAMP="$timestamp_compact"
    export PARSED_ZONES="${ZONES[*]}"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
__RPZ_EMBED_PARSE_RPZ_SH__
}

emit_generate_datagroup_sh() {
cat <<'__RPZ_EMBED_GENERATE_DATAGROUP_SH__'
#!/bin/bash
# =============================================================================
# generate_datagroup.sh - 產生 F5 External DataGroup 檔案 (動態 Zone 支援)
# =============================================================================
# 功能: 將解析後的檔案整理到最終輸出目錄
# 輸出格式已由 parse_rpz.sh 產生，此腳本僅負責檔案管理
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
PARSED_DATA_DIR="${OUTPUT_DIR}/parsed"
FINAL_OUTPUT_DIR="${OUTPUT_DIR}/final"
ZONELIST_FILE="${ZONELIST_FILE:-${PROJECT_ROOT}/config/zonelist.txt}"

# =============================================================================
# 讀取 Zone 清單
# =============================================================================

get_zone_list() {
    if [[ ! -f "$ZONELIST_FILE" ]]; then
        die "Zone 清單檔案不存在: $ZONELIST_FILE"
    fi

    # 讀取非註解、非空白行
    grep -v '^#' "$ZONELIST_FILE" | grep -v '^[[:space:]]*$' | xargs
}

# =============================================================================
# 整理 DataGroup 檔案到最終目錄
# =============================================================================

prepare_final_datagroups() {
    log_info "整理 DataGroup 檔案到最終目錄"

    # 建立最終輸出目錄
    ensure_dir "$FINAL_OUTPUT_DIR"

    # 讀取 zone 清單
    local zone_list_str
    zone_list_str=$(get_zone_list)

    if [[ -z "$zone_list_str" ]]; then
        die "Zone 清單為空"
    fi

    # 轉換為陣列
    local zones
    read -ra zones <<< "$zone_list_str"
    log_info "處理 ${#zones[@]} 個 Zones: ${zones[*]}"

    # -------------------------------------------------------------------------
    # 第一階段：解析所有來源檔案，全部確認齊全才進入發布階段。
    #
    # 找不到 parsed artifact 必須硬失敗。原版靠 ls 的非零退出碼 + pipefail
    # 達到這個效果；改用 find_newest_file 後必須明確 die，不可讓 missing
    # artifact 落入 touch final 的成功分支。
    # 兩階段的目的是避免「前面的 zone 已經 cp 完、後面的 zone 缺檔才 die」
    # 造成 final/ 部分發布。
    # 參見 CODE_REVIEW_20260821.md CR-01。
    # -------------------------------------------------------------------------
    local -a src_zone=() src_file=()
    local zone parsed_file
    for zone in "${zones[@]}"; do
        if ! parsed_file=$(find_newest_file "${PARSED_DATA_DIR}/${zone}_"*.txt); then
            die "找不到 ${zone} 的解析檔案: ${PARSED_DATA_DIR}/${zone}_*.txt"
        fi
        [[ -f "$parsed_file" ]] || die "${zone} 的解析檔案不存在: $parsed_file"

        if [[ ! -s "$parsed_file" ]]; then
            log_warn "${zone} 的解析檔案為 0 bytes: $parsed_file"
        fi

        src_zone+=("$zone")
        src_file+=("$parsed_file")
    done

    # rpzip 的 artifact 必須存在，但允許內容為空 (目前來源沒有 IP 類型記錄)
    local ip_file
    if ! ip_file=$(find_newest_file "${PARSED_DATA_DIR}"/rpzip_*.txt); then
        die "找不到 rpzip 的解析檔案: ${PARSED_DATA_DIR}/rpzip_*.txt"
    fi
    [[ -f "$ip_file" ]] || die "rpzip 的解析檔案不存在: $ip_file"

    # -------------------------------------------------------------------------
    # 第二階段：發布
    #
    # 注意：這裡【不是】完整的 publish transaction。第一階段確保「缺 artifact
    # 時不會部分發布」，但發布階段仍是逐一 cp/touch 正式檔案，若某次 cp 中途
    # 失敗，前面已寫入的 final 檔案不會回復。
    # 完整的原子發布（temp + rename、run manifest、資料完整性門檻）屬於
    # CODE_REVIEW_20260821.md 的 CR-10，尚未實作。
    # 參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md 第 9.1 節。
    # -------------------------------------------------------------------------
    local count=0 i=0 record_count
    while [[ $i -lt ${#src_zone[@]} ]]; do
        cp "${src_file[$i]}" "${FINAL_OUTPUT_DIR}/${src_zone[$i]}.txt"
        record_count=$(wc -l < "${src_file[$i]}")
        log_info "✓ ${src_zone[$i]} DataGroup: ${FINAL_OUTPUT_DIR}/${src_zone[$i]}.txt ($record_count 筆)"
        count=$((count + 1))
        i=$((i + 1))
    done

    if [[ -s "$ip_file" ]]; then
        cp "$ip_file" "${FINAL_OUTPUT_DIR}/rpzip.txt"
        local ip_count
        ip_count=$(wc -l < "$ip_file")
        log_info "✓ rpzip DataGroup: ${FINAL_OUTPUT_DIR}/rpzip.txt ($ip_count 筆)"
        count=$((count + 1))
    else
        touch "${FINAL_OUTPUT_DIR}/rpzip.txt"
        log_debug "  rpzip: 無記錄 (建立空檔案)"
    fi

    if [[ $count -eq 0 ]]; then
        log_warn "沒有找到任何有效的解析檔案"
    fi

    log_info "共產生 $count 個有效的 DataGroup 檔案"

    # 設定全域變數供 update_datagroup.sh 使用
    export FINAL_OUTPUT_DIR
    export PROCESSED_ZONES="${zones[*]}"
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    log_info "=== 開始產生 DataGroup 檔案 ==="

    prepare_final_datagroups

    log_info "=== DataGroup 檔案產生完成 ==="
    log_info "檔案位置: $FINAL_OUTPUT_DIR"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
__RPZ_EMBED_GENERATE_DATAGROUP_SH__
}

main "$@"
