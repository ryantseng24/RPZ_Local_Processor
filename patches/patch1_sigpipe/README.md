# Patch 1：修正黑名單更新失敗

| 項目 | 內容 |
|---|---|
| patch 本體 | `patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh` |
| 更換的程式 | `utils.sh`、`parse_rpz.sh`、`generate_datagroup.sh` |
| 前置條件 | 設備上的程式是原版 v1.2（用第 3 節的 check 確認） |
| 部署順序 | 三個 patch 的第 1 個。總表與共同規則見 `patches/README.md` |

**路徑約定**：檔案路徑都從 repo 根目錄起算。設備上的指令用 `/var/tmp/` 路徑。

## 1. 這個 patch 修正什麼

原始程式挑選最新暫存檔的方法，在暫存檔超過約 67 個時會不定期失敗。
黑名單因此停止更新，畫面只顯示「RPZ 解析失敗」，看不出原因。
本 patch 更換 3 個程式檔案。新方法逐一比對檔案時間，
不受檔案數量影響。

驗證環境實測（300 個暫存檔）：修正前失敗率 100%，修正後 0%。

## 2. 檔案

| 檔案 | 用途 |
|---|---|
| `patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh` | patch 本體。動作：`check` / `apply` / `rollback` |
| `patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh.sha256` | 檢查碼 |
| `patches/patch1_sigpipe/build_patch_v4.sh` | 開發端工具。不要帶到設備 |

正確的 SHA-256 值：

```
e407d6e7d0d12d1c6ca445d737208ab139437fd8504fe47d9b318754c1d37626  rpz_patch_sigpipe_v4.sh
```

傳檔與完整性驗證的步驟，見 `patches/README.md` 第 4 節。

## 3. 部署步驟

1. 檢查目前版本。這個步驟只讀取，不改任何檔案：

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh check
```

| check 顯示 | 動作 |
|---|---|
| 全部是原版 v1.2，可以套用 | 繼續第 2 步 |
| 版本不明 | **停止**。把完整輸出回報 |

把 check 的完整輸出存檔。記錄表（`patches/README.md` 第 6 節）需要它。

2. 套用：

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh apply
```

必須顯示「套用完成」。**記下輸出中的備份目錄路徑**
（`/var/tmp/rpz_patch_backup_<時間>`）。

3. 確認：

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh check
```

必須顯示「已全部套用修正」。

4. 繼續下一本手冊：`patches/patch2_retention/README.md`。

## 4. 套用後驗證

功能驗證與 Patch 2 一起做。套用 Patch 2 之後，
執行 `patches/patch2_retention/README.md` 第 4 節。

## 5. 還原

沒有「只還原 Patch 1」的情境。還原一律照 `patches/README.md`
第 5 節的順序：Patch 3 -> Patch 2 -> Patch 1。
本 patch 的還原指令在該順序的最後一步：

```bash
bash /var/tmp/rpz_patch_sigpipe_v4.sh rollback /var/tmp/rpz_patch_backup_<時間>
```

還原工具只接受部署時自動建立的原版備份。

## 6. 開發端資訊（部署時不需要讀）

| 項目 | 內容 |
|---|---|
| builder | `patches/patch1_sigpipe/build_patch_v4.sh`。對目前的 tracked source 重建，產出物與交付檔完全一致 |
| 自動化測試 | `tests/lab/f5_patch_v4_test.sh`，78 項檢查 |
| 獨立審核 | 兩輪：`docs/reviews/CODE_REVIEW_V4_STE100_20260822.md`、`docs/reviews/CODE_REVIEW_V4_ROUND2_STE100_20260822.md` |
