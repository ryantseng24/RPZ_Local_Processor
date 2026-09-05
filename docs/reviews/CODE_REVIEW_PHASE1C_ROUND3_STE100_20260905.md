# Phase 1C 第三輪文件核對

日期：2026-09-05。範圍：第二輪文件殘項及執行檔完整性。
本輪未連接 LAB，未重跑 regression、destructive e2e 或 soak。

## 1. 判定

| 項目 | 結果 |
|---|---|
| Production source 與 patch | GO 維持，執行內容未變 |
| P1C-01 | 主要缺項已修正；降為 Low，只剩全部還原後的 check 輸出敘述 |
| P1C-02 | 維持關閉 |
| P1C-03 | 第二輪列出的殘項已修正，關閉 |
| Canary | 修正第 2 節的一句文字後，即可解除文件條件；Splunk 收件仍須現場驗收 |
| 完整安裝包 | 維持 HOLD / NO-GO |

已核對六檔傳送、三個 sidecar 驗證、Patch 3 停止／恢復排程、
還原順序、備份記錄欄位，以及同一 TESTID 的 notice／err 驗證步驟。
不要求再修改程式或增加測試機制。

## 2. 唯一剩餘修正：全部還原後的 check 結果

位置：[patches/README.md:323](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:323)。

目前文字：

> 只有情境 B 走完三步，三個工具的 check 才都回到 v1.2 原版。

這句不符合工具的版本表。
全部還原後，main.sh 的 MD5 是 `0041c1d74e5b8514dea506608607b8c6`。
Patch 3 只接受 1B main 的 `d1e1f688…` 或 1C main 的 `9d8538a6…`。
所以 Patch 3 check 會顯示版本不明並回傳 RC=2。
這是版本保護的預期結果，不是還原失敗。

證據：[Patch 3 版本表](/Users/ryan/project/RPZ_Local_Processor/patches/rpz_patch_phase1c_v1.sh:45)、
[Patch 3 check 判定](/Users/ryan/project/RPZ_Local_Processor/patches/rpz_patch_phase1c_v1.sh:113)。
本輪以原始 Git baseline 核對 v1.2 main 的 MD5；未實際還原 LAB。

建議直接替換為：

> 情境 B 完成後，Patch 1 與 Patch 2 的 check 應顯示原版 v1.2（RC=0）。Patch 3 的 check 會因 main.sh 已回到 v1.2 而顯示「版本不明」（RC=2）。這是預期結果，不需重新套用 Patch 3。

只需修正此句。保持執行檔雜湊不變，即可關閉 P1C-01 並解除 canary 文件條件。
不要求再做一輪 runtime 審核。

## 3. 完整性核對

| 檔案 | SHA-256 | 結果 |
|---|---|---|
| Patch 3 | `a0ca535f84f744cb50dfbdbe84e9dec7362d398968dd53bd33ee9d2de04610ec` | 與第二輪相同；sidecar OK |
| e2e driver | `4359910970b808bbe662a21e1c02d83099af52f944379551461dbd8115498715` | 與第二輪相同 |
| regression | `9dfb72908dc889374fb6d932539048f24a977cf40f78b001eeb0f5197dedbd23` | 與第二輪相同 |
| 第二輪審核文件 | `98057c7e568033a98f606344057b5dddd48360d5f50eeeb020f15fccd313a9ef` | 與原交付檔相同，未被改寫 |

三支 production source 的完整 SHA-256 也與第二輪相同。
builder 的唯一差異是產生模板外的一行註解。
本輪沒有重建 patch。沒有重跑 gate；本輪自行執行的文件空白檢查通過。
使用者回報的 gate PASS=42，與上一輪本審核者實測 PASS=42 分開看待。

本輪在專案內只新增此核對文件。沒有修改受審文件或程式，未 commit，未 push。
