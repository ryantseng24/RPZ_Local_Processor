# REVIEW_HANDOFF_PHASE1B — Phase 1B patch 審核交接

**初版**: 2026-08-23（送審）
**本版**: 2026-08-23（第二輪審核回應後更新）
**第二輪判定**: CONDITIONAL GO；P1B-02/03/04 關閉、P1B-01 降 Medium 部分關閉、
新增 P1B-08（`CODE_REVIEW_PHASE1B_ROUND2_STE100_20260823.md`，SHA-256
`f72f0298…` 已核對）。**P1B-08、P1B-01 殘餘、P1B-07 已全部修正並重驗。**

## 0. 第二輪 findings 回應摘要（最新）

| 編號 | 修正 | 證據 |
|---|---|---|
| P1B-08（Medium）合法前綴重疊跨家族刪除 | 家族選擇器改為精確形狀 `<前綴字面>_<8位日期>_<6位時間><副檔名>`（`prune_family()`，前綴引號展開不作 glob）；raw 選擇器同步收緊 | 舊建置 LAB 重現 alpha=0；新建置迴歸 F12：alpha=24、alpha_beta=24、最新保留最舊刪除、final/ 不動。**F12 在舊建置 FAIL、新建置 PASS** |
| P1B-01（Medium）e2e 殘餘 | 13 項修正全數落實：播種逐檔 gate（拒絕覆蓋既存、建立/touch 都驗證、先記 manifest）、120 檔存在與 mtime < now−2天 驗證、check RC 與文字分開驗、家族數精確 =24（0 不通過）、manifest 逐檔刪除驗證且有殘留不清空、trap 回報恢復/存檔失敗 | 5 個拒絕案例 RC=2 且狀態零變更（實測驗證 md5/revision/合成檔數）；注入案例（預置衝突路徑）RC=1、handler 恢復 active/300、revision 不變、無殘留；正式 e2e PASS=20 FAIL=0 |
| P1B-07（Low）記錄不一致 | handoff 數字全面更新（本檔）；設計文件程式碼樣本改為最終實作、第 8 節改為確認記錄；README「硬上限」改「估計」；STATUS 第 11 節改為已完成；迴歸標頭 F1-F12/T1-T4；process 第 22 節標註歷史數字、第 24 節記錄本輪 | 各文件已同步 |

重驗：迴歸 **PASS=112 FAIL=0**、gate PASS=31 FAIL=0、sidecar RC=0、
deterministic 重建一致、e2e PASS=20 FAIL=0（revision 22->23）。

---

**第一輪判定**: patch CONDITIONAL GO / e2e 驅動器 NO-GO / v1.2.2 包 NO-GO /
CR-10 升 Phase 2 P0（`CODE_REVIEW_PHASE1B_STE100_20260823.md`，
SHA-256 `7329d2c8…` 已核對）。**P1B-01～04 已修正並重驗；05/06 屬安裝包，
維持 HOLD；07 記錄項全數完成。**
**判定格式**: GO / CONDITIONAL GO / NO-GO，findings 編號 P1B-xx。

---

## 0-1. 第一輪 findings 回應摘要（歷史記錄）

| 編號 | 修正 | 證據 |
|---|---|---|
| P1B-01 e2e 非 fail-closed | 驅動器重寫：`--lab-only` + 主機名 `cdns.ryantseng.work`（`uname -n`，無 bypass）+ `E2E_CONFIRM` 完整確認 + handler 初始 active/300；manifest 只刪自建檔；revision/size/mtime/診斷行/save/最終 handler 全數斷言 | 五個拒絕案例全 RC=2（錯誤主機名在 macOS 本機驗）；正式執行 **PASS=20 FAIL=0**，revision 21->22 |
| P1B-02 KEEP 溢位 | 接受範圍 1-99999（`^[1-9][0-9]{0,4}$`），範圍外回退 24 | 迴歸 F8 系列：0 / 100000 / 36 位數 -> 警告 + 24；99999 有效；24 有效 |
| P1B-03 glob 前綴跨家族 | 前綴限 `A-Za-z0-9._-`；不安全前綴 WARN 並跳過數量上限 | 迴歸 F9：`*` `?` `[` 前綴下 alpha=24、beta=24、異常檔保留 |
| P1B-04 刪除失敗被隱藏 | 逐檔計數；失敗 WARN 據實回報；find 失敗也 WARN；仍不影響主流程 | 迴歸 F10（immutable：WARN「失敗 1 個」、實際 25、解鎖後 24）、F11（天數上限 WARN） |
| P1B-05/06 安裝包 | 不修，v1.2.2 維持 **HOLD**（審核 10.4 允許）；gate PASS 不作為可安裝性宣稱 | `dist/DO_NOT_DEPLOY.md` 已更新 |
| P1B-07 記錄 | NO_UPDATE 永久測試 T3/T4、`LOG_FILE` fixture、LAB README、設計文件狀態與 403 MB 措辭、package changelog | 迴歸 T3/T4；各文件已更新 |

重驗（輪 1 當時的數字）：迴歸 PASS=104、gate PASS=31、sidecar RC=0、
deterministic 一致。完整記錄 `process.md` 第 23 節。最新數字見上方第 0 節。
**前情**: v4（SIGPIPE 修正）已兩輪 CONDITIONAL GO 且 findings 全關
（`REVIEW_HANDOFF_V4.md`）。Phase 1B 是同一維護窗口的第二個 patch，
先 v4、後 1B，各自可 rollback。

---

## 1. 受審 artifacts

| 檔案 | md5 | 行數 | 角色 |
|---|---|---|---|
| `patches/rpz_patch_phase1b_v1.sh` | `e44052005a176071f8049d4a8a9ab948` | 591 | patch 本體（內嵌 main.sh 357 + 邏輯 234） |
| `patches/rpz_patch_phase1b_v1.sh.sha256` | — | 1 | sidecar |
| `patches/build_patch_phase1b.sh` | `8cadfaa994ebfe13a2f55348b0723f36` | 303 | builder（GitHub baseline 常數，deterministic） |
| `scripts/main.sh`（修正版 payload） | `d1e1f688d939a5a5e87282605d0e3eed` | 353 | **功能變更本體**（原版 `0041c1d7…` 256 行） |
| `tests/lab/f5_patch_1b_test.sh` | `64ee04a13fbc68372e70a3ef9338078b` | 365 | 迴歸測試（112 斷言，含 F12 前綴重疊） |
| `tests/lab/f5_e2e_1b_controlled.sh` | `84f57120eda3b1d19756a86f43670a98` | 173 | fail-closed 受控 e2e 驅動（20 斷言 + 5 拒絕 + 注入案例） |
| `tests/check_source_consistency.sh` 第 9 節 | — | — | gate 擴充（PASS=31 FAIL=0） |
| `docs/PHASE1B_DESIGN_20260823.md` | — | — | 設計文件（狀態已更新） |
| `patches/README.md` 第 8 節 | — | — | 部署 SOP |

patch SHA-256：
`aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785`

**與 v4 的差異**：patch 工具邏輯是 v4 審過的同款（單檔版：無安裝順序
與 dep_violation，其餘 gate 全保留——純原版備份、目前檔案預檢、
md5 整批核對、pgrep guard、原子取代）。**審核重點應是 payload
（main.sh 的功能變更）**，工具邏輯可對照 v4 差異審。

---

## 2. payload 功能變更（main.sh，原版 256 行 -> 修正版 353 行）

| # | 變更 | 理由與依據 |
|---|---|---|
| 1 | cleanup 的 find 從遞迴掃 `OUTPUT_DIR` 縮小到 `raw/` `parsed/`（`-maxdepth 1`） | `final/` 是 DataGroup source-path。實測 D：加 trap 而不縮小範圍，停滯機器的 final/ 被刪到 0（process.md 第 15 節） |
| 2 | 新增 `prune_family()` `prune_parsed_families()`：每家族保留最新 24 個（精確時間戳形狀選取） | 純 bash 零管線；家族前綴由檔名推導，不解析 zonelist（v3 cleanup 的教訓）；bash 4.2 空陣列 set -u 陷阱已防 |
| 3 | `RPZ_KEEP_COUNT` 環境變數（預設 24），非法值回退並警告 | 使用者定案 KEEP=24（磁碟上限 403 MB、平日回溯 12 小時） |
| 4 | `trap on_exit EXIT` + `run_cleanup_once`：全部 exit 路徑清理，退出碼原樣保留 | 六個 exit 路徑中原本只有成功路徑清理；停滯即累積到磁碟告警 |
| 5 | cleanup 靜默化（無刪除零輸出） | trap 使 cleanup 每日約 288 次（NO_UPDATE tick），保留 banner 會使 wrapper log 膨脹約三成 |
| 6 | 補結尾 newline | 原版 main.sh 缺結尾 newline（與 v1.2 utils.sh 同型） |
| 7 | 缺陷 A 死碼保留原樣 + 註解 | 範圍紀律；Phase 2 |

不變式（已測）：final/ 不碰、退出碼語意不變、三個 wrapper log 診斷樣式不變。

---

## 3. LAB 驗證證據（2026-08-23，BIG-IP 17.1.3.1 實機）

1. 迴歸 `f5_patch_1b_test.sh`：**PASS=112 FAIL=0**（歷史：輪 1 前 66、輪 1 後 104）
   - M1-M10：patch 機制（含版本不明/缺檔/混合備份拒絕、chattr 注入與續跑）
   - F1-F12：保留最新 24、天數上限、零輸出、外來檔名、KEEP 邊界值
     （0/24/99999/100000/36 位數）、不安全前綴（`*` `?` `[`）、刪除失敗
     據實 WARN、天數上限失敗 WARN、**合法前綴重疊（alpha/alpha_beta）**
   - T1-T4：失敗路徑與 NO_UPDATE 路徑 trap 清理、--no-cleanup、LOG_FILE fixture
2. 受控 e2e `f5_e2e_1b_controlled.sh`（fail-closed）：**PASS=20 FAIL=0**（歷史：初版 5 斷言）
   四道身分防護 -> 120 合成檔逐檔 gate 與 mtime 驗證 ->
   `main.sh --force` RC=0 -> 四家族**精確 =24** ->
   final/rpztw 2,243,094 bytes -> revision 22 -> 23 -> manifest 全清 ->
   handler active/300 + save（全數斷言）。
3. 真實目錄 rollback -> 再 apply 全 RC=0；v4 三支不受影響。
4. gate PASS=31 FAIL=0；sidecar RC=0；deterministic 重建一致。

---

## 4. 必須告知審核者的測試事故（process.md 第 22.3 節）

第一版 e2e 腳本缺 apply gate 且假檔用新 mtime，讓 0-byte 假 dump 被
原版 pipeline 選中，LAB 的 final/ 被覆寫為 0 bytes 一次。TMOS 內
DataGroup 未受影響（update 對 0 筆跳過）。已修復並以第二版 e2e 重驗。

**附帶發現**：generate_datagroup（v4 payload，本次未改）對 0-byte
解析檔只 WARN 就發布 final/。這是 CR-10 的活體證據。
建議審核者確認：此風險是否影響 1B 的 GO（我的立場：不影響——1B 未改變
該行為，且 1B 的 KEEP 保留策略與其無交互；CR-10 應列 Phase 2 最高優先）。

---

## 5. 已知限制

1. 數量上限依檔名字典序（檔名含時間戳，與時間序一致）；
   非本命名格式檔案只受天數上限管。
2. SIGKILL/OOM 不觸發 trap；下一個 tick（300 秒）補清。
3. 無全流程 lock（CR-09 遺留），與現行相同。
4. NO_UPDATE tick 執行 cleanup 是新行為；無刪除時零輸出。
5. Phase 1B 不是 4096 修正（實測見 STATUS 第 9 節）。

---

## 6. 給審核者的問題

1. main.sh 的新增邏輯（256 -> 353 行；prune/trap/KEEP）是否有遺漏的 failure path？
2. trap on_exit 對退出碼語意的保留是否完備（含 ERR trap 並存）？
3. cleanup 靜默化與 NO_UPDATE tick 執行清理，操作面是否可接受？
4. 第 4 節的事故是否影響 1B 判定？CR-10 升級 Phase 2 優先度的建議是否同意？

## 7. 環境前提

同 v4：BIG-IP 17.1.3.1 / bash 4.2.46 / coreutils 8.22 / admin uid=0。
`touch -d`、`declare -A`（函數內 local 語意）、`trap EXIT` 皆在 LAB 實機驗過。

## 8. 建議閱讀順序

1. 本文件
2. `docs/PHASE1B_DESIGN_20260823.md`（設計與依據）
3. `patches/rpz_patch_phase1b_v1.sh`（受審本體；工具邏輯對照 v4）
4. `tests/lab/f5_patch_1b_test.sh`、`tests/lab/f5_e2e_1b_controlled.sh`
5. `process.md` 第 22~24 節（實作、事故、兩輪審核回應）
6. `patches/README.md` 第 8 節（部署 SOP）
