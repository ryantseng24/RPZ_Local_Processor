# REVIEW_HANDOFF_V4 — v4 patch 審核交接

**初版**: 2026-08-22（送審）
**本版**: 2026-08-22（第二輪審核回應後更新）
**第一輪判定**: CONDITIONAL GO（`CODE_REVIEW_V4_STE100_20260822.md`），V4-01～05 已修正。
**第二輪判定**: CONDITIONAL GO（`CODE_REVIEW_V4_ROUND2_STE100_20260822.md`，
SHA-256 `7577ca04…` 已核對）。**R2-V4-01～03 已全部修正並重驗。**
**判定格式**: GO / CONDITIONAL GO / NO-GO，findings 編號 V4-xx / R2-V4-xx。

---

## 0. 第二輪 findings 回應摘要

| 編號 | 修正 | 證據 |
|---|---|---|
| R2-V4-01（Medium）SOP 證據不完整 | SOP 步驟 7 改為 before 記錄（final/ mtime、revision、**size**、last-update-time）→ 測試 → 下一條立刻 `MAIN_RC=$?; echo` → after 記錄 → 五項驗收條件。標注保留完整終端機輸出 | `patches/README.md` §3 步驟 7 |
| R2-V4-02（Medium）rollback 不驗目前 target | `do_rollback()` 加目前檔案預檢：逐檔 `state_of`，非 orig/new 即 RC=2，發生在改任何檔案之前；依賴違規組合可通過（由純原版修復） | 迴歸案例 14（unknown → RC=2 三檔全未動）、15（missing → RC=2 無部分還原）、16（onn → RC=0 全原版）。LAB **PASS=78 FAIL=0** |
| R2-V4-03（Low）builder 註解不實 | 註解改為「審核核定的 GitHub baseline（commit `27415940…`）」，明載非四台實測證據、每台先 check | `patches/build_patch_v4.sh` 常數區註解；本地已核實四台擷取資料無腳本 md5 |

重驗（審核第 8 節範圍）：sidecar RC=0、deterministic 重建一致、
gate PASS=26 FAIL=0 RC=0、LAB 迴歸 PASS=78 FAIL=0 RC=0。
payload 未變，依審核指示未重跑 4096 curve 與 e2e。
未恢復 transaction / recovery staging / cleanup / embedded selftest。

---

## 0-1. 第一輪 findings 回應摘要

| 編號 | 修正 | 證據 |
|---|---|---|
| V4-01（High）SOP 併發與被動驗證上限 | SOP 步驟 7 改受控序列（停 handler → 等靜止 → 測試 → 恢復 → save config）；被動驗證改「等真實更新事件」 | `patches/README.md` §3 步驟 7；受控 e2e 實測：RC=0、revision 15→16、handler 恢復 active/300、config 已存 |
| V4-02（Medium）provider 依賴缺失 | patch 新增 `dep_violation()`：check 對「舊 utils + 新 consumer」回 RC=2；apply 警告並修復；rollback 只接受純原版備份（改檔前拒絕）；還原後逐檔驗證 | `tests/lab/f5_patch_v4_test.sh` 案例 9（八組合，三種不可運作組合全 RC=2）、案例 11（混合備份拒絕且狀態不變）、案例 10、13 |
| V4-03（Medium）builder 依賴 git HEAD | 原版 md5 改為審核核定常數，移除 git 依賴 | 驗收實測：暫存 repo commit 新版 source 後從乾淨 checkout 重建，RC=0，SHA-256 與 release 值逐位一致 |
| V4-04（Medium）gate 驗 v3 | gate 改驗 v4（v4 內嵌格式與 md5 表）；v3 移至 `patches/archive/`；新增 sidecar 檢查 5c | `tests/check_source_consistency.sh` 重跑 **PASS=26 FAIL=0，RC=0** |
| V4-05（Low）sidecar 驗證目錄 | 文件改為 `cd patches` 後驗證，標注同目錄需求 | `patches/README.md` §3 步驟 1；本文件第 1 節指令 |

Release conditions 1-13 全部完成；本文件更新即 condition 14。
未恢復 v3 的 transaction、recovery staging、cleanup、內嵌 selftest。
完整記錄見 `process.md` 第 20 節。

---

## 1. 受審 artifacts（第一輪修正後）

| 檔案 | md5 | 行數 | 角色 |
|---|---|---|---|
| `patches/rpz_patch_sigpipe_v4.sh` | `bf858c36bac342f4ab5e2f7ff5c9d0bc` | 876 | patch 本體（內嵌 608 + 邏輯 268） |
| `patches/rpz_patch_sigpipe_v4.sh.sha256` | — | 1 | 外部完整性 sidecar |
| `patches/build_patch_v4.sh` | `70a4afd400f7777dad33ee2c98e9a727` | 361 | builder（GitHub baseline 常數，不依賴 git HEAD） |
| `patches/README.md` | `f8d0c75b820135af3a399593196683d8` | 210 | 部署 SOP（含受控驗證與 before/after 證據記錄） |
| `tests/check_source_consistency.sh` | `385e5b745d3bff4120a4969ce12a71f7` | 264 | project gate（驗 v4） |
| `tests/lab/f5_patch_v4_test.sh` | `bbf104d8a52b4d3b61c73a478acf36e6` | 279 | 獨立迴歸測試（78 斷言，含 R2-V4-02 案例） |

patch 本體 SHA-256：
`e407d6e7d0d12d1c6ca445d737208ab139437fd8504fe47d9b318754c1d37626`

**不在範圍（out of scope）**：

1. 內嵌的三支修正版腳本（`utils.sh` `b8294149…`、`parse_rpz.sh` `cefa71b6…`、
   `generate_datagroup.sh` `9599755a…`）。md5 與 v3 內嵌相同，功能已由
   前三輪審核與 LAB 驗證覆蓋。
2. `patches/archive/rpz_patch_sigpipe_v3.sh`：封存審核紀錄，已非現行 patch。
3. Phase 1B（保留策略、`trap EXIT`、find 範圍）：另立變更。

**審核者可自行執行的驗證**（patch 與 sidecar 必須在同一目錄）：

```
cd patches
shasum -a 256 -c rpz_patch_sigpipe_v4.sh.sha256
```

```
bash patches/build_patch_v4.sh        # 重建，SHA-256 應不變（deterministic）
bash tests/check_source_consistency.sh   # 應 PASS=26 FAIL=0, RC=0
```

builder 內建：三個修正版 md5 斷言、原版 md5 審核核定常數、delimiter 檢查、
`bash -n`、round-trip 抽出比對、佔位符殘留檢查。

---

## 2. v3 -> v4 結構對照

| v3 區段 | v3 行數 | v4 處置 | 理由 |
|---|---|---|---|
| cleanup / cleanup-dry | 275 | **移除** | 與 4096 修正無關。暫存檔由手動作業文件與 Phase 1B 承接 |
| do_selftest | 178 | **移除** | LAB 同平台迴歸測試檔 + SOP 受控真實驗證取代 |
| recovery staging（R2-02 回應） | 約 60 | **以安裝順序 + 版本組合規則取代** | utils.sh 純新增最先安裝；中斷點組合可運作（實測）；V4-02 補上依賴規則與純原版 rollback gate |
| do_apply | 155 | 保留，精簡 + 修復警告 | |
| do_rollback | 94 | 保留，精簡 + 純原版 gate + 還原後驗證 | |
| do_check | 86 | 保留 + md5 欄 + 組合規則 | 兼作四台資料收集工具 |

與 REV2 第 9 節（審核者自列的過度設計邊界）方向一致。

---

## 3. REV2「工程底線」在 v4 的對應

| 底線 | v4 實作 |
|---|---|
| 精確版本 | ORIG/NEW md5 表 + `state_of()` + `dep_violation()`；check/apply 對版本不明或組合不可運作拒絕；rollback 另有目前檔案預檢（R2-V4-02 後） |
| 外部完整性 | `.sha256` sidecar；SOP 步驟 1（工作機，cd patches）與步驟 3（設備）各驗一次；gate 檢查 5c |
| 固定 production path | `SCRIPTS_DIR` 寫死常數，無環境變數覆寫 |
| 非零錯誤 | `set -euo pipefail`；退出碼 0/1/2 |
| 失敗可回復 | 備份 + `md5sums.txt`、純原版 rollback、冪等 re-apply、安裝順序 |
| 真實功能驗證 | SOP 步驟 7 受控序列（V4-01 修正後） |
| handler 恢復 | SOP 明定成功或失敗都恢復 active 並 `save sys config`，有確認步驟 |

---

## 4. 設計立場（第一輪已接受）

1. 不做 quiesce 於 apply/rollback：pgrep guard（best-effort）+ 安裝順序。
   審核 Q2 接受，條件是文件化極端時序限制 —— 已寫入 README 注意 5。
   功能驗證（SOP 步驟 7）依 V4-01 改為必須停 handler。
2. 無 selftest 子指令：由 `tests/lab/f5_patch_v4_test.sh`（66 斷言）+
   SOP 受控驗證取代。審核第 7 節的建議即此測試檔。
3. 無 cleanup 子指令：審核接受（第 6 節 accepted limits）。
4. rollback 需明確目錄參數 + 純原版限制（V4-02 修正後更嚴）。

---

## 5. 先前 findings 在 v4 的處置

| 編號 | 處置 |
|---|---|
| CR-01 | 在內嵌 payload 內，md5 未變，修正保留 |
| CR-02 | selftest 移除；由 LAB 迴歸測試檔 + SOP 取代 |
| CR-04 / R2-02 | 「順序相容取代 transaction」立場獲第一輪審核接受（Q3: Yes）；V4-02 的依賴規則與純原版 gate 補上缺口 |
| CR-05 | cleanup 移除，moot |
| R3 P0-1 | sidecar 保留 + gate 5c |
| R3 P0-2 | cleanup 移除，moot |
| R3 P0-3 | SOP 中止/恢復條件依 V4-01 補強（handler 恢復為無條件步驟） |
| R3 P0-4 | builder 斷言 + deterministic 重建 + gate + 迴歸測試檔 |
| V4-01～05 | 見第 0 節 |

---

## 6. LAB 驗證證據（2026-08-22，BIG-IP 17.1.3.1 實機，rebuild 後重驗）

失敗曲線（payload 未變，沿用同日實測）：

| raw 檔數 | ls 輸出 | 原版失敗率 | v4 套用後 |
|---|---|---|---|
| 67 | 4087 B | 0/10 | 0/10 |
| 80 | 4880 B | 2/10 | 0/10 |
| 141 | 8601 B | 7/10 | 0/10 |
| 179 | 10919 B | 8/10 | 0/10 |
| 300 | 18300 B | 9/10 | 0/10 |

rebuild `d058b2cf…` 後的重驗：

1. 迴歸測試 `f5_patch_v4_test.sh`：**66 斷言全 PASS**（12 審核案例 +
   修復路徑；含各檔 chattr +i 故障注入與續跑、八組合、混合備份拒絕）。
2. 真實目錄週期：check → rollback（純原版 gate）→ apply，全 RC=0。
3. 受控 e2e：handler inactive → `main.sh --force` RC=0、診斷行、
   `final/` 更新、revision 15→16 → handler active → save config → 確認。
4. project gate：PASS=26 FAIL=0，RC=0。
5. V4-03 驗收：乾淨 commit checkout 重建，SHA-256 一致。

---

## 7. 已知限制與非目標（第一輪第 6 節已接受）

1. 不清理暫存檔；Phase 1B 承接。不得把 v4 描述為完整磁碟生命週期修正。
2. 缺陷 A（`main.sh:88` 死碼）不在本 patch 範圍。
3. pgrep guard 是 best-effort，有 time-of-check race；極端時序下某一輪
   可能仍以舊腳本失敗一次，下一輪自動恢復（README 注意 5）。
4. 一次只能有一個管理者執行 patch 指令。
5. `/var/tmp` 備份不進 UCS。最終後盾是 repo tracked source。

---

## 8. 給審核者的問題（第三輪，如有）

1. R2-V4-01～03 的修正與證據是否足以解除 CONDITIONAL、進入單機 canary？
2. rollback 的目前檔案預檢是否還有遺漏路徑？

---

## 9. 環境前提

BIG-IP 17.1.3.1 / Linux 3.10 EL7 / bash 4.2.46 / coreutils 8.22 /
GNU awk 4.0.2 / procps-ng（`pgrep -a` 可用）/ admin 登入即 uid=0。
`declare -A`、`mktemp`、`chmod/chown --reference`、`md5sum -c`、`chattr`
全部在 LAB 同版本實機執行過。

## 10. 建議閱讀順序

1. 本文件（第 0 節是第一輪回應）
2. `patches/rpz_patch_sigpipe_v4.sh`
3. `patches/build_patch_v4.sh`
4. `patches/README.md`
5. `tests/lab/f5_patch_v4_test.sh` 與 `tests/check_source_consistency.sh`
6. `process.md` 第 20 節（本輪回應記錄）、第 19 節（重構記錄）
7. 參考：`CODE_REVIEW_V4_STE100_20260822.md`（第一輪審核）
