# Patch 3：事件 log 改走 syslog

| 項目 | 內容 |
|---|---|
| patch 本體 | `patches/patch3_syslog/rpz_patch_phase1c_v1.sh` |
| 更換的程式 | `main.sh`、`extract_rpz.sh`、`update_datagroup.sh` |
| 前置條件 | Patch 1 與 Patch 2 都已套用（用第 3 節第 1 步交叉確認） |
| 部署順序 | 三個 patch 的第 3 個。總表與共同規則見 `patches/README.md` |

**路徑約定**：檔案路徑都從 repo 根目錄起算。設備上的指令用 `/var/tmp/` 路徑。

## 1. 這個 patch 修正什麼

原本 17 筆系統事件訊息直接寫入本機檔案 `/var/log/ltm`，
沒有經過 syslog。所以遠端 log 平台（Splunk）收不到這些事件。
本 patch 更換 3 個程式檔案。事件改用系統的 `logger` 指令送出
（11 筆 err、6 筆 notice），本機與遠端都會收到。
訊息是 F5 原生 log 格式，標籤為 `RPZLocal`。

## 2. 檔案

| 檔案 | 用途 |
|---|---|
| `patches/patch3_syslog/rpz_patch_phase1c_v1.sh` | patch 本體。動作：`check` / `apply` / `rollback` |
| `patches/patch3_syslog/rpz_patch_phase1c_v1.sh.sha256` | 檢查碼 |
| `patches/patch3_syslog/build_patch_phase1c.sh` | 開發端工具。不要帶到設備 |

正確的 SHA-256 值：

```
a0ca535f84f744cb50dfbdbe84e9dec7362d398968dd53bd33ee9d2de04610ec  rpz_patch_phase1c_v1.sh
```

傳檔與完整性驗證的步驟，見 `patches/README.md` 第 4 節。

## 3. 部署步驟

Patch 3 的 check 只驗它自己的三個檔案（`main.sh`、`extract_rpz.sh`、
`update_datagroup.sh`）。**它不會檢查 Patch 1 的三個檔案。**
所以第 1 步要做交叉確認。

1. 交叉確認（兩條都只讀取，不改任何檔案）：

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh check
```

```bash
bash /var/tmp/rpz_patch_phase1c_v1.sh check
```

判讀：Patch 1 的 check 必須顯示「已全部套用修正」；
Patch 3 的 check 必須顯示「全部是部署前版本」。
Patch 3 顯示「版本不明」時停止回報（最常見原因：Patch 2 還沒套用）。

2. 停止排程並等待系統靜止（目的：套用期間避免排程執行；
   patch 內建的程序檢查只看當下，不能鎖定排程）：

```bash
tmsh modify sys icall handler periodic rpz_processor_handler status inactive
```

重複執行下面這條，直到沒有輸出：

```bash
pgrep -f "RPZ_Local_Processor/scripts"
```

3. 套用與確認：

```bash
bash /var/tmp/rpz_patch_phase1c_v1.sh apply
```

```bash
bash /var/tmp/rpz_patch_phase1c_v1.sh check
```

必須顯示「已套用 Phase 1C 修正」。**記下備份目錄路徑**
（`/var/tmp/rpz_patch1c_backup_<時間>`）。

4. 恢復排程並存檔（**套用成功或失敗，這一步都必須做**）：

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

5. 部署後驗證：Patch 1 check（RC=0）加 Patch 3 check（RC=0）。
   此時 Patch 2 的 check 會回報「版本不明」（RC=2）——預期行為，
   見第 5 節。

## 4. Splunk 驗證（canary 必做）

先知會監控人員這是測試訊息。用**同一個唯一識別碼**分別送
notice 與 err 各一筆，在本機與 Splunk 兩邊比對。
err 等級必須驗（客戶關心的 `RPZ parsing failed` 就是 err）。
**不要**故意讓真實 RPZ 流程失敗來製造錯誤訊息。

```bash
TESTID=$(date +%Y%m%d%H%M%S); logger -t RPZLocal -p local0.notice "RPZLocal canary test notice ${TESTID}"; logger -t RPZLocal -p local0.err "RPZLocal canary test err ${TESTID}"; echo "TESTID=${TESTID}"
```

本機確認（應有 notice 與 err 各一筆）：

```bash
grep "RPZLocal canary test" /var/log/ltm | tail -2
```

Splunk 端由客戶以同一個 TESTID 查詢，必須同時查到 notice 與 err
兩筆。之後等待一次真實更新，確認 `RPZ processing completed`
事件同樣出現在兩邊。TESTID 與結果填入記錄表
（`patches/README.md` 第 6 節）。

## 5. 本 patch 特有狀況

| 狀況 | 意義 | 動作 |
|---|---|---|
| check 顯示「版本不明」 | 最常見原因：Patch 2 還沒套用 | 停止。回報完整輸出 |
| 套用後，Patch 2 的 check 回報「版本不明」（RC=2） | 預期行為。舊工具不認得 Phase 1C 版的 `main.sh`，保留策略仍然生效 | 不需處理 |
| 全部還原後，本 patch 的 check 顯示「版本不明」（RC=2） | 預期結果。它的部署前基準是 Phase 1B 版 `main.sh`，不認得 v1.2 原版 | 不需重新套用任何 patch |

## 6. 只還原本 patch（保留 Patch 1 與 Patch 2）

1. 停止排程並等待系統靜止。指令與第 3 節第 2 步相同。
2. 還原：

```bash
bash /var/tmp/rpz_patch_phase1c_v1.sh rollback /var/tmp/rpz_patch1c_backup_<時間>
```

使用本 patch 的純部署前備份。還原後 Patch 1 與 Patch 2 的修正仍在。
本 patch 的 check 顯示「全部是部署前版本」——不是 v1.2 原版。

3. 恢復排程並存檔。指令與第 3 節第 4 步相同。

全部還原（含 Patch 2 與 Patch 1）見 `patches/README.md` 第 5 節。

## 7. 開發端資訊（部署時不需要讀）

| 項目 | 內容 |
|---|---|
| builder | `patches/patch3_syslog/build_patch_phase1c.sh`。對目前的 tracked source 重建，產出物與交付檔完全一致 |
| 自動化測試 | `tests/lab/f5_patch_1c_test.sh`，33 項檢查（含 parsing 失敗與 logger 失敗兩個永久保護案例） |
| 受控 e2e | `tests/lab/f5_e2e_1c_controlled.sh`（只限指定 LAB 使用） |
| 獨立審核 | 兩輪：`docs/reviews/CODE_REVIEW_PHASE1C_STE100_20260905.md`、`docs/reviews/CODE_REVIEW_PHASE1C_ROUND2_STE100_20260905.md` |
