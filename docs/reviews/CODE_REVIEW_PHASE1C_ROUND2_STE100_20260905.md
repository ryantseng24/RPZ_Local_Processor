# Phase 1C 第二輪短確認

日期：2026-09-05。
受審 Git 版本：`0569761`。開始時工作目錄乾淨。
依更新後的 [REVIEW_HANDOFF_PHASE1C.md](/Users/ryan/project/RPZ_Local_Processor/docs/reviews/REVIEW_HANDOFF_PHASE1C.md) 確認 P1C-01～03。

## 1. 判定

| 項目 | 判定 |
|---|---|
| Production 日誌修正及 patch 執行邏輯 | **GO，維持第一輪判定** |
| P1C-01：部署及還原 SOP | **部分關閉，仍為 Medium**；剩下明確的操作步驟缺項 |
| P1C-02：e2e 錯誤判定 | **關閉**；本輪反向測試通過 |
| Phase 1C e2e driver | **GO，僅限指定 LAB**；本輪未重跑真實資料 e2e |
| P1C-03：文件一致性 | **部分關閉，仍為 Low** |
| 客戶單機 canary | **CONDITIONAL GO**；先完成下列文件修正 |
| v1.2.3 完整安裝包 | **維持 HOLD / NO-GO** |

未發現新的 production source 缺陷。
目前不能接受交接文件首頁的「P1C-01～03 已全部修正」敘述。
剩餘工作是文件，不需要擴充 patch 功能。

## 2. 尚未關閉的項目

### P1C-01：SOP 已補版本關係，但操作步驟仍缺項

已確認完成：

- 第 4.6 節說明 1C check 不檢查 v4，並要求交叉確認。
- 說明安裝 1C 後，1B check 的 RC=2 是舊工具的預期反應。
- 第 5 節區分只還原 1C，及全部還原 1C → 1B → v4。
- 加入帶唯一識別碼的 Splunk notice 測試。

尚需修正 [patches/README.md](/Users/ryan/project/RPZ_Local_Processor/patches/README.md)：

1. **補 Patch 3 傳檔及完整性驗證指令。**
   第 3 節 [第 59 行](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:59) 的 scp 仍只傳四個檔案。
   [第 65 行](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:65) 也只驗證兩個 sidecar。
   須加入 Patch 3 本體及 sidecar。三項都顯示 OK，才可繼續。
   同步把「四個檔案」改為「六個檔案」。

2. **在 Patch 3 apply 及 rollback 前，明確停止排程並等待程序結束。**
   第 4.3 節已恢復排程。到了 [第 4.6 節](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:205)，沒有再次停止的步驟。
   第 5 節也沒有停止／恢復步驟。
   pgrep 只是檢查當下，不是鎖定排程。
   補上停止、等待、操作，以及成功或失敗時的恢復及存檔指令即可。
   不要求新增鎖或自動排程管理器。

3. **修正 check 與 rollback 的預期輸出。**
   [第 210 行](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:210) 寫「兩條都必須已套用」，
   但下方正確要求 Patch 3 顯示「全部是部署前版本」。刪除矛盾的前一句。
   [第 283 行](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:283) 寫每次 rollback 都回到原版 v1.2，也不正確。
   只還原 Patch 3 時，main 保留 1B 修正版；1C check 應顯示「全部是部署前版本」。
   同步加入 Patch 3 備份路徑的記錄欄位。

4. **Splunk 驗收補 err 等級。**
   [第 245 行](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:245) 只送 local0.notice。
   客戶關心的 `RPZ parsing failed` 使用 local0.err。
   依第一輪要求，使用同一個唯一識別碼，分別送 notice 與 err，並在本機與 Splunk 比對。
   清楚標成測試訊息，先與監控人員確認；不要讓真實 RPZ 流程故意失敗。

以上均屬原 P1C-01 的收尾，不新增功能要求。

### P1C-03：仍有舊文字，不能標成全部關閉

已修正：事件數量 11 err／6 notice、timestamp 宣告數、license 日期、patch 內的遠端收件措辭，以及 v1.2.3 HOLD 記錄。

仍需同步：

- [交接文件第 61 行](/Users/ryan/project/RPZ_Local_Processor/docs/reviews/REVIEW_HANDOFF_PHASE1C.md:61) 仍稱 check 強制完整 v4 → 1B → 1C 順序。
  [builder 第 11 行](/Users/ryan/project/RPZ_Local_Processor/patches/build_patch_phase1c.sh:11) 也留有同樣文字。
  改成「1C 驗自己的三檔；v4 由 SOP 確認」。
- 交接首頁與 STATUS 仍稱 mock 四模式全部中止。
  正確結果是三種錯誤中止；trap_save_error 模式正常通過，因第二次 save 已不存在。
- 交接表的 patch 仍寫 890 行／邏輯 243 行，實際為 892／245。
  regression 仍寫 202 行，實際為 205 行。
  LAB README 仍寫 29 項，實際為 33 項。
  行數欄位也可以刪除，避免每次註解變更都需要同步。
- 主手冊末尾仍稱所有 builder 從目前 tracked source 產生。
  process 第 29 節已有 1B 使用 `f560b80` 歷史來源的說明，請同步到主手冊。

不要求放寬 builder 的 MD5 保護。
builder 第 11 行在生成模板外，只修改這行註解不應改變 patch 內容。

## 3. P1C-02 關閉證據

已完整讀取修改後的 132 行 e2e driver。
本輪使用第一輪的 mock，在新的隔離目錄執行，沒有呼叫真實 F5 修改指令。

| 模式 | 本輪結果 | 判斷 |
|---|---|---|
| normal | PASS=15 FAIL=0，RC=0 | 正常對照通過 |
| interval3000 | RC=2 | 正確拒絕，不再把 3000 當成 300 |
| read_error | RC=2 | 正確拒絕 tmsh 查詢錯誤 |
| pgrep_error | RC=1 | 正確中止，不再把查詢失敗當成沒有程序 |
| trap_save_error | PASS=15 FAIL=0，RC=0，save 只有一次 | 正常收尾已解除 trap，第二次未驗證的 save 不再執行 |

本輪也確認程式已保存其他 tmsh 查詢的 RC，並精確比對 status／interval。
結論限於本次 finding 及指定 LAB 用途，不宣稱已窮舉所有故障。

本機重現工具與各模式日誌位於：

`/private/tmp/rpz-phase1c-round2.BecEuG/`

## 4. 獨立驗證結果

| 項目 | 本輪結果 |
|---|---|
| Project gate | PASS=42 FAIL=0 RC=0 |
| Shell 語法 | 30 支通過；由 gate 執行 |
| Deterministic rebuild | 隔離重建與交付 patch 完全一致 |
| Patch sidecar／嵌入內容 | 通過 |
| Patch 與第一輪差異 | 只有檔頭註解；執行邏輯與三支 payload 不變 |
| LAB regression | PASS=33 FAIL=0 RC=0，含 F4／F5 |
| F4 | parsing 失敗回傳 RC=1，local0.err 事件實際進入 LAB ltm |
| F5 | logger 替身回傳 42，NO_UPDATE 主流程仍回傳 RC=0 |
| ShellCheck | 未執行；本機未安裝，不以語法檢查代替 |
| 真實資料 destructive e2e／soak | 本輪未執行，亦不要求重跑 |
| Splunk 收件 | 本輪未驗證，保留為 canary 現場驗收 |

本輪只執行 LAB 隔離 regression。測試檔由測試工具清除，本機 ltm 留下少量測試事件。
未修改 LAB 已安裝程式、DataGroup、SOA 快取、iRule 或 handler。
開始及收尾均為 handler active／300、rpztw revision 35、size 2243094。
三支已安裝 payload MD5 維持 `9d8538a6…`、`fea7c2e2…`、`67227cb3…`。

受審 patch SHA-256：

```text
a0ca535f84f744cb50dfbdbe84e9dec7362d398968dd53bd33ee9d2de04610ec
```

受審 e2e driver SHA-256：

```text
4359910970b808bbe662a21e1c02d83099af52f944379551461dbd8115498715
```

受審 regression SHA-256：

```text
9dfb72908dc889374fb6d932539048f24a977cf40f78b001eeb0f5197dedbd23
```

## 5. 交付要求

只修 P1C-01 的 SOP 缺項及 P1C-03 的文字。
不修改 production source、patch 執行邏輯或 e2e 程式。
只要這些執行檔雜湊不變，下輪只需核對文件，不需要重建 patch、重跑 regression 或完整 runtime 審核。
完成文件核對後，可以解除 canary 的文件條件。Splunk 的現場收件條件仍保留。

本輪在專案內只新增此審核文件。未修改既有文件或程式，未 commit，未 push。
