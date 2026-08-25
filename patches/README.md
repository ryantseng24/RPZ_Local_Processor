# RPZ 修正 patch 部署手冊

| 項目 | 內容 |
|---|---|
| 對象 | 在 F5 設備上執行部署的工程師 |
| 內容 | 兩個 patch 的部署、驗證、還原步驟 |
| 單台時間 | 約 30 分鐘（含驗證） |
| 服務影響 | 不需要重開機。不中斷 DNS 服務 |

**路徑約定**：本文件內的檔案路徑，都從 repo 根目錄起算。
本文件自己的位置是 `patches/README.md`。

問題背景說明在 `process.md` 第 2 節（repo 根目錄）。
部署不需要先讀它。

---

## 1. 部署檔案

要帶到設備的檔案有 4 個，都在 `patches/` 目錄：

| 檔案 | 用途 |
|---|---|
| `patches/rpz_patch_sigpipe_v4.sh` | Patch 1 本體（修正更新失敗） |
| `patches/rpz_patch_sigpipe_v4.sh.sha256` | Patch 1 檢查碼 |
| `patches/rpz_patch_phase1b_v1.sh` | Patch 2 本體（暫存檔保留策略） |
| `patches/rpz_patch_phase1b_v1.sh.sha256` | Patch 2 檢查碼 |

正確的 SHA-256 值：

```
e407d6e7d0d12d1c6ca445d737208ab139437fd8504fe47d9b318754c1d37626  rpz_patch_sigpipe_v4.sh
aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785  rpz_patch_phase1b_v1.sh
```

規則：

1. 只使用上表的檔案。
2. 部署前，核對 SHA-256。值不符就停止，並回報。
3. patch 檔案與 .sha256 檔案必須放在同一個目錄。

## 2. 部署原則

1. 先部署一台（試行台）。試行台完整通過第 4.6 節的驗收，才部署下一台。
2. 不要多台同時部署。
3. 每台的順序固定：先 Patch 1，後 Patch 2。
4. 如果任何步驟的輸出與本文件不符：停止、保留完整畫面輸出、回報。
   不要強行繼續。
5. 部署期間不需要停用 DNS 服務。

## 3. 部署前檢查（每台設備）

1. 傳 4 個檔案到設備：

```bash
scp rpz_patch_sigpipe_v4.sh rpz_patch_sigpipe_v4.sh.sha256 rpz_patch_phase1b_v1.sh rpz_patch_phase1b_v1.sh.sha256 admin@<設備IP>:/var/tmp/
```

2. 登入設備。核對檔案完整性：

```bash
cd /var/tmp && sha256sum -c rpz_patch_sigpipe_v4.sh.sha256 && sha256sum -c rpz_patch_phase1b_v1.sh.sha256
```

兩行都必須顯示 `OK`。

3. 檢查目前的程式版本。這個步驟只讀取，不改任何檔案：

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh check
```

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh check
```

4. 判讀：

| check 顯示 | 動作 |
|---|---|
| 全部是原版 v1.2，可以套用 | 繼續第 4 節 |
| 版本不明 | **停止**。把完整輸出回報 |

5. 把兩個 check 的完整輸出存檔。第 6 節的記錄表需要它。

## 4. 部署步驟（每台設備）

### 4.1 套用 Patch 1

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh apply
```

必須顯示「套用完成」。**記下輸出中的備份目錄路徑。**

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh check
```

必須顯示「已全部套用修正」。

### 4.2 套用 Patch 2

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh apply
```

必須顯示「套用完成」。**記下備份目錄路徑。**

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh check
```

必須顯示「已套用 Phase 1B 修正」。

### 4.3 功能驗證（逐條輸入，保留完整輸出作為證據）

1. 暫停排程。目的：驗證期間避免排程與手動執行重疊。

```bash
tmsh modify sys icall handler periodic rpz_processor_handler status inactive
```

2. 等系統靜止。重複執行下面這條，直到沒有輸出：

```bash
pgrep -f "RPZ_Local_Processor/scripts"
```

3. 記錄測試前數值：

```bash
ls -l --time-style=full-iso /config/snmp/rpz_datagroups/final/
```

```bash
tmsh list sys file data-group rpztw | grep -E "revision|size|last-update-time"
```

4. 執行一次完整更新。下一條指令要**立刻**輸入，保存結果代碼：

```bash
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
```

```bash
MAIN_RC=$?; echo "main.sh RC=${MAIN_RC}"
```

5. 記錄測試後數值。與第 3 步相同的兩條指令，再執行一次。

6. 恢復排程並存檔。**驗證成功或失敗，這一步都必須做：**

```bash
tmsh modify sys icall handler periodic rpz_processor_handler status active
```

```bash
tmsh save sys config
```

```bash
tmsh list sys icall handler periodic rpz_processor_handler status interval
```

最後一條必須顯示 `status active` 與 `interval 300`。

注意：不要在設備上建立任何測試用的假檔案。驗證一律使用真實資料。

### 4.4 驗收條件（全部成立才算通過）

| # | 條件 |
|---|---|
| 1 | `main.sh RC=0` |
| 2 | 執行輸出含「使用 dnsxdump 檔案」與「處理完成」 |
| 3 | final 目錄三個檔案的時間，比測試前新 |
| 4 | revision 比測試前增加 |
| 5 | size 與測試前同量級，不是 0 |
| 6 | 排程恢復 `active` / `300`，設定已存檔 |

### 4.5 部署後觀察（試行台必做）

1. 等至少一次排程自動執行。排程每 300 秒檢查一次。
   黑名單來源的變更間隔約 5～80 分鐘。
2. 查看紀錄：

```bash
grep -E "處理完成|ERROR|WARN" /config/snmp/rpz_wrapper.log | tail -20
```

3. 判讀：有「處理完成」、沒有新的 ERROR、沒有「清理失敗」類的 WARN。
4. 確認暫存檔數量有上限：

```bash
ls /config/snmp/rpz_datagroups/raw/ | wc -l
```

數值必須在 24 以內。

5. 試行台觀察一個工作日。無異常後，依本文件部署其餘設備。

## 5. 還原步驟（需要時才執行）

還原順序與部署相反：先還原 Patch 2，再還原 Patch 1。
備份目錄路徑，用第 4.1 與 4.2 節記下的值。

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh rollback /var/tmp/rpz_patch1b_backup_<時間>
```

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh rollback /var/tmp/rpz_patch_backup_<時間>
```

規則：

1. 每條還原指令結束會自動核對版本。結果必須回到「原版 v1.2」。
2. 還原工具只接受部署時自動建立的原版備份。
   備份內容不符時，工具會拒絕動作。此時停止並回報。
3. 還原後，系統回到部署前的行為，原本的問題會回來。
   還原是暫時措施。還原後請回報，安排後續。

## 6. 每台記錄表（部署時填寫）

| 欄位 | 內容 |
|---|---|
| 設備名稱 / 日期 / 執行者 | |
| 部署前 check 輸出（兩個 patch） | 附檔 |
| Patch 1 備份目錄路徑 | |
| Patch 2 備份目錄路徑 | |
| 測試前 revision / size / final 檔案時間 | |
| `main.sh RC` | |
| 測試後 revision / size / final 檔案時間 | |
| 驗收條件 1~6 勾選 | |
| 觀察期結果（第 4.5 節） | |

## 7. 退出碼

兩個 patch 工具的退出碼相同：

| 退出碼 | 意義 | 動作 |
|---|---|---|
| 0 | 成功（含「已套用，無需動作」） | 繼續下一步 |
| 1 | 執行中發生錯誤 | 停止。回報錯誤訊息 |
| 2 | 前置條件不符 | 看下表的常見狀況 |

## 8. 常見狀況與判讀

| 畫面顯示 | 意義 | 動作 |
|---|---|---|
| RPZ 處理程序執行中 | 系統正在跑例行更新（約 1~2 分鐘） | 等 2 分鐘，重試同一條指令 |
| 版本不明 | 設備上的程式不是本 patch 支援的版本 | 停止。回報完整輸出 |
| 版本組合不可運作 | 檔案版本混雜（少見） | 執行 apply 可修復。修復後回報 |
| 備份不是純原版 | 指到了錯的備份目錄 | 改用第 4.1 / 4.2 節記下的備份路徑 |
| log 出現「數量上限清理: … 保留 24 個」 | 正常。這是新的自動清理 | 不需處理 |
| log 出現「實際刪除 … 失敗 N 個」 | 有檔案刪不掉 | 回報 |
| log 出現「天數上限清理失敗」 | 有舊檔刪不掉 | 回報 |

## 9. 問題回報

1. 停止操作。同一條指令不要重試超過一次。不要跳步。
2. 保留完整終端機輸出。
3. 回報三項：設備名稱、執行到的章節編號、完整輸出。

---

## 10. 背景與驗證記錄（部署時不需要讀）

### 10.1 相關文件位置

| 內容 | 位置 |
|---|---|
| 問題原因與實測數據 | `process.md` 第 2 節、第 6 節（repo 根目錄） |
| 完整事件記錄 | `process.md` 第 1～27 節 |
| Patch 2 的設計文件 | `docs/PHASE1B_DESIGN_20260823.md` |
| 獨立審核文件（9 份）與審核交接（3 份） | `docs/reviews/` 目錄 |
| 目前進度快照 | `STATUS_20260822.md`（repo 根目錄） |
| 安裝包的部署狀態（目前不可部署） | `dist/DO_NOT_DEPLOY.md` |
| LAB 測試腳本說明 | `tests/lab/README.md` |

### 10.2 修正內容摘要

Patch 1 更換 3 個程式檔案。原始程式挑選最新暫存檔的方法，
在檔案超過約 67 個時會不定期失敗。新方法逐一比對，
不受檔案數量影響。

Patch 2 更換 1 個程式檔案（`main.sh`）。變更三項：
清理範圍限制在兩個暫存目錄（生效中的黑名單目錄不在任何清理
範圍內）；每一類暫存檔保留最新 24 個（可用環境變數
`RPZ_KEEP_COUNT` 調整，範圍 1~99999）；清理改為每次執行結束
都會做，包括失敗與無需更新的情況。

### 10.3 驗證摘要

驗證環境與正式設備同版本（BIG-IP 17.1.3.1）。

| 項目 | 結果 |
|---|---|
| 原始程式失敗率（300 個暫存檔） | 100% |
| Patch 1 之後（300 個暫存檔） | 0% |
| Patch 工具自動化測試 | 78 + 112 項檢查全部通過 |
| 端對端演練（含還原） | 通過 |
| 真實來源連續測試（每 6 分鐘一筆，共 10 筆） | 10 筆全部在 5 分鐘內生效，期間 0 個錯誤 |
| 獨立審核 | Patch 1 兩輪、Patch 2 三輪，最終判定通過 |

完整審核往返記錄在 `process.md` 第 16～25 節與 `docs/reviews/`。

### 10.4 已知勘誤（不影響行為）

`main.sh` 與兩個 patch 內嵌副本的註解，有兩處引用了錯誤的
`process.md` 章節號：「第 13 節」應為第 2 節；「第 15 節」應為
第 27 節。只是註解，不影響任何行為。修改會變更已交付的 patch
SHA-256，因此保留到下一次程式變更時一併修正。
`docs/PHASE1B_DESIGN_20260823.md` 第 3 節的程式碼樣本與實作
逐字一致，保留同樣的筆誤。

### 10.5 版本沿革

| 版本 | 狀態 |
|---|---|
| patch v1 / v2 | 開發過程版本，已淘汰，不在 repo |
| patch v3 | 封存於 `patches/archive/`，只作審核紀錄，不要使用 |
| `rpz_patch_sigpipe_v4.sh` | **現行** Patch 1 |
| `rpz_patch_phase1b_v1.sh` | **現行** Patch 2 |

兩個 patch 都以 builder 從 tracked source 產生：
`patches/build_patch_v4.sh`、`patches/build_patch_phase1b.sh`。
builder 只給開發端使用，不要帶到設備上。
