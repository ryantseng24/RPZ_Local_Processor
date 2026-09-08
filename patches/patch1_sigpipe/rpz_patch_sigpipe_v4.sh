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
ORIG[utils.sh]="3cab6cbca952f3780350e9882e5f7c11"
ORIG[parse_rpz.sh]="bbe45c6f79b56922388d4af7aa6e7583"
ORIG[generate_datagroup.sh]="35547d33ce109945d1ca17e8eb241e0a"
NEW[utils.sh]="b8294149dc978305e19bcd83fcb650e6"
NEW[parse_rpz.sh]="cefa71b6623632dd51c60a51cdf72196"
NEW[generate_datagroup.sh]="9599755a54db53652c070cd70ae92652"

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

embed_utils_sh() {
cat <<'__RPZ_EMBED__'
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
__RPZ_EMBED__
}

embed_parse_rpz_sh() {
cat <<'__RPZ_EMBED__'
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
__RPZ_EMBED__
}

embed_generate_datagroup_sh() {
cat <<'__RPZ_EMBED__'
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
__RPZ_EMBED__
}

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
