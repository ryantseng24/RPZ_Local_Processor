# RPZ Local Processor — SIGPIPE(4096) 修正 patch

| 項目 | 值 |
|---|---|
| 現行版本 | `rpz_patch_sigpipe_v4.sh` |
| SHA-256 | `e407d6e7d0d12d1c6ca445d737208ab139437fd8504fe47d9b318754c1d37626` |
| 建置日期 | 2026-08-22 |
| 適用對象 | BIG-IP 17.1.x，RPZ_Local_Processor v1.2（腳本 md5 見第 2 節） |
| 規模 | 876 行（內嵌檔案 608 行 + 工具邏輯 268 行） |
| 外部審核 | 兩輪 CONDITIONAL GO（`docs/reviews/CODE_REVIEW_V4_STE100_20260822.md`、`docs/reviews/CODE_REVIEW_V4_ROUND2_STE100_20260822.md`）。V4-01～05 與 R2-V4-01～03 已修正並重驗 |

## 1. 問題摘要

三處 `ls -t <glob> | head -1` 在 `set -o pipefail` 下不安全。`ls` 輸出超過
4096 bytes（約 67 個暫存檔）時收到 SIGPIPE 以 141 結束，`set -e` 讓腳本
靜默中止，RPZ 黑名單停止更新。完整分析見 `process.md` 第 2 節，
完整實測數據見第 6 節。

判別方法：`rpz_wrapper.log` 出現「載入 N 個 Zones」後直接
「`[ERROR] RPZ 解析失敗`」，中間缺「`[INFO] 使用 dnsxdump 檔案:`」。

## 2. patch 內容

只取代三個檔案，其他檔案不動：

| 檔案 | 原版 v1.2 md5 | 修正版 md5 | 變更 |
|---|---|---|---|
| `utils.sh` | `3cab6cbca952f3780350e9882e5f7c11` | `b8294149dc978305e19bcd83fcb650e6` | 新增 `find_newest_file()`（純新增） |
| `parse_rpz.sh` | `bbe45c6f79b56922388d4af7aa6e7583` | `cefa71b6623632dd51c60a51cdf72196` | 改用 `find_newest_file()` |
| `generate_datagroup.sh` | `35547d33ce109945d1ca17e8eb241e0a` | `9599755a54db53652c070cd70ae92652` | 改用 `find_newest_file()`，先解析全部再發布 |

子指令三個：`check`（只讀）、`apply`（備份後套用）、`rollback <備份目錄>`。

兩條保護規則（審核 V4-02）：

1. **版本組合規則**：新版 `parse_rpz.sh` / `generate_datagroup.sh` 需要新版
   `utils.sh`。舊 utils + 新 consumer 的組合不可運作，`check` 以 RC=2 回報，
   `apply` 會警告並修復為全新版。
2. **rollback 只接受純原版 v1.2 備份**，且會先預檢目前的三個檔案：任一檔
   版本不明或缺少即拒絕（R2-V4-02）。兩種拒絕都發生在改任何檔案之前（RC=2）。
   依賴違規組合（各檔皆為已知版本）可通過預檢，由純原版還原修復。

## 3. 部署 SOP（每台設備）

1. 在工作機核對 patch 完整性。**patch 與 sidecar 必須在同一目錄**：
   ```
   cd patches
   shasum -a 256 -c rpz_patch_sigpipe_v4.sh.sha256
   ```
2. 傳兩個檔案到設備：
   ```
   scp rpz_patch_sigpipe_v4.sh rpz_patch_sigpipe_v4.sh.sha256 admin@<設備>:/var/tmp/
   ```
3. 在設備上再核對一次：
   ```
   cd /var/tmp && sha256sum -c rpz_patch_sigpipe_v4.sh.sha256
   ```
4. 檢查版本（不改任何檔案）：
   ```
   bash /var/tmp/rpz_patch_sigpipe_v4.sh check
   ```
   必須顯示「全部是原版 v1.2，可以套用」。
   顯示「版本不明」或「版本組合不可運作」：**停止**，回報 check 的完整輸出。
5. 套用：
   ```
   bash /var/tmp/rpz_patch_sigpipe_v4.sh apply
   ```
   記下輸出中的備份目錄路徑（`/var/tmp/rpz_patch_backup_<時間>`）。
6. 確認：
   ```
   bash /var/tmp/rpz_patch_sigpipe_v4.sh check
   ```
   必須顯示「已全部套用修正」。
7. 功能驗證（受控執行，逐條輸入，**保留終端機完整輸出作為驗收證據**）：
   ```
   tmsh modify sys icall handler periodic rpz_processor_handler status inactive
   ```
   ```
   pgrep -f "RPZ_Local_Processor/scripts"
   ```
   等到上面這條沒有輸出（RPZ 程序靜止；單次執行約 1-2 分鐘）再繼續。
   記錄測試前（before）數值：
   ```
   ls -l --time-style=full-iso /config/snmp/rpz_datagroups/final/
   ```
   ```
   tmsh list sys file data-group rpztw | grep -E "revision|size|last-update-time"
   ```
   執行測試，並在下一條指令**立刻**保存退出碼（互動 shell 不會自動顯示
   `$?`，再打其他指令就會被蓋掉）：
   ```
   bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
   ```
   ```
   MAIN_RC=$?; echo "main.sh RC=${MAIN_RC}"
   ```
   記錄測試後（after）數值：
   ```
   ls -l --time-style=full-iso /config/snmp/rpz_datagroups/final/
   ```
   ```
   tmsh list sys file data-group rpztw | grep -E "revision|size|last-update-time"
   ```
   驗收條件（全部成立才算通過）：
   - `main.sh RC=0`
   - 測試輸出含「`使用 dnsxdump 檔案:`」與「`處理完成`」
   - `final/` 三檔 mtime 比 before 新
   - revision 比 before 增加
   - size 非零，且與 before 同一個量級（LAB 參考值：rpztw 約 2.2 MB）
   然後恢復 handler 並存檔：
   ```
   tmsh modify sys icall handler periodic rpz_processor_handler status active
   ```
   ```
   tmsh save sys config
   ```
   ```
   tmsh list sys icall handler periodic rpz_processor_handler status interval
   ```
   必須是 `status active`、`interval 300`。
   **無論驗證成功或失敗，都必須把 handler 恢復為 active 並存檔。**
   替代（被動）驗證：不停 handler，等 log 出現新的「`使用 dnsxdump 檔案:`」。
   注意：iCall 每 300 秒觸發，但 SOA 未變時不做更新；真實更新間隔 5～80 分鐘，
   **300 秒不是被動驗證的等待上限**。
8. 需要退回時：
   ```
   bash /var/tmp/rpz_patch_sigpipe_v4.sh rollback /var/tmp/rpz_patch_backup_<時間>
   ```
   rollback 只接受**純原版**備份（步驟 5 從全原版狀態產生的那個）。

**rollout 順序**：先單機 canary，通過後才推下一台。不要四台同時變更。

## 4. 退出碼

| 退出碼 | 意義 | 處置 |
|---|---|---|
| 0 | 成功（含「已套用，無需動作」） | 繼續下一步 |
| 1 | 執行中發生錯誤 | 看錯誤訊息，回報 |
| 2 | 前置條件不符（版本不明 / 版本組合不可運作 / 備份不是純原版 / rollback 目前檔案版本不明或缺少 / RPZ 程序執行中 / 參數錯誤） | 依訊息處理後重試 |

## 5. 操作注意

1. `apply` 與 `rollback` 會拒絕在 RPZ 程序執行中操作，並列出偵測到的程序。
   iCall 週期 300 秒、單次執行約 1-2 分鐘，等它結束再重試。
2. 其他 cmdline 含腳本路徑的程序（例如開著 `vi .../scripts/main.sh`）也會
   觸發此防護。訊息會列出程序，關掉後重試。
3. `apply` 中斷後直接重跑會補齊剩下的檔案。中斷後重跑產生的第二個備份是
   混合狀態，rollback 會**自動拒絕**它；退回原版一律用從全原版狀態產生的
   純原版備份。
4. `check` 回報「版本組合不可運作」（RC=2）代表舊 utils 配新 consumer，
   會出現 `find_newest_file: command not found`。執行 `apply` 即可修復為全新版。
5. 已知限制：`apply` 當下若 iCall 恰好已用舊腳本啟動，該輪可能仍以舊缺陷
   失敗一次，下一輪（300 秒後）自動用新版恢復。pgrep 防護是 best-effort，
   不是 lock。
6. 本 patch 不清理暫存檔。磁碟壓力依《RPZ_手動清檔作業說明_20260821.md》
   處理。保留策略改造屬於 Phase 1B，另立變更。
7. patch 後暫存檔數量不影響正確性（LAB 實測 300 檔仍 0 失敗）。

## 6. LAB 驗證記錄（2026-08-22，BIG-IP 17.1.3.1）

證據對應的建置：迴歸測試對應現行建置 `e407d6e7…`；失敗曲線對應內嵌
payload（三檔 md5 未變，跨建置有效）；受控 e2e 對應 `d058b2cf…` 建置
（此後只改 rollback 預檢，審核第二輪判定不需重跑 e2e），且審核者以
獨立腳本重跑過一次（revision 16 -> 17，等待靜止成功）。

功能前後對照（同一支 probe，真實 `parse_rpz.sh`，每組 10 次；payload 未變）：

| raw 檔數 | ls 輸出 | 原版失敗率 | 修正版失敗率 |
|---|---|---|---|
| 67 | 4087 B | 0/10 | 0/10 |
| 80 | 4880 B | 2/10 | 0/10 |
| 141 | 8601 B | 7/10 | 0/10 |
| 179 | 10919 B | 8/10 | 0/10 |
| 300 | 18300 B | 9/10 | 0/10 |

原版失敗全為 exit 141（SIGPIPE）。

patch 工具迴歸測試：`tests/lab/f5_patch_v4_test.sh`（fixture 在 `/var/tmp`，
不碰 `/config`），涵蓋第一輪審核第 7 節全部 12 案例、修復路徑案例，
加上第二輪 R2-V4-02 的三個 rollback 預檢案例，**78 項斷言全數 PASS**：

| 案例 | 內容 |
|---|---|
| 1-3 | 原版 check、正常 apply（備份+md5+無殘留）、重複 apply 冪等 |
| 4-5 | 三個檔案各自 apply 失敗（chattr +i 注入）；中間狀態正確；續跑補齊 |
| 6 | 正常 rollback |
| 7-8 | 三個檔案各自 rollback 失敗；中間狀態正確；續跑還原 |
| 9 | 八種 o/n 組合：三種「舊 utils + 新 consumer」全部 RC=2 |
| 10 | 純原版備份 rollback RC=0 |
| 11 | 混合備份 rollback RC=2，且拒絕發生在改檔之前 |
| 13 | 不可運作組合的 apply 修復路徑（警告 + 修復 + 該備份被拒） |
| 14 | 目前檔案版本不明 + 純原版備份：RC=2，三檔全未被改動（R2-V4-02） |
| 15 | 目前檔案缺失 + 純原版備份：RC=2，無部分還原（R2-V4-02） |
| 16 | 依賴違規組合（onn）+ 純原版備份：RC=0，修復為全原版（R2-V4-02） |
| 12 | 全程無殘留暫存檔 |

真實目錄完整週期：`check`（已套用）→ `rollback` 到純原版 → `apply` 全部 RC=0。

受控 e2e（SOP 步驟 7 全程照做）：handler inactive → `main.sh --force` RC=0、
診斷行出現、`final/` 三檔更新、**revision 15 → 16** → handler active →
`tmsh save sys config` → 確認 active / 300。

## 7. 版本沿革

| 版本 | 狀態 | 說明 |
|---|---|---|
| v1 / v2 | 已淘汰 | 開發過程版本 |
| v3 | 封存於 `patches/archive/` | 1596 行（工具邏輯 987 行）。三輪外部審核 CONDITIONAL GO。功能正確，但工具邏輯與功能變更比例 33:1，判定過度設計。留作審核紀錄 |
| v4 | **現行** | 876 行（工具邏輯 268 行）。兩輪審核 CONDITIONAL GO；第一輪修正 V4-01～05（SOP 受控驗證、版本組合規則、純原版 rollback、builder 不依賴 git HEAD、gate 驗 v4），第二輪修正 R2-V4-01～03（SOP 記錄 before/after 與 `MAIN_RC`、rollback 目前檔案預檢、builder 註解改為 GitHub baseline）。以 `build_patch_v4.sh` 產生，deterministic |

v4 重構與審核回應的完整記錄見 `process.md` 第 19~21 節。

---

## 8. Phase 1B patch（第二個 patch：暫存檔保留策略）

| 項目 | 值 |
|---|---|
| 檔案 | `rpz_patch_phase1b_v1.sh` + `.sha256` |
| SHA-256 | `aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785` |
| 規模 | 591 行（內嵌 main.sh 357 行 + 工具邏輯 234 行） |
| 變更 | 只換 `main.sh`（原版 `0041c1d7…` -> 修正版 `d1e1f688…`） |
| 前提 | **先套用並驗證 v4**。兩個 patch 無程式碼相依，可各自 rollback |
| 外部審核 | 兩輪 CONDITIONAL GO（`docs/reviews/CODE_REVIEW_PHASE1B_STE100_20260823.md`、`…_ROUND2_…`）。P1B-01～04、07、08 已修正並重驗；P1B-05/06 屬安裝包（HOLD），不影響 patch |
| 設計文件 | `docs/PHASE1B_DESIGN_20260823.md` |

### 8.1 修正內容

1. cleanup 的 `find` 範圍縮小到 `raw/` 與 `parsed/`（`-maxdepth 1`）。
   `final/` 從此不在任何刪除範圍內。
2. 數量上限：每個檔案家族保留最新 24 個（環境變數 `RPZ_KEEP_COUNT` 可調）。
   與 8 天的天數上限並用，取先到者。磁碟用量估計約 403 MB
   （現況家族數與平均檔案大小的估計值，不是位元組配額）。
3. `trap EXIT`：成功、NO_UPDATE、失敗路徑都會清理。流程停滯時
   下一個 iCall tick（300 秒）就清理，不再累積到磁碟告警。
4. log 行為：cleanup 無事可做時零輸出；有刪除時每家族一行摘要；
   **刪除失敗會 WARN 並回報實際數字**（P1B-04），不會謊稱已保留 24。
5. `RPZ_KEEP_COUNT` 接受範圍 1-99999，範圍外回退 24（P1B-02 防溢位）。
6. 家族前綴只接受 `A-Za-z0-9._-`；含 glob 字元的異常檔名跳過數量上限
   並 WARN，只由天數上限管理（P1B-03）。
7. 家族成員以**精確形狀**選取：`<前綴字面>_<8位日期>_<6位時間><副檔名>`。
   合法前綴互相包含（如 `alpha` 與 `alpha_beta`）不會跨家族刪除（P1B-08）。

### 8.2 部署 SOP

與 v4 的第 3 節相同流程，差異只有：

1. 檔名換成 `rpz_patch_phase1b_v1.sh`（步驟 1~6、8）。
2. 順序：**同一維護窗口，先 v4、後 1B**，各自跑步驟 7 驗證。
   退回順序相反：先退 1B、再退 v4。
3. 1B 的備份目錄前綴是 `/var/tmp/rpz_patch1b_backup_<時間>`。
4. 步驟 7 驗收條件多一項：若 raw/parsed 檔數原本超過 24，
   log 會出現「數量上限清理」且各家族剩 24 個。

### 8.3 LAB 驗證記錄（2026-08-23，BIG-IP 17.1.3.1，審核輪 2 修正後建置 `aa97950e…`）

1. 迴歸測試 `tests/lab/f5_patch_1b_test.sh`：**112 斷言全 PASS**（含 F12
   前綴重疊——舊建置實測 FAIL、新建置 PASS）。
   M1-M10（patch 機制）、F1-F12（含 P1B-02 KEEP 邊界值 0/24/99999/100000/36 位數、
   P1B-03 不安全前綴 `*` `?` `[` 不跨家族、P1B-04 刪除失敗據實 WARN 與
   天數上限失敗 WARN）、T1-T4（失敗與 NO_UPDATE 路徑、--no-cleanup；
   `LOG_FILE` 指向 fixture）。
2. 受控 e2e `tests/lab/f5_e2e_1b_controlled.sh`（fail-closed 版）：
   **20 斷言全 PASS**。五個拒絕案例先驗證（無 `--lab-only`、錯誤主機名
   〔本機執行〕、`E2E_CONFIRM` 未設 / 錯誤、handler 非 active），
   全部 RC=2 且無任何變更。正式執行：apply/check gate -> 120 個合成檔
   （manifest 記錄）-> `main.sh --force` RC=0 -> 四家族各「刪除 22 保留 24」
   -> revision 22 -> 23、size 2,243,094、mtime 更新 -> manifest 全清 ->
   handler active/300 + `save sys config` 全數斷言通過。
3. 真實目錄 rollback -> 再 apply 全 RC=0；v4 三支不受影響。

**測試事故記錄**：第一版 e2e 腳本缺 apply gate、且假檔用了新 mtime，
造成 LAB 的 `final/` 被 0-byte 內容覆寫一次（TMOS 內 DataGroup 未受影響）。
已修復並促成本 fail-closed 版驅動器（審核 P1B-01）。完整分析見
`process.md` 第 22~24 節——這同時是 CR-10 的活體證據，審核已把
CR-10 列為 Phase 2 P0。

## 9. 勘誤（payload 註解的章節號筆誤）

`main.sh`（與兩個 patch 的內嵌副本）有兩處註解引用了錯誤的
`process.md` 章節號：

| 註解位置 | 寫的是 | 實際應為 |
|---|---|---|
| `prune_family()` 的 SIGPIPE 根因引用 | 第 13 節 | 第 2 節（實測數據第 6 節） |
| `cleanup()` 的 final/ 實測引用 | 第 15 節 | 第 27 節 |

只是註解，不影響任何行為。因為修改會變更已審核並交付的 patch
SHA-256（`aa97950e…` 已寫入客戶 SOP），本次不重建，
排入下一次 payload 變更時一併修正。
`docs/PHASE1B_DESIGN_20260823.md` 第 3 節的程式碼樣本與實作
逐字一致，因此保留同樣的筆誤。
