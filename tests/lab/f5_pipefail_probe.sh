#!/bin/bash
# =============================================================================
# f5_pipefail_probe.sh
# 目的: 在 F5 BIG-IP 上驗證 `ls -t <glob> | head -1` 在 set -o pipefail 下
#       是否會回傳非 0，以及觸發門檻。
#
# 對應的 production 程式碼:
#   scripts/parse_rpz.sh:227          ls -t raw/dnsxdump_*.out   | head -1
#   scripts/generate_datagroup.sh:65  ls -t parsed/${zone}_*.txt | head -1
#   scripts/generate_datagroup.sh:82  ls -t parsed/rpzip_*.txt   | head -1
#
# 安全性:
#   - 預設只在 /var/tmp 下建立自己的目錄，建 0 bytes 假檔，測完刪除
#   - 不讀寫 /config、不碰 final/、不碰 DataGroup、不碰 SOA cache、不碰 tmsh
#   - 假檔路徑長度刻意與 production 完全相同（ls 輸出的位元組數才是關鍵變數）
#   - 加 --on-config 才會在 /config 下重測一次（只在測試 VM 上使用）
# =============================================================================

ITERS="${ITERS:-100}"
ON_CONFIG=0
CONFIRM=0

while [ $# -gt 0 ]; do
    case "$1" in
        --on-config) ON_CONFIG=1; shift ;;
        --iters)     ITERS="$2"; shift 2 ;;
        --i-know)    CONFIRM=1; shift ;;
        -h|--help)
            echo "用法: $0 [--iters N] [--on-config --i-know]"
            exit 0 ;;
        *) echo "未知選項: $1"; exit 1 ;;
    esac
done

# -----------------------------------------------------------------------------
# production 偵測：避免誤跑在正式機
# -----------------------------------------------------------------------------
PROD_MARK=/config/snmp/rpz_datagroups/final/rpztw.txt
if [ -s "$PROD_MARK" ] && [ "$CONFIRM" -ne 1 ]; then
    echo "!! 偵測到 $PROD_MARK 存在且非空，這看起來是正式機。"
    echo "!! 本腳本不會動任何 production 資料，但仍要求明確確認。"
    echo "!! 確認是測試 VM 請加 --i-know。"
    exit 2
fi

echo "=============================================================="
echo " f5_pipefail_probe  主機: $(hostname)  時間: $(date '+%F %T')"
echo "=============================================================="
echo

# -----------------------------------------------------------------------------
# 0. 環境
# -----------------------------------------------------------------------------
echo "===== 0. 環境 ====="
uname -srm
bash --version 2>/dev/null | head -1
ls --version 2>/dev/null | head -1 || echo "ls: 非 GNU coreutils"
echo "ls 實際位置: $(type -p ls)  $(readlink -f "$(type -p ls)" 2>/dev/null)"
echo "pipe-max-size: $(cat /proc/sys/fs/pipe-max-size 2>/dev/null || echo N/A)"
echo "ARG_MAX: $(getconf ARG_MAX 2>/dev/null)"
echo "CPU 核心數: $(getconf _NPROCESSORS_ONLN 2>/dev/null)"
echo

# -----------------------------------------------------------------------------
# 路徑組裝：讓 ls 輸出的每行長度與 production 完全一致
#   production raw    前綴 = /config/snmp/rpz_datagroups/raw/     = 32 bytes
#   production parsed 前綴 = /config/snmp/rpz_datagroups/parsed/  = 35 bytes
#   raw    檔名 dnsxdump_YYYYmmdd_HHMMSS.out = 28 bytes -> 每行 61 bytes(含 \n)
#   parsed 檔名 rpztw_YYYYmmdd_HHMMSS.txt    = 25 bytes -> 每行 61 bytes(含 \n)
# -----------------------------------------------------------------------------
setup_dirs() {
    local root="$1"
    PROBE_ROOT="$root/rpzprobe"
    RAWD="$PROBE_ROOT/raw0000000000"          # 前綴湊到 32
    PARSEDD="$PROBE_ROOT/parsed0000000000"    # 前綴湊到 35
    if [ "$root" = "/config/snmp" ]; then
        # /config/snmp/rpzprobe/... 長度不同，改用刻意補齊的名稱
        PROBE_ROOT="/config/snmp/rpzprobe"    # 長度 21
        RAWD="$PROBE_ROOT/raw000000"          # 21+1+9  = 31 -> 含 / 為 32
        PARSEDD="$PROBE_ROOT/parsed000000"    # 21+1+12 = 34 -> 含 / 為 35
    fi
    mkdir -p "$RAWD" "$PARSEDD" || return 1
    printf '  raw    前綴長度 = %s (production 32)\n' "$(( ${#RAWD} + 1 ))"
    printf '  parsed 前綴長度 = %s (production 35)\n' "$(( ${#PARSEDD} + 1 ))"
}

fill() {
    # fill <dir> <prefix> <suffix> <target_count>
    local dir="$1" pre="$2" suf="$3" target="$4"
    local cur i name
    cur=$(ls -1 "$dir" 2>/dev/null | wc -l)
    i=$cur
    while [ "$i" -lt "$target" ]; do
        i=$((i + 1))
        name=$(printf '%s2026%04d_%06d%s' "$pre" "$i" "$i" "$suf")
        : > "$dir/$name"
    done
}

probe() {
    # probe <dir> <glob_suffix> <label>
    local dir="$1" glob="$2" label="$3"
    local n bytes fail=0 codes="" rc t
    n=$(ls -1 "$dir" 2>/dev/null | wc -l)
    bytes=$(ls -t "$dir"/$glob 2>/dev/null | wc -c)

    for t in $(seq 1 "$ITERS"); do
        ( set -euo pipefail
          f=$(ls -t "$dir"/$glob 2>/dev/null | head -1)
          : "$f"
        ) 2>/dev/null
        rc=$?
        if [ "$rc" -ne 0 ]; then
            fail=$((fail + 1))
            case " $codes " in *" $rc "*) ;; *) codes="$codes $rc" ;; esac
        fi
    done
    printf '%-26s 檔案數=%-5s ls輸出=%-9s 失敗 %3d/%-4s 退出碼:%s\n' \
        "$label" "$n" "${bytes}B" "$fail" "$ITERS" "${codes:- -}"
}

pipestatus_detail() {
    local dir="$1" glob="$2"
    echo "  --- PIPESTATUS 逐段退出碼（各跑 5 次）---"
    local t
    for t in 1 2 3 4 5; do
        ls -t "$dir"/$glob 2>/dev/null | head -1 >/dev/null
        printf '    第 %s 次: ls=%s head=%s\n' "$t" "${PIPESTATUS[0]}" "${PIPESTATUS[1]}"
    done
    echo "  --- ls 單獨執行（不接管線）的退出碼 ---"
    ls -t "$dir"/$glob >/dev/null 2>&1
    printf '    ls rc=%s\n' "$?"
}

test_fixes() {
    local dir="$1" glob="$2"
    echo "  --- 修正方案 A: 管線後面加 || true ---"
    ( set -euo pipefail
      f=$(ls -t "$dir"/$glob 2>/dev/null | head -1 || true)
      echo "    rc=0 取到: $(basename "${f:-<空>}")"
    ) || echo "    方案 A 失敗 rc=$?"

    echo "  --- 修正方案 B: 純 bash 迴圈，完全不用管線（建議）---"
    ( set -euo pipefail
      newest=""
      for f in "$dir"/$glob; do
          [ -f "$f" ] || continue
          if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
      done
      echo "    rc=0 取到: $(basename "${newest:-<空>}")"
    ) || echo "    方案 B 失敗 rc=$?"
}

run_suite() {
    local root="$1" tag="$2"
    echo "=============================================================="
    echo " $tag  (root=$root)"
    echo "=============================================================="
    if ! setup_dirs "$root"; then
        echo "  無法建立測試目錄，跳過"
        return 1
    fi
    echo

    echo "===== raw/ 情境：模擬 dnsxdump_*.out 累積 ====="
    for n in 30 67 125 141 169 179 300 600 1200; do
        fill "$RAWD" "dnsxdump_" ".out" "$n"
        case "$n" in
            125) lbl="n=125 (設備D 實際)" ;;
            141) lbl="n=141 (設備A 實際)" ;;
            169) lbl="n=169 (設備C 實際)" ;;
            179) lbl="n=179 (設備B 實際)" ;;
            *)   lbl="n=$n" ;;
        esac
        probe "$RAWD" 'dnsxdump_*.out' "$lbl"
    done
    echo
    pipestatus_detail "$RAWD" 'dnsxdump_*.out'
    echo
    test_fixes "$RAWD" 'dnsxdump_*.out'
    echo

    echo "===== parsed/ 情境：模擬 ${zone}_*.txt 累積 ====="
    for n in 95 201 267 285 400; do
        fill "$PARSEDD" "rpztw_" ".txt" "$n"
        case "$n" in
            95)  lbl="n=95  (單一 zone 約略值)" ;;
            201) lbl="n=201 (設備D 實際)" ;;
            267) lbl="n=267 (設備A 實際)" ;;
            285) lbl="n=285 (設備B 實際)" ;;
            *)   lbl="n=$n" ;;
        esac
        probe "$PARSEDD" 'rpztw_*.txt' "$lbl"
    done
    echo

    echo "===== 清除測試目錄 ====="
    echo "  即將刪除: $PROBE_ROOT"
    rm -rf "$PROBE_ROOT"
    if [ -d "$PROBE_ROOT" ]; then echo "  !! 刪除失敗，請手動處理"; else echo "  已刪除"; fi
    echo
}

run_suite /var/tmp "情境 1: /var/tmp（與 /config 不同分割區，零風險）"

if [ "$ON_CONFIG" -eq 1 ]; then
    echo "注意: 接下來在 /config 下重測，用意是取得真實分割區的 I/O 時序。"
    echo "      只建立 0 bytes 假檔於 /config/snmp/rpzprobe/，測完刪除。"
    echo
    run_suite /config/snmp "情境 2: /config/snmp（真實分割區時序，僅測試 VM）"
fi

echo "=============================================================="
echo " 判讀方式"
echo "=============================================================="
cat <<'EOT'
  退出碼 141 = SIGPIPE。代表 ls 在 head -1 結束後還想寫入。
  退出碼 1/2 = ls 本身回報錯誤。
  失敗 0/100 且各 n 都是 0 -> 這一行不是失敗點，要重新找。
  某個 n 之後開始失敗       -> 找到門檻，與四台的檔案數對照即可確認。
EOT
