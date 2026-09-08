# Patch 2：暫存檔保留策略

| 項目 | 內容 |
|---|---|
| patch 本體 | `patches/patch2_retention/rpz_patch_phase1b_v1.sh` |
| 更換的程式 | `main.sh` |
| 前置條件 | Patch 1 已套用；`main.sh` 是原版 v1.2 |
| 部署順序 | 三個 patch 的第 2 個。總表與共同規則見 `patches/README.md` |

**路徑約定**：檔案路徑都從 repo 根目錄起算。設備上的指令用 `/var/tmp/` 路徑。

## 1. 這個 patch 修正什麼

暫存檔原本沒有數量上限，長期累積造成磁碟空間告警，
也讓 Patch 1 修正的失敗更容易發生。
本 patch 更換 1 個程式檔案（`main.sh`），變更三項：

1. 清理範圍限制在兩個暫存目錄。
   生效中的黑名單目錄不在任何清理範圍內。
2. 每一類暫存檔保留最新 24 個。可用環境變數 `RPZ_KEEP_COUNT`
   調整，範圍 1~99999。
3. 清理改為每次執行結束都會做，包括失敗與無需更新的情況。

## 2. 檔案

| 檔案 | 用途 |
|---|---|
| `patches/patch2_retention/rpz_patch_phase1b_v1.sh` | patch 本體。動作：`check` / `apply` / `rollback` |
| `patches/patch2_retention/rpz_patch_phase1b_v1.sh.sha256` | 檢查碼 |
| `patches/patch2_retention/build_patch_phase1b.sh` | 開發端工具。不要帶到設備 |

正確的 SHA-256 值：

```
aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785  rpz_patch_phase1b_v1.sh
```

傳檔與完整性驗證的步驟，見 `patches/README.md` 第 4 節。

## 3. 部署步驟

1. 檢查目前版本。這個步驟只讀取，不改任何檔案：

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh check
```

| check 顯示 | 動作 |
|---|---|
| 全部是原版 v1.2，可以套用 | 繼續第 2 步 |
| 版本不明 | **停止**。把完整輸出回報 |

把 check 的完整輸出存檔。記錄表（`patches/README.md` 第 6 節）需要它。

2. 套用：

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh apply
```

必須顯示「套用完成」。**記下備份目錄路徑**
（`/var/tmp/rpz_patch1b_backup_<時間>`）。

3. 確認：

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh check
```

必須顯示「已套用 Phase 1B 修正」。

4. 繼續第 4 節的功能驗證。

## 4. 套用後功能驗證（同時驗證 Patch 1 與 Patch 2）

### 4.1 驗證步驟（逐條輸入，保留完整輸出作為證據）

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

### 4.2 驗收條件（全部成立才算通過）

| # | 條件 |
|---|---|
| 1 | `main.sh RC=0` |
| 2 | 執行輸出含「使用 dnsxdump 檔案」與「處理完成」 |
| 3 | final 目錄三個檔案的時間，比測試前新 |
| 4 | revision 比測試前增加 |
| 5 | size 與測試前同量級，不是 0 |
| 6 | 排程恢復 `active` / `300`，設定已存檔 |

通過後，繼續下一本手冊：`patches/patch3_syslog/README.md`。

### 4.3 部署後觀察（試行台必做）

試行台在完成 Patch 3（`patches/patch3_syslog/README.md`）之後，
開始觀察期。

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

5. 試行台觀察一個工作日。無異常後，依 `patches/README.md`
   第 3 節部署其餘設備。

## 5. 本 patch 特有狀況

| 狀況 | 意義 | 動作 |
|---|---|---|
| 套用 Patch 3 之後，本 patch 的 check 回報「版本不明」（RC=2） | 預期行為。舊工具不認得 Phase 1C 版的 `main.sh`。保留策略仍然生效 | 不需處理 |
| 已套用 Patch 3 的設備，執行本 patch 的 rollback 被拒絕 | 版本檢查的保護，不是故障 | 照 `patches/README.md` 第 5 節，先還原 Patch 3 |
| log 出現「數量上限清理: … 保留 24 個」 | 正常。這是本 patch 新增的自動清理 | 不需處理 |

## 6. 還原

只在跨 patch 全部還原時執行。順序見 `patches/README.md` 第 5 節。
本 patch 的還原指令：

```bash
bash /var/tmp/rpz_patch_phase1b_v1.sh rollback /var/tmp/rpz_patch1b_backup_<時間>
```

還原工具只接受部署時自動建立的原版備份。

## 7. 開發端資訊（部署時不需要讀）

| 項目 | 內容 |
|---|---|
| builder | `patches/patch2_retention/build_patch_phase1b.sh`。**必須在歷史版本 `f560b80` 的 checkout 重建**：tracked `main.sh` 已前進到 Phase 1C 版，builder 的 md5 檢查會正確拒絕目前版本——這是保護 |
| 設計文件 | `docs/PHASE1B_DESIGN_20260823.md` |
| 自動化測試 | `tests/lab/f5_patch_1b_test.sh`，112 項檢查 |
| 獨立審核 | 三輪，見 `docs/reviews/` 目錄 |
| 勘誤記錄 | patch 內嵌的 `main.sh` 是凍結的歷史版本，含兩處舊章節號註解（「第 13 節」應為 `process.md` 第 2 節；「第 15 節」應為第 27 節）。tracked source 已於 Phase 1C（2026-09-04）修正。`docs/PHASE1B_DESIGN_20260823.md` 的程式碼樣本與凍結版逐字一致，同樣保留。兩者皆不影響行為 |
