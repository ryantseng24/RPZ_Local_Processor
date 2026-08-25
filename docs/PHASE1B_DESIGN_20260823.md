# Phase 1B 設計文件 — 暫存檔保留策略

**日期**: 2026-08-23
**狀態**: 已實作並完成三輪審核（輪 3 判定 GO）。第 8 節四點已於 2026-08-23 全數核可。實作與審核記錄見 `process.md` 第 22~25 節
**已定案輸入**: 範圍 = B1（只改 `main.sh`）；KEEP = 24（每個檔案家族；`RPZ_KEEP_COUNT` 接受範圍 1-99999，審核輪 1 P1B-02 修正）
**前提**: v4（SIGPIPE 修正）先上。Phase 1B 不解決 4096 問題，
四種復發途徑已實測（`STATUS_20260822.md` 第 9 節）。

---

## 1. 目標與範圍

### 1.1 要解決的問題

| # | 現況缺陷 | 位置 |
|---|---|---|
| 1 | cleanup 的 `find` 遞迴掃整個 `OUTPUT_DIR`，範圍涵蓋 `final/`（DataGroup 來源） | `main.sh:84` |
| 2 | 只有天數上限（8 天），沒有數量上限。頻率成長時磁碟用量跟著翻倍 | `main.sh:84` |
| 3 | cleanup 只在五步驟全部成功後執行。流程停滯時檔案無限累積，直到磁碟告警 | `main.sh:175` 是唯一呼叫點；`main.sh:125/130/144/153/163/171` 六個 exit 路徑都不清理 |

### 1.2 不在範圍（明確排除）

1. `rpz_wrapper.log` rotate（B2 項目，成長 50 MB/年，不急）。
2. 缺陷 A（`main.sh:88-91` 的死碼：`DNSXDUMP_FILE` 由子行程 export 傳不回來，
   `rm -f` 從未執行）。本次**保留原樣**，只加註解標記。Phase 2 處理。
3. 全流程 lock（CR-09）、SOA cache 時序（CR-06/07/08）、final 原子發布（CR-10）。
4. `.soa_cache/` 空目錄移除（對既有機器無效果）。
5. 其他六支腳本、iRule、v4 已修的三支檔案。

---

## 2. 設計依據（已實測，不重做）

| 事實 | 出處 |
|---|---|
| 測試 D：先加 `trap EXIT` 而不縮小 find，停滯機器的 `final/` 會被刪到 0 個 | `process.md` 第 27 節 |
| 測試 E：find 縮小到 `raw/` + `parsed/` 後，`final/` 保留、舊檔仍清除 | 同上 |
| 平日 18 次/日、每次 16.8 MB；KEEP=24 → 磁碟用量估計 403 MB（現況家族數與平均檔案大小；`/config` 12.6%）、平日可回溯 12 小時 | `STATUS_20260822.md` 第 4 節 |
| 檔名 `{prefix}_YYYYMMDD_HHMMSS.{ext}`，glob 字典序 = 時間序 | LAB 實查 raw/ 與 parsed/ |
| `main.sh` 是 `set -euo pipefail`；bash 4.2 空陣列 + `set -u` 展開會報 unbound | `main.sh:14`；bash 4.2 已知行為 |

**因此修改順序固定：縮小 find → 加數量上限 → 加 trap。順序不可顛倒。**

---

## 3. 變更設計（`main.sh`，共四塊）

### 3.1 KEEP 參數（配置區，`main.sh:34` 附近）

```bash
# 暫存檔保留數量上限（每個檔案家族）。與天數上限並用，取先到者。
# 接受範圍 1~99999；範圍外或非數字回退預設 24（防 bash 整數溢位）。
RPZ_KEEP_COUNT="${RPZ_KEEP_COUNT:-24}"
if ! [[ "$RPZ_KEEP_COUNT" =~ ^[1-9][0-9]{0,4}$ ]]; then
    log_warn "RPZ_KEEP_COUNT 非法或超出範圍 1-99999（${RPZ_KEEP_COUNT}），改用預設 24"
    RPZ_KEEP_COUNT=24
fi
```

非法或超出範圍回退預設並警告，不中止（審核輪 1 P1B-02 修正後版本）。

### 3.2 數量上限函數（新增兩個函數）

```bash
# 時間戳的精確 glob 形狀: 8 位日期 _ 6 位時間
TS_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]'

prune_family() {
    # prune_family <目錄> <家族前綴> <副檔名> <保留數>
    # 家族成員 = <前綴>_<8位日期>_<6位時間><副檔名> 的精確形狀。
    # 前綴以字面比對（引號展開），不作為 glob 使用：
    # alpha 家族不會選中 alpha_beta 家族的檔案（P1B-08）。
    # 純 bash 迴圈，不用管線（SIGPIPE 根因見 process.md 第 13 節）。
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
    # 不讀 zonelist.txt。前綴只接受安全字元（P1B-03），
    # 家族成員由 prune_family 以精確形狀選取（P1B-08）。
    local dir="$1" keep="$2"
    local f name prefix
    declare -A seen
    for f in "$dir"/*_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].txt; do
        [[ -f "$f" ]] || continue
        name="${f##*/}"
        [[ "$name" =~ ^(.+)_[0-9]{8}_[0-9]{6}\.txt$ ]] || continue
        prefix="${BASH_REMATCH[1]}"
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
```

設計要點：

1. 零管線、零 `ls`。與 v4 的 `find_newest_file()` 同一設計語言。
2. 家族前綴由檔名推導，zone 增減自動適應，不需要同步 zonelist。
3. 只會刪 `raw/` 與 `parsed/` 內符合本專案命名**精確形狀**的檔案
   （前綴字面 + 8 位日期 + 6 位時間）。不符合的由天數上限（find）處理。

### 3.3 cleanup() 改寫（`main.sh:75-95`）

```bash
cleanup() {
    if [[ "$CLEANUP_TEMP" != "true" ]]; then
        log_info "跳過清理臨時檔案"
        return 0
    fi

    # 只清 raw/ 與 parsed/，不遞迴掃 OUTPUT_DIR。
    # final/ 是 DataGroup 的 source-path，一旦刪除服務即受影響（實測 D/E）。
    # find 失敗不隱藏（P1B-04）
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
```

行為變更（刻意）：**沒刪東西時不輸出 log**。原因見 3.4——cleanup 改為
每次執行都會跑（含 NO_UPDATE tick，每日約 288 次），保留原本三行 banner
會讓 wrapper log 膨脹約三成。有刪除時 `prune_family` 會輸出一行摘要。

### 3.4 trap EXIT（`main.sh:175` 與 `main.sh:251-256`）

```bash
# 配置區新增
CLEANUP_RAN="false"

run_cleanup_once() {
    if [[ "$CLEANUP_RAN" == "true" ]]; then
        return 0
    fi
    CLEANUP_RAN="true"
    cleanup
}

on_exit() {
    local rc=$?
    run_cleanup_once || true
    exit "$rc"
}
```

1. `main.sh:175` 的 `cleanup` 呼叫改為 `run_cleanup_once`——成功路徑的
   log 順序與現在相同（清理訊息在「處理完成」banner 之前）。
2. 執行區（`main.sh:253` 旁）加 `trap on_exit EXIT`。
   六個 exit 路徑（NO_UPDATE、五個失敗點）從此都會清理。
3. `on_exit` 先保存 `$?` 再清理，最後 `exit "$rc"` 原樣回傳退出碼——
   不改變 wrapper 記錄的退出碼語意。
4. trap 內不用跨函數的 `local` 變數（v3 selftest 的教訓，
   `process.md` 第 17 節）。

### 3.5 保留語意（合併後）

| 規則 | 值 | 主導情境 |
|---|---|---|
| 天數上限 | mtime 超過 7 天（保留 8 天） | 低頻期（週末、假期） |
| 數量上限 | 每家族保留最新 24 個 | 平日（18 次/日 → 約 1.3 天） |
| 合併語意 | **兩者先到者為準** | 磁碟用量估計 ≈ 24 × 16.8 MB ≈ 403 MB（現況 4 家族與實測平均檔案大小；zone 數或資料量增加時會變） |

執行時機：每次 main.sh 結束（成功、NO_UPDATE、失敗）。
流程停滯時，下一個 iCall tick（300 秒內）就會清理，不再累積到告警。

---

## 4. 不變式（測試必驗）

1. `final/` 三檔在任何路徑下不被刪除、不被改動。
2. `.soa_cache/`、`/config/snmp/.{zone}_soa_serial.last`、`rpz_wrapper.log` 不碰。
3. 每家族最新 24 個檔案永不被數量上限刪除。
4. 退出碼與現行完全一致（成功 0、NO_UPDATE 0、失敗 1）。
5. wrapper log 的三個診斷樣式不變：「載入 N 個 Zones」「使用 dnsxdump 檔案」「處理完成」。

---

## 5. patch 交付形態（與 v4 同款）

| 項目 | 值 |
|---|---|
| patch 檔 | `patches/rpz_patch_phase1b_v1.sh`（單檔自足，內嵌完整新版 `main.sh`） |
| builder | `patches/build_patch_phase1b.sh`（deterministic，GitHub baseline 常數） |
| 子指令 | `check` / `apply` / `rollback <備份目錄>`，退出碼 0/1/2 |
| 原版 md5 | `main.sh` = `0041c1d74e5b8514dea506608607b8c6`（GitHub baseline `27415940`；每台先 check，同 R2-V4-03 紀律） |
| 安全機制 | 與 v4 相同：md5 整批核對、pgrep guard、備份 + md5sums、同目錄 mktemp+mv、`--reference` 權限沿用、安裝後驗證、rollback 純原版 gate + 目前檔案預檢 |
| 單檔差異 | 只有一個檔案，不需要 v4 的安裝順序與 `dep_violation()` |

部署順序（決定 2 的做法 B）：同一維護窗口，**先 v4、後 1B**，各自驗證。
rollback 反向：先退 1B、再退 v4。兩個 patch 無程式碼依賴
（1B 的 main.sh 不呼叫 `find_newest_file()`），可獨立退。
退掉 1B 後回到現行行為（遞迴 find、只成功才清），是已知且可接受的狀態。

gate 擴充：`tests/check_source_consistency.sh` 增加對 1B patch 的
內嵌一致性、md5 表、sidecar 檢查；「現行 patch 唯一」規則改為
每個 patch 家族（sigpipe、phase1b）各一個。

---

## 6. 測試計畫

### 6.1 patch 機制迴歸（fixture，`/var/tmp`，不碰 `/config`）

`tests/lab/f5_patch_1b_test.sh`（最終 112 斷言）：M1-M10 patch 機制
（check/apply/冪等/chattr 注入/rollback 純原版 gate 與目前檔案預檢）。

### 6.2 cleanup 功能測試（fixture OUTPUT_DIR）

最終範圍 F1-F12（審核三輪後）：

| # | 情境 | 驗收 |
|---|---|---|
| F1 | raw 100 + 3 家族各 100 | 每家族剩**最新的** 24 個 |
| F2 | 檔數 < 24 但 mtime 30 天前 | 被天數上限刪除 |
| F3 | 檔數 < 24 且 mtime 新 | 全保留，零輸出 |
| F5 | 非本命名格式檔案 | 數量上限不動；天數上限照舊 |
| F6/F8 | KEEP 邊界：abc / 0 / 24 / 99999 / 100000 / 36 位數 | 非法或超界警告並回退 24（P1B-02） |
| F6b | KEEP=7 | 生效 |
| F7 | --no-cleanup | 全保留 |
| F9 | 前綴含 `*` `?` `[` | WARN 跳過，不跨家族（P1B-03） |
| F10 | 數量上限刪除失敗（chattr +i） | WARN 據實回報，不謊稱保留數（P1B-04） |
| F11 | 天數上限刪除失敗 | WARN（P1B-04） |
| F12 | 合法前綴重疊 alpha / alpha_beta 各 30 | **各自 =24**，不跨家族（P1B-08） |

方法：`source main.sh` 後直接呼叫 `cleanup`（main.sh 有 source guard，
不會啟動主流程）。

### 6.3 trap 路徑測試（fixture OUTPUT_DIR，真實 main.sh 執行）

最終範圍 T1-T4（`LOG_FILE` 一律指向 fixture，不寫真實 /var/log/ltm）：

| # | 情境 | 驗收 |
|---|---|---|
| T1 | 步驟 2 失敗（exit 1） | 退出碼 1；trap 仍清理；final/ 不動 |
| T2 | 同上 + `--no-cleanup` | 不清理 |
| T3 | NO_UPDATE（exit 0，stub check_soa） | 退出碼 0；trap 清理到 24；final/ 不動 |
| T4 | NO_UPDATE + `--no-cleanup` | 不清理 |

### 6.4 LAB 真實 e2e

1. LAB 已有 v4，套 1B patch，check RC=0。
2. 在真實 `raw/`、`parsed/` 各播種 30 個 0-byte 舊時間戳假檔
   （本來就是暫存目錄，假檔就是要被清的對象）。
   **修訂（2026-08-23）**：假檔 mtime 必須設為 3 天前，不可用新 mtime。
   新 mtime 的假檔可能與真實 dnsxdump 同秒，被 `find_newest_file`（mtime
   比較）選中，把 0-byte 內容送進 pipeline。第一版 e2e 已實際踩中，
   見 `process.md` 第 22 節。e2e 腳本並必須在 apply 失敗時立即中止。
3. 受控執行（v4 SOP 的 handler 停/起序列 + before/after 證據）。
4. 驗收：run RC=0、播種過的家族**精確 =24**（0 不算通過）、
   `final/` mtime 正常更新、revision 增加、handler active/300。
5. rollback e2e：退回原版 main.sh、check、再 apply。

### 6.5 完成後

gate（含 1B 檢查）RC=0、兩個 sidecar RC=0、更新
`docs/reviews/REVIEW_HANDOFF_PHASE1B.md`（新檔）後送 Codex。

---

## 7. 風險與已知限制（誠實列出）

1. **數量上限依檔名字典序**，不是 mtime。本專案檔名含時間戳，兩者一致；
   人工放入不同命名的檔案不在數量上限保護範圍（天數上限仍涵蓋）。
2. **SIGKILL/OOM 不觸發 trap**。該次不清理，下一個 tick（300 秒）補上。
   持續累積只剩一種情境：iCall handler 本身停止——那已是更大的故障。
3. **無全流程 lock（CR-09 遺留）**：極端情況兩個 run 並發，prune 只刪
   「最舊的超額檔案」、寫入者只寫最新檔，兩端不相交；殘餘風險與現行相同。
4. **NO_UPDATE tick 也執行 cleanup** 是新行為。無刪除時零輸出，
   wrapper log 不膨脹；有刪除時每家族一行。
5. Phase 1B **不是** 4096 修正。KEEP=24 恰好也讓 `ls` 輸出遠低於
   4096 bytes，但那是 v4 的工作，不依賴本 patch。

---

## 8. 確認記錄（2026-08-23 使用者已全數核可）

以下四點為設計階段的提問，使用者已核可。之後兩輪審核造成的實作差異
（P1B-01~04、07、08）記錄在 `process.md` 第 23~24 節，本文件第 3 節的
程式碼樣本已同步為最終實作。原提問保留如下：

1. cleanup 靜默化（3.3 的 log 行為變更）可以接受？
2. KEEP=24 是「每家族 24 個」（磁碟用量估計 403 MB）。確認語意無誤？
3. patch 命名 `rpz_patch_phase1b_v1.sh` 可以？
4. 6.4 在真實 raw/parsed 播種假檔做 e2e，可以接受？

（已確認並完成實作。）
