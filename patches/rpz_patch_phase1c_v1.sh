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
ORIG[main.sh]="d1e1f688d939a5a5e87282605d0e3eed"
ORIG[extract_rpz.sh]="62aeaf053b08f3411fe530f33555c414"
ORIG[update_datagroup.sh]="f8b038bc06df1c07050cd2922a91c5aa"
NEW[main.sh]="9d8538a68480a1a0489058be6b1d6622"
NEW[extract_rpz.sh]="fea7c2e29f5380ab22611f7b2cc97fbc"
NEW[update_datagroup.sh]="67227cb39028dc2bf17b14ef9c871bc4"

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

embed_main_sh() {
cat <<'__RPZ_EMBED__'
#!/bin/bash
# =============================================================================
# main.sh - RPZ Local Processor 主執行腳本
# =============================================================================
# 完整流程:
# 1. 檢查 SOA Serial 是否變更
# 2. 從 DNS Express 提取 RPZ 資料
# 3. 解析 RPZ 記錄 (FQDN + IP)
# 4. 產生 DataGroup 檔案
# 5. 更新 F5 DataGroups
# 6. 清理臨時檔案
# =============================================================================

set -euo pipefail

# 取得腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 載入工具函數
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

CONFIG_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"

# 是否清理臨時檔案 (預設: 是)
CLEANUP_TEMP="${CLEANUP_TEMP:-true}"

# 是否強制執行 (跳過 SOA 檢查)
FORCE_RUN="${FORCE_RUN:-false}"

# 暫存檔保留數量上限（每個檔案家族）。與天數上限並用，取先到者。
# 接受範圍 1~99999；範圍外或非數字回退預設 24（防 bash 整數溢位）。
RPZ_KEEP_COUNT="${RPZ_KEEP_COUNT:-24}"
if ! [[ "$RPZ_KEEP_COUNT" =~ ^[1-9][0-9]{0,4}$ ]]; then
    log_warn "RPZ_KEEP_COUNT 非法或超出範圍 1-99999（${RPZ_KEEP_COUNT}），改用預設 24"
    RPZ_KEEP_COUNT=24
fi

# cleanup 只執行一次（成功路徑先呼叫，EXIT trap 補所有其他路徑）
CLEANUP_RAN="false"

# =============================================================================
# 初始化
# =============================================================================

init() {
    log_info "=========================================="
    log_info "  RPZ Local Processor 啟動"
    log_info "=========================================="
    log_info "專案根目錄: $PROJECT_ROOT"
    log_info "輸出目錄: $OUTPUT_DIR"
    log_info "系統事件 log: syslog local0 -> /var/log/ltm（tag=RPZLocal）"

    # 建立必要目錄
    ensure_dir "$LOG_DIR"
    ensure_dir "$OUTPUT_DIR"

    # 檢查必要指令
    check_command "bash"
    check_command "awk"
    check_command "sed"
    check_command "grep"

    # 檢查 F5 特定指令
    if ! command -v tmsh >/dev/null 2>&1; then
        log_warn "tmsh 指令不存在，可能不在 F5 環境中"
    fi

    if ! command -v /usr/local/bin/dnsxdump >/dev/null 2>&1; then
        log_warn "dnsxdump 指令不存在，可能不在 F5 DNS 環境中"
    fi
}

# =============================================================================
# 清理臨時檔案
# =============================================================================

# 時間戳的精確 glob 形狀: 8 位日期 _ 6 位時間
TS_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]'

prune_family() {
    # prune_family <目錄> <家族前綴> <副檔名> <保留數>
    # 家族成員 = <前綴>_<8位日期>_<6位時間><副檔名> 的精確形狀。
    # 前綴以字面比對（引號展開），不作為 glob 使用：
    # alpha 家族不會選中 alpha_beta 家族的檔案（P1B-08）。
    # 檔名時間戳使 glob 展開的字典序即時間序。
    # 純 bash 迴圈，不用管線（SIGPIPE 根因見 process.md 第 2 節，實測數據第 6 節）。
    local dir="$1" prefix="$2" ext="$3" keep="$4"
    local files=() f i del
    for f in "$dir/${prefix}"_${TS_GLOB}"${ext}"; do
        [[ -f "$f" ]] || continue
        files+=("$f")
    done
    del=$(( ${#files[@]} - keep ))
    (( del > 0 )) || return 0
    local deleted=0 failed=0
    for (( i = 0; i < del; i++ )); do
        if rm -f -- "${files[$i]}" 2>/dev/null; then
            deleted=$((deleted + 1))
        else
            failed=$((failed + 1))
        fi
    done
    if (( failed > 0 )); then
        log_warn "數量上限清理: ${dir##*/}/${prefix} 家族應刪 ${del} 個，實際刪除 ${deleted} 個，失敗 ${failed} 個（實際保留數超過 ${keep}）"
    else
        log_info "數量上限清理: ${dir##*/}/${prefix} 家族刪除 ${deleted} 個，保留 ${keep} 個"
    fi
}

prune_parsed_families() {
    # 從 parsed/ 檔名推導家族前綴（zone 名），逐家族套用數量上限。
    # 不讀 zonelist.txt：zone 增減自動適應，也不引入新的解析路徑。
    local dir="$1" keep="$2"
    local f name prefix
    declare -A seen
    for f in "$dir"/*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].txt; do
        [[ -f "$f" ]] || continue
        name="${f##*/}"
        [[ "$name" =~ ^(.+)_[0-9]{8}_[0-9]{6}\.txt$ ]] || continue
        prefix="${BASH_REMATCH[1]}"
        # 前綴只接受本專案會產生的安全字元，避免被當成 glob 使用
        if [[ "$prefix" =~ ^[A-Za-z0-9._-]+$ ]]; then
            seen["$prefix"]=1
        else
            log_warn "略過不安全的家族前綴（僅由天數上限管理）: ${name}"
        fi
    done
    (( ${#seen[@]} > 0 )) || return 0    # bash 4.2: 空陣列展開會踩 set -u
    for prefix in "${!seen[@]}"; do
        prune_family "$dir" "$prefix" ".txt" "$keep"
    done
}

cleanup() {
    if [[ "$CLEANUP_TEMP" != "true" ]]; then
        log_info "跳過清理臨時檔案"
        return 0
    fi

    # 只清 raw/ 與 parsed/，不遞迴掃 OUTPUT_DIR。
    # final/ 是 DataGroup 的 source-path，刪除即影響服務（實測見 process.md 第 27 節）。
    if [[ -d "$OUTPUT_DIR/raw" ]]; then
        if ! find "$OUTPUT_DIR/raw" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null; then
            log_warn "天數上限清理失敗（raw/ 有檔案無法刪除）"
        fi
    fi
    if [[ -d "$OUTPUT_DIR/parsed" ]]; then
        if ! find "$OUTPUT_DIR/parsed" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null; then
            log_warn "天數上限清理失敗（parsed/ 有檔案無法刪除）"
        fi
    fi

    prune_family "$OUTPUT_DIR/raw" "dnsxdump" ".out" "$RPZ_KEEP_COUNT"
    prune_parsed_families "$OUTPUT_DIR/parsed" "$RPZ_KEEP_COUNT"

    # 缺陷 A（Phase 2）: DNSXDUMP_FILE 由 extract_rpz.sh 子行程 export，
    # 傳不回本行程，此分支從未執行。本次保留原樣。
    if [[ -n "${DNSXDUMP_FILE:-}" && -f "$DNSXDUMP_FILE" ]]; then
        rm -f "$DNSXDUMP_FILE" || true
        log_info "清理 dnsxdump 檔案完成"
    fi

    return 0
}

run_cleanup_once() {
    if [[ "$CLEANUP_RAN" == "true" ]]; then
        return 0
    fi
    CLEANUP_RAN="true"
    cleanup
}

on_exit() {
    # 先保存退出碼，清理後原樣回傳，不改變 wrapper 記錄的語意。
    local rc=$?
    run_cleanup_once || true
    exit "$rc"
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    local start_time=$(date +%s)

    # 初始化
    init

    # 步驟 1: 檢查 SOA Serial 變更
    log_info ""
    log_info "步驟 1/5: 檢查 RPZ Zone SOA Serial"

    if [[ "$FORCE_RUN" == "true" ]]; then
        log_warn "強制執行模式，跳過 SOA 檢查"
    else
        # 執行 SOA 檢查並捕獲輸出
        # 輸出: UPDATE_NEEDED=需要更新, NO_UPDATE=無需更新
        local soa_check_output
        soa_check_output=$(bash "${SCRIPT_DIR}/check_soa.sh" check-all 2>&1 | grep -E '^(UPDATE_NEEDED|NO_UPDATE)$' | tail -1)
        local soa_check_exit=$?

        if [[ "$soa_check_output" == "NO_UPDATE" ]]; then
            # SOA 未變更，無需更新（這是正常情況，不是錯誤）
            log_info "SOA Serial 未變更，無需更新"
            logger -t RPZLocal -p local0.notice "RPZ SOA not changed, skip update" || true
            exit 0
        elif [[ "$soa_check_output" != "UPDATE_NEEDED" ]]; then
            # 檢查失敗或輸出異常
            log_error "SOA 檢查失敗或輸出異常（退出碼: $soa_check_exit, 輸出: '$soa_check_output'）"
            logger -t RPZLocal -p local0.err "RPZ SOA check failed" || true
            exit 1
        fi

        # SOA 已變更，繼續處理
        log_info "SOA Serial 已變更，繼續處理"
        logger -t RPZLocal -p local0.notice "RPZ SOA changed, start processing" || true
    fi

    # 步驟 2: 從 DNS Express 提取 RPZ 資料
    log_info ""
    log_info "步驟 2/5: 提取 DNS Express 資料"
    if ! bash "${SCRIPT_DIR}/extract_rpz.sh"; then
        log_error "資料提取失敗"
        logger -t RPZLocal -p local0.err "RPZ extraction failed" || true
        exit 1
    fi

    # 步驟 3: 解析 RPZ 記錄
    log_info ""
    log_info "步驟 3/5: 解析 RPZ 記錄"
    if ! bash "${SCRIPT_DIR}/parse_rpz.sh"; then
        log_error "RPZ 解析失敗"
        logger -t RPZLocal -p local0.err "RPZ parsing failed" || true
        exit 1
    fi

    # 步驟 4: 產生 DataGroup 檔案
    log_info ""
    log_info "步驟 4/5: 產生 DataGroup 檔案"
    if ! bash "${SCRIPT_DIR}/generate_datagroup.sh"; then
        log_error "DataGroup 產生失敗"
        logger -t RPZLocal -p local0.err "DataGroup generation failed" || true
        exit 1
    fi

    # 步驟 5: 更新 F5 DataGroups
    log_info ""
    log_info "步驟 5/5: 更新 F5 DataGroups"
    if ! bash "${SCRIPT_DIR}/update_datagroup.sh"; then
        log_error "F5 DataGroup 更新失敗"
        logger -t RPZLocal -p local0.err "F5 update failed" || true
        exit 1
    fi

    # 清理臨時檔案
    run_cleanup_once

    # 統計執行時間
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    log_info ""
    log_info "=========================================="
    log_info "  處理完成"
    log_info "=========================================="
    log_info "總耗時: $(timer_format "$elapsed")"
    logger -t RPZLocal -p local0.notice "RPZ processing completed in ${elapsed}s" || true

    exit 0
}

# =============================================================================
# 命令列參數處理
# =============================================================================

show_usage() {
    cat << EOF
用法: $0 [選項]

選項:
  -f, --force          強制執行 (跳過 SOA 檢查)
  -n, --no-cleanup     不清理臨時檔案
  -h, --help           顯示此說明
  -v, --verbose        詳細模式 (DEBUG log level)

範例:
  $0                   # 正常執行
  $0 --force           # 強制執行，忽略 SOA 檢查
  $0 --no-cleanup      # 保留臨時檔案供除錯
  $0 -f -n -v          # 強制執行 + 保留檔案 + 詳細輸出

環境變數:
  OUTPUT_DIR           DataGroup 輸出目錄 (預設: /config/snmp/rpz_datagroups)
  DNSXDUMP_CMD         dnsxdump 指令路徑 (預設: /usr/local/bin/dnsxdump)
  LOG_LEVEL            日誌等級 0-3 (預設: 1=INFO)
  RPZ_KEEP_COUNT       暫存檔每家族保留數量上限 (預設: 24，範圍 1-99999)

EOF
}

# 解析命令列參數
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_RUN="true"
            shift
            ;;
        -n|--no-cleanup)
            CLEANUP_TEMP="false"
            shift
            ;;
        -v|--verbose)
            LOG_LEVEL=$LOG_DEBUG
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "未知選項: $1"
            show_usage
            exit 1
            ;;
    esac
done

# =============================================================================
# 執行
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 設定 trap 處理錯誤
    trap 'log_error "執行過程發生錯誤，退出碼: $?"' ERR

    # 所有 exit 路徑（成功、NO_UPDATE、失敗）都執行清理（Phase 1B）
    trap on_exit EXIT

    main "$@"
fi
__RPZ_EMBED__
}

embed_extract_rpz_sh() {
cat <<'__RPZ_EMBED__'
#!/bin/bash
# =============================================================================
# extract_rpz.sh - 從 DNS Express 提取 RPZ 資料
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
DNSXDUMP_CMD="${DNSXDUMP_CMD:-/usr/local/bin/dnsxdump}"

# =============================================================================
# 執行 dnsxdump 並導出完整資料
# =============================================================================

execute_dnsxdump() {
    local output_file="$1"

    log_info "執行 dnsxdump 導出 DNS Express 資料"

    # 檢查指令是否存在
    if [[ ! -x "$DNSXDUMP_CMD" ]]; then
        log_error "dnsxdump 指令不存在或無執行權限: $DNSXDUMP_CMD"
        logger -t RPZLocal -p local0.err "dnsxdump command not found" || true
        return 1
    fi

    # 執行 dnsxdump
    if ! "$DNSXDUMP_CMD" > "$output_file" 2>&1; then
        log_error "執行 dnsxdump 失敗"
        logger -t RPZLocal -p local0.err "dnsxdump execution failed" || true
        return 1
    fi

    # 檢查輸出檔案
    if [[ ! -s "$output_file" ]]; then
        log_error "dnsxdump 輸出檔案為空"
        logger -t RPZLocal -p local0.err "dnsxdump output is empty" || true
        return 1
    fi

    local line_count=$(wc -l < "$output_file")
    log_info "dnsxdump 執行成功，匯出 $line_count 行資料"
    logger -t RPZLocal -p local0.notice "dnsxdump exported ${line_count} lines" || true

    return 0
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    local timestamp_compact=$(timestamp_compact)

    log_info "=== 開始提取 RPZ 資料 ==="

    # 建立輸出目錄
    ensure_dir "$RAW_DATA_DIR"

    # 執行完整 dnsxdump - 直接產生供 parse_rpz.sh 使用
    local full_dump_file="${RAW_DATA_DIR}/dnsxdump_${timestamp_compact}.out"
    if ! execute_dnsxdump "$full_dump_file"; then
        die "DNS Express 資料提取失敗"
    fi

    log_info "=== RPZ 資料提取完成 ==="

    # 設定全域變數供後續腳本使用
    export DNSXDUMP_FILE="$full_dump_file"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
__RPZ_EMBED__
}

embed_update_datagroup_sh() {
cat <<'__RPZ_EMBED__'
#!/bin/bash
# =============================================================================
# update_datagroup.sh - 更新 F5 External DataGroup (動態 Zone 支援 + 自動建立)
# =============================================================================
# 功能:
# 1. 從 zonelist.txt 讀取要處理的 zones
# 2. 檢查 DataGroup 是否存在，不存在則自動建立
# 3. 更新 DataGroup 內容
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# 配置
# =============================================================================

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
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
# 檢查 DataGroup 是否存在
# =============================================================================

datagroup_exists() {
    local dg_name="$1"

    if tmsh list ltm data-group external "$dg_name" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# 建立 External DataGroup
# =============================================================================

create_datagroup() {
    local dg_name="$1"
    local source_file="$2"

    log_info "建立新的 DataGroup: $dg_name"

    # 建立 external data-group
    if tmsh create ltm data-group external "$dg_name" \
        source-path "file:$source_file" \
        type string 2>&1; then
        log_info "✓ DataGroup $dg_name 建立成功"
        logger -t RPZLocal -p local0.notice "created DataGroup ${dg_name} (file=${source_file})" || true
        return 0
    else
        log_error "DataGroup $dg_name 建立失敗"
        logger -t RPZLocal -p local0.err "failed to create DataGroup ${dg_name}" || true
        return 1
    fi
}

# =============================================================================
# 更新單一 DataGroup
# =============================================================================

update_single_datagroup() {
    local dg_name="$1"
    local source_file="$2"

    log_info "處理 DataGroup: $dg_name"

    # 檢查檔案是否存在
    if [[ ! -f "$source_file" ]]; then
        log_error "來源檔案不存在: $source_file"
        logger -t RPZLocal -p local0.err "source file not found: ${source_file}" || true
        return 1
    fi

    # 檢查檔案是否為空
    if [[ ! -s "$source_file" ]]; then
        log_warn "來源檔案為空，跳過: $source_file"
        return 0
    fi

    # 檢查 DataGroup 是否存在
    if ! datagroup_exists "$dg_name"; then
        log_info "DataGroup $dg_name 不存在，嘗試建立..."
        if ! create_datagroup "$dg_name" "$source_file"; then
            return 1
        fi
        return 0
    fi

    # DataGroup 已存在，執行更新
    if tmsh modify ltm data-group external "$dg_name" source-path "file:$source_file" 2>&1; then
        local record_count=$(wc -l < "$source_file")
        log_info "✓ DataGroup $dg_name 更新成功 ($record_count 筆記錄)"
        logger -t RPZLocal -p local0.notice "updated DataGroup ${dg_name} (${record_count} records, file=${source_file})" || true
        return 0
    else
        log_error "DataGroup $dg_name 更新失敗"
        logger -t RPZLocal -p local0.err "failed to update DataGroup ${dg_name}" || true
        return 1
    fi
}

# =============================================================================
# 批次更新 DataGroups
# =============================================================================

update_all_datagroups() {
    local success_count=0
    local fail_count=0
    local skip_count=0

    log_info "=== 開始更新 F5 DataGroups ==="

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

    # 更新每個 zone 的 DataGroup
    for zone in "${zones[@]}"; do
        local source_file="${FINAL_OUTPUT_DIR}/${zone}.txt"

        if [[ -f "$source_file" && -s "$source_file" ]]; then
            if update_single_datagroup "$zone" "$source_file"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        else
            log_debug "跳過 $zone (檔案不存在或為空)"
            skip_count=$((skip_count + 1))
        fi
    done

    # 處理 IP DataGroup (rpzip) - 如果有資料的話
    local ip_file="${FINAL_OUTPUT_DIR}/rpzip.txt"
    if [[ -f "$ip_file" && -s "$ip_file" ]]; then
        if update_single_datagroup "rpzip" "$ip_file"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    else
        log_debug "跳過 rpzip (檔案不存在或為空)"
    fi

    log_info "=== 更新完成 ==="
    log_info "成功: $success_count 個, 失敗: $fail_count 個, 跳過: $skip_count 個"

    # 儲存配置 (如果有成功更新)
    if [[ $success_count -gt 0 ]]; then
        log_info "儲存 F5 配置..."
        if tmsh save sys config 2>&1; then
            log_info "✓ 配置已儲存"
        else
            log_warn "配置儲存失敗 (可能需要手動儲存)"
        fi
    fi

    return $fail_count
}

# =============================================================================
# 主函數
# =============================================================================

main() {
    update_all_datagroups
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
__RPZ_EMBED__
}

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
