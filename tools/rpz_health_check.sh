#!/bin/bash
# =============================================================================
# rpz_health_check.sh — RPZ Local Processor 運作健康檢查（唯讀）
# =============================================================================
# 對象: OP / 監控人員。獨立於 RPZ 程式本身，單檔即可使用。
# 用法: bash /var/tmp/rpz_health_check.sh
# 遠端: ssh <帳號>@<設備IP> 'bash /var/tmp/rpz_health_check.sh'
#
# 本工具只讀取狀態。不修改任何檔案、設定與排程。
#
# 退出碼: 0 = 全部[正常]
#         1 = 有[注意]項目（可觀察，不需立即處理）
#         2 = 有[異常]項目（保留完整輸出回報）
#
# 可調整（環境變數，平時不需要動）:
#   RPZ_FRESH_HOURS  完整更新的新鮮度門檻（小時），預設 24
#   RPZ_KEEP         每類暫存檔的保留上限，預設 24（需與 main.sh 一致）
# =============================================================================

set -u

BASE=${RPZ_BASE:-/config/snmp/rpz_datagroups}
WLOG=${RPZ_WLOG:-/config/snmp/rpz_wrapper.log}
LTMLOG=${RPZ_LTMLOG:-/var/log/ltm}
DISK=${RPZ_DISK_PATH:-/config}
FRESH_HOURS=${RPZ_FRESH_HOURS:-24}
KEEP=${RPZ_KEEP:-24}

NOW=$(date +%s)
OKC=0; WARNC=0; FAILC=0

ok()  { OKC=$((OKC+1));     printf '[正常] %s\n' "$1"; }
wrn() { WARNC=$((WARNC+1)); printf '[注意] %s\n' "$1"; }
bad() { FAILC=$((FAILC+1)); printf '[異常] %s\n' "$1"; }

# 檔案 mtime（epoch）。BIG-IP 走 GNU stat；BSD 分支只給開發機測試用。
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
# 文字日期轉 epoch。格式: Tue Sep 15 18:30:00 CST 2026
epoch_of() {
    date -d "$1" +%s 2>/dev/null \
    || date -j -f '%a %b %d %T %Z %Y' "$1" +%s 2>/dev/null
}
count_glob() { local n=0 f; for f in "$@"; do [ -f "$f" ] && n=$((n+1)); done; printf '%s\n' "$n"; }

printf '==============================================================\n'
printf ' RPZ Local Processor 健康檢查（唯讀）\n'
printf ' 設備: %s    時間: %s\n' "$(uname -n)" "$(date '+%F %T')"
printf '==============================================================\n'

# ---------------------------------------------------------------- 1. 排程
if command -v tmsh >/dev/null 2>&1; then
    H=$(tmsh list sys icall handler periodic rpz_processor_handler status interval 2>/dev/null)
    if [ -z "$H" ]; then
        bad "排程: 讀不到 rpz_processor_handler（tmsh 查詢失敗）"
    else
        ST=$(printf '%s\n' "$H" | awk '$1=="status"{print $2}')
        IV=$(printf '%s\n' "$H" | awk '$1=="interval"{print $2}')
        if [ "${ST:-}" = "active" ] && [ "${IV:-}" = "300" ]; then
            ok "排程: active，每 300 秒檢查一次"
        else
            bad "排程: status=${ST:-?} interval=${IV:-?}（預期 active / 300）"
        fi
    fi
else
    wrn "此主機沒有 tmsh，略過排程與資料載入檢查（不是在 F5 設備上執行？）"
fi

# ---------------------------------------------- 2. 排程是否真的有在執行
if [ ! -r "$WLOG" ]; then
    bad "執行紀錄: 讀不到 ${WLOG}"
else
    LASTSTART=$(tail -600 "$WLOG" 2>/dev/null | sed -n 's/^=== \(.*\) - Wrapper Start ===.*/\1/p' | tail -1)
    if [ -z "$LASTSTART" ]; then
        bad "執行紀錄: 近期找不到任何一次執行開始的紀錄"
    else
        EP=$(epoch_of "$LASTSTART")
        if [ -z "${EP:-}" ]; then
            wrn "執行紀錄: 時間格式無法解析（最後一次開始: ${LASTSTART}）"
        else
            AGE=$((NOW - EP))
            if [ "$AGE" -le 900 ]; then
                ok "排程有在執行: 最近一次開始於 ${LASTSTART}（$((AGE / 60)) 分鐘前）"
            else
                bad "超過 $((AGE / 60)) 分鐘沒有新的執行（排程應每 5 分鐘一次）。最後一次: ${LASTSTART}"
            fi
        fi
    fi
fi

# ---------------------------------------------- 3. 最近 12 次的執行結果
if [ -r "$WLOG" ]; then
    RCL=$(tail -4000 "$WLOG" 2>/dev/null | sed -n 's/^=== .* - Exit Code: \([0-9][0-9]*\) ===$/\1/p' | tail -12)
    TOTAL=0; NZ=0
    for rc in $RCL; do
        TOTAL=$((TOTAL + 1))
        [ "$rc" != "0" ] && NZ=$((NZ + 1))
    done
    if [ "$TOTAL" -eq 0 ]; then
        wrn "執行結果: 近期沒有結束紀錄可判讀"
    elif [ "$NZ" -eq 0 ]; then
        ok "執行結果: 最近 ${TOTAL} 次全部成功"
    elif [ "$NZ" -le 2 ]; then
        wrn "執行結果: 最近 ${TOTAL} 次中有 ${NZ} 次失敗（偶發）。可到 Splunk 用 RPZLocal 查錯誤事件"
    else
        bad "執行結果: 最近 ${TOTAL} 次中有 ${NZ} 次失敗。保留本輸出回報"
    fi
fi

# ---------------------------------------------- 4. 黑名單結果檔（完整性與新鮮度）
MISS=""; TMAX=0; TMIN=0
for f in rpztw.txt phishtw.txt rpzip.txt; do
    P="$BASE/final/$f"
    if [ ! -f "$P" ]; then
        MISS="${MISS} ${f}"
        continue
    fi
    T=$(mtime_of "$P")
    [ -z "$T" ] && continue
    [ "$TMAX" -eq 0 ] && { TMAX=$T; TMIN=$T; }
    [ "$T" -gt "$TMAX" ] && TMAX=$T
    [ "$T" -lt "$TMIN" ] && TMIN=$T
done
if [ -n "$MISS" ]; then
    bad "結果檔: 缺少${MISS}（位置 ${BASE}/final/）"
elif [ "$TMAX" -eq 0 ]; then
    bad "結果檔: 讀不到檔案時間"
else
    SPAN=$((TMAX - TMIN))
    if [ "$SPAN" -le 600 ]; then
        ok "結果檔: 三個檔案時間一致（完整更新的特徵）"
    else
        bad "結果檔: 三個檔案時間不一致（相差 $((SPAN / 3600)) 小時）。這是「更新跑到一半失敗」的特徵，保留本輸出回報"
    fi
    AGEH=$(( (NOW - TMAX) / 3600 ))
    if [ "$AGEH" -le "$FRESH_HOURS" ]; then
        ok "新鮮度: 最後一次完整更新在 ${AGEH} 小時內"
    else
        wrn "新鮮度: 已 ${AGEH} 小時沒有完整更新（門檻 ${FRESH_HOURS} 小時）。若來源最近真的沒有變更，屬正常；請搭配第 2、3 項判讀"
    fi
fi

# ---------------------------------------------- 5. 暫存檔數量（清理機制是否生效）
NR=$(count_glob "$BASE"/raw/dnsxdump_*.out)
NT=$(count_glob "$BASE"/parsed/rpztw_*.txt)
NP=$(count_glob "$BASE"/parsed/phishtw_*.txt)
NZP=$(count_glob "$BASE"/parsed/rpzip_*.txt)
MAXN=$NR
for n in $NT $NP $NZP; do [ "$n" -gt "$MAXN" ] && MAXN=$n; done
DETAIL="raw ${NR}、parsed ${NT}/${NP}/${NZP}（上限每類 ${KEEP}）"
if [ "$MAXN" -le $((KEEP + 2)) ]; then
    ok "暫存檔數量受控: ${DETAIL}"
elif [ "$MAXN" -lt 60 ]; then
    wrn "暫存檔超過上限: ${DETAIL}。自動清理可能未生效，請回報"
else
    bad "暫存檔大量累積: ${DETAIL}。已接近會導致更新失敗的數量，保留本輸出回報"
fi

# ---------------------------------------------- 6. 磁碟
USEP=$(df -P "$DISK" 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
if [ -z "${USEP:-}" ]; then
    wrn "磁碟: 讀不到 ${DISK} 的使用率"
elif [ "$USEP" -ge 80 ]; then
    bad "磁碟: ${DISK} 使用率 ${USEP}%（告警線 80%）"
elif [ "$USEP" -ge 70 ]; then
    wrn "磁碟: ${DISK} 使用率 ${USEP}%，請留意趨勢"
else
    ok "磁碟: ${DISK} 使用率 ${USEP}%"
fi

# ---------------------------------------------- 7. 事件通道（Splunk 可視性）
if [ -r "$LTMLOG" ]; then
    LASTEVT=$(grep 'RPZLocal' "$LTMLOG" 2>/dev/null | tail -1 | cut -c1-96)
    if [ -n "$LASTEVT" ]; then
        ok "事件通道: 本機有 RPZLocal 事件（最後一筆: ${LASTEVT}）"
    else
        wrn "事件通道: 目前的 ${LTMLOG} 沒有 RPZLocal 事件（每日換檔後或近期無更新屬可能）。Splunk 端可直接查 RPZLocal"
    fi
else
    wrn "事件通道: 讀不到 ${LTMLOG}（權限不足？）"
fi

# ---------------------------------------------- 8. 資料是否已載入 DNS 服務
if command -v tmsh >/dev/null 2>&1; then
    DG=$(tmsh list sys file data-group rpztw 2>/dev/null | awk '$1=="revision" || $1=="size" {printf "%s=%s ", $1, $2}')
    if [ -n "${DG:-}" ]; then
        ok "資料載入: rpztw ${DG}"
    else
        bad "資料載入: 讀不到 rpztw（tmsh 查詢失敗）"
    fi
fi

printf '==============================================================\n'
printf ' 結果: 正常 %s 項 / 注意 %s 項 / 異常 %s 項\n' "$OKC" "$WARNC" "$FAILC"
if [ "$FAILC" -gt 0 ]; then
    printf ' 判定: [異常] 請保留本畫面完整輸出回報。\n'
    printf '==============================================================\n'
    exit 2
elif [ "$WARNC" -gt 0 ]; then
    printf ' 判定: [注意] 可先觀察；持續出現再回報。\n'
    printf '==============================================================\n'
    exit 1
else
    printf ' 判定: [正常] 系統運作正常。\n'
    printf '==============================================================\n'
    exit 0
fi
