# RPZ 修正 patch 部署手冊（總表）

| 項目 | 內容 |
|---|---|
| 對象 | 在 F5 設備上執行部署的工程師 |
| 內容 | 三個 patch 的總表、共同規則、跨 patch 還原 |
| 單台時間 | 約 40 分鐘（含驗證，不含觀察期） |
| 服務影響 | 不需要重開機。不中斷 DNS 服務 |

**路徑約定**：本文件內的檔案路徑，都從 repo 根目錄起算。
本文件自己的位置是 `patches/README.md`。

問題背景說明在 `process.md` 第 2 節（repo 根目錄）。
部署不需要先讀它。

---

## 1. 目錄結構

| 位置 | 內容 |
|---|---|
| `patches/README.md` | 本文件。總表與共同規則 |
| `patches/patch1_sigpipe/` | Patch 1：修正黑名單更新失敗 |
| `patches/patch2_retention/` | Patch 2：暫存檔保留策略 |
| `patches/patch3_syslog/` | Patch 3：事件 log 改走 syslog |
| `patches/archive/` | 已淘汰的 patch v3。只作審核紀錄，不要使用 |

每個 patch 資料夾固定放 4 個檔案：

| 檔案 | 用途 |
|---|---|
| `README.md` | 該 patch 的部署手冊 |
| `rpz_patch_*.sh` | patch 本體 |
| `rpz_patch_*.sh.sha256` | 檢查碼 |
| `build_patch_*.sh` | 開發端工具。不要帶到設備 |

## 2. Patch 總表

| Patch | 修正的問題 | 部署手冊 | 審核 |
|---|---|---|---|
| Patch 1 | 暫存檔超過約 67 個時，黑名單更新不定期失敗 | `patches/patch1_sigpipe/README.md` | 兩輪，GO |
| Patch 2 | 暫存檔無上限累積，造成磁碟空間告警 | `patches/patch2_retention/README.md` | 三輪，GO |
| Patch 3 | 事件 log 只寫本機檔案，遠端 log 平台（Splunk）收不到 | `patches/patch3_syslog/README.md` | 兩輪，GO |

正確的 SHA-256 值：

```
e407d6e7d0d12d1c6ca445d737208ab139437fd8504fe47d9b318754c1d37626  rpz_patch_sigpipe_v4.sh
aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785  rpz_patch_phase1b_v1.sh
a0ca535f84f744cb50dfbdbe84e9dec7362d398968dd53bd33ee9d2de04610ec  rpz_patch_phase1c_v1.sh
```

## 3. 部署順序與共同規則

1. 每台的順序固定：Patch 1 -> Patch 2 -> Patch 3。不得跳序。
   依序照三本手冊執行：`patches/patch1_sigpipe/README.md` ->
   `patches/patch2_retention/README.md` -> `patches/patch3_syslog/README.md`。
2. 先部署一台（試行台）。試行台完整通過三本手冊的驗收，
   再觀察一個工作日（方法見 `patches/patch2_retention/README.md` 第 4.3 節）。
   無異常後，才部署其餘設備。
3. 不要多台同時部署。
4. 只使用第 2 節總表的檔案。部署前核對 SHA-256。值不符就停止並回報。
5. 如果任何步驟的輸出與手冊不符：停止、保留完整畫面輸出、回報。
   不要強行繼續。
6. 部署期間不需要停用 DNS 服務。不要在設備上建立任何測試用的假檔案。

## 4. 傳檔與完整性驗證（每台設備）

1. 從 repo 根目錄，傳 6 個檔案到設備：

```bash
scp patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh.sha256 patches/patch2_retention/rpz_patch_phase1b_v1.sh patches/patch2_retention/rpz_patch_phase1b_v1.sh.sha256 patches/patch3_syslog/rpz_patch_phase1c_v1.sh patches/patch3_syslog/rpz_patch_phase1c_v1.sh.sha256 admin@<設備IP>:/var/tmp/
```

2. 登入設備。核對檔案完整性
   （patch 檔案與 `.sha256` 檔案必須在同一個目錄）：

```bash
cd /var/tmp && sha256sum -c rpz_patch_sigpipe_v4.sh.sha256 && sha256sum -c rpz_patch_phase1b_v1.sh.sha256 && sha256sum -c rpz_patch_phase1c_v1.sh.sha256
```

三行都必須顯示 `OK`，才可以繼續第一本手冊
`patches/patch1_sigpipe/README.md`。

## 5. 全部還原（跨 patch，需要時才執行）

只還原 Patch 3 的情境，見 `patches/patch3_syslog/README.md` 第 6 節。

全部還原的順序固定 **Patch 3 -> Patch 2 -> Patch 1，不得跳過 Patch 3**。
已套用 Patch 3 的設備直接執行 Patch 2 的 rollback 會被版本檢查拒絕——
這是保護，不是故障。

1. 停止排程並等待系統靜止：

```bash
tmsh modify sys icall handler periodic rpz_processor_handler status inactive
```

重複執行下面這條，直到沒有輸出：

```bash
pgrep -f "RPZ_Local_Processor/scripts"
```

2. 依序執行三條還原。備份目錄路徑用各手冊部署時記下的值：

```bash
bash /var/tmp/rpz_patch_phase1c_v1.sh rollback /var/tmp/rpz_patch1c_backup_<時間>
```

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh rollback /var/tmp/rpz_patch1b_backup_<時間>
```

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh rollback /var/tmp/rpz_patch_backup_<時間>
```

3. 恢復排程並存檔（**成功或失敗，這一步都必須做**）：

```bash
tmsh modify sys icall handler periodic rpz_processor_handler status active
```

```bash
tmsh save sys config
```

```bash
tmsh list sys icall handler periodic rpz_processor_handler status interval
```

必須顯示 `status active` 與 `interval 300`。

規則與預期結果：

1. 每條還原指令結束會自動核對版本，回到**該 patch 的部署前版本**。
2. 三步走完後：Patch 1 與 Patch 2 的 check 顯示原版 v1.2（RC=0）；
   **Patch 3 的 check 會顯示「版本不明」（RC=2）**——因為它的部署前
   基準是 Phase 1B 版 `main.sh`，不認得 v1.2 原版。這是預期結果，
   不需要重新套用任何 patch。
3. 還原工具只接受部署時自動建立的原版備份。備份內容不符時，
   工具會拒絕動作。此時停止並回報。
4. 還原後，系統回到部署前的行為，原本的問題會回來。
   還原是暫時措施。還原後請回報，安排後續。

## 6. 每台記錄表（部署時填寫）

| 欄位 | 內容 |
|---|---|
| 設備名稱 / 日期 / 執行者 | |
| 部署前 check 輸出（三個 patch） | 附檔 |
| Patch 1 備份目錄路徑 | |
| Patch 2 備份目錄路徑 | |
| Patch 3 備份目錄路徑 | |
| Splunk 驗證 TESTID 與結果（notice + err） | |
| 測試前 revision / size / final 檔案時間 | |
| `main.sh RC` | |
| 測試後 revision / size / final 檔案時間 | |
| 驗收條件 1~6 勾選（`patches/patch2_retention/README.md` 第 4.2 節） | |
| 觀察期結果（`patches/patch2_retention/README.md` 第 4.3 節） | |

## 7. 退出碼

三個 patch 工具的退出碼相同：

| 退出碼 | 意義 | 動作 |
|---|---|---|
| 0 | 成功（含「已套用，無需動作」） | 繼續下一步 |
| 1 | 執行中發生錯誤 | 停止。回報錯誤訊息 |
| 2 | 前置條件不符 | 看下表的常見狀況 |

## 8. 常見狀況與判讀

| 畫面顯示 | 意義 | 動作 |
|---|---|---|
| RPZ 處理程序執行中 | 系統正在跑例行更新（約 1~2 分鐘） | 等 2 分鐘，重試同一條指令 |
| 版本不明 | 設備上的程式不是該 patch 支援的版本 | 停止。回報完整輸出（Patch 3 的例外見 `patches/patch3_syslog/README.md` 第 5 節） |
| 版本組合不可運作 | 檔案版本混雜（少見） | 執行 apply 可修復。修復後回報 |
| 備份不是純原版 | 指到了錯的備份目錄 | 改用各手冊部署時記下的備份路徑 |
| log 出現「數量上限清理: … 保留 24 個」 | 正常。這是新的自動清理 | 不需處理 |
| log 出現「實際刪除 … 失敗 N 個」 | 有檔案刪不掉 | 回報 |
| log 出現「天數上限清理失敗」 | 有舊檔刪不掉 | 回報 |

## 9. 問題回報

1. 停止操作。同一條指令不要重試超過一次。不要跳步。
2. 保留完整終端機輸出。
3. 回報三項：設備名稱、執行到的手冊與章節編號、完整輸出。

---

## 10. 背景與驗證記錄（部署時不需要讀）

### 10.1 相關文件位置

| 內容 | 位置 |
|---|---|
| 問題原因與實測數據 | `process.md` 第 2 節、第 6 節（repo 根目錄） |
| 完整事件記錄 | `process.md`（repo 根目錄） |
| Patch 2 的設計文件 | `docs/PHASE1B_DESIGN_20260823.md` |
| 獨立審核文件與審核交接 | `docs/reviews/` 目錄 |
| 目前進度快照 | `STATUS_20260822.md`（repo 根目錄） |
| 安裝包的部署狀態（目前不可部署） | `dist/DO_NOT_DEPLOY.md` |
| LAB 測試腳本說明 | `tests/lab/README.md` |

### 10.2 驗證摘要

驗證環境與正式設備同版本（BIG-IP 17.1.3.1）。

| 項目 | 結果 |
|---|---|
| 原始程式失敗率（300 個暫存檔） | 100% |
| Patch 1 之後（300 個暫存檔） | 0% |
| Patch 工具自動化測試 | 78 + 112 + 33 項檢查全部通過 |
| 端對端演練（含還原） | 通過 |
| 真實來源連續測試（每 6 分鐘一筆，共 10 筆） | 10 筆全部在 5 分鐘內生效，期間 0 個錯誤 |
| 遠端 log 收件（Splunk） | 保留為 canary 現場驗收 |
| 獨立審核 | Patch 1 兩輪、Patch 2 三輪、Patch 3 兩輪，最終判定通過 |

完整審核往返記錄在 `process.md` 第 16～30 節與 `docs/reviews/`。

### 10.3 版本沿革

| 版本 | 狀態 |
|---|---|
| patch v1 / v2 | 開發過程版本，已淘汰，不在 repo |
| patch v3 | 封存於 `patches/archive/`，只作審核紀錄，不要使用 |
| `rpz_patch_sigpipe_v4.sh` | **現行** Patch 1 |
| `rpz_patch_phase1b_v1.sh` | **現行** Patch 2 |
| `rpz_patch_phase1c_v1.sh` | **現行** Patch 3。兩輪審核 GO；Splunk 收件於 canary 現場驗收 |

patch 都以各資料夾內的 builder 產生。builder 的使用限制與重建方式，
見各資料夾 `README.md` 的「開發端資訊」一節。
