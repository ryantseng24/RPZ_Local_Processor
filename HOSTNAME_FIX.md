# F5 hostname 命令問題修正記錄

## 📅 發現日期
**2025-11-12 20:30**

## 🐛 問題描述

### 錯誤 Log
```
Wed Nov 12 20:15:01 CST 2025 err dns.ryantseng.work scriptd[3590] 014f0013
Script (/Common/rpz_processor_script) generated this Tcl error:
(script did not successfully complete: (child process exited abnormally
```

### 問題模式
- ✅ **無更新時**（SOA 未變更）：沒有錯誤
- ❌ **有更新時**（SOA 變更執行實際處理）：出現錯誤

### 用戶反饋
> "更新資料除了rpztw 以及phishtw, 你再檢查一下script , 有類似的log"

---

## 🔍 根本原因分析

### 問題定位過程

1. **初步分析**：錯誤只在有實際更新時出現
2. **排除可能**：
   - ✅ update_datagroup.sh 返回值正常（exit 0）
   - ✅ DataGroup 更新成功（rpztw 58605 筆，phishtw 821 筆）
   - ✅ cleanup 函數正常
3. **Process Tracing**：使用 strace 發現有子進程返回 1
4. **命令追蹤**：使用 `bash -x` 發現 `hostname` 命令返回 1

### 關鍵發現

**F5 TMOS 系統中的 hostname 命令行為異常**：

```bash
# 在 F5 10.8.34.234 上測試
$ hostname ; echo $?
Use the TMOS shell utility to make changes to the system configuration.
For more information, see "tmsh help sys global-settings."
1  # ⚠️ 返回退出碼 1！
```

對比正常命令：
```bash
$ uname -n ; echo $?
dns.ryantseng.work
0  # ✅ 返回 0（正常）
```

### 為什麼會出錯？

在腳本中使用 `$(hostname)` 進行命令替換時：

```bash
echo "$timestamp $(hostname) INFO: updated DataGroup..." >> "$LOG_FILE"
```

執行流程：
1. Bash 執行 `hostname` 命令作為子進程
2. `hostname` 返回退出碼 1
3. F5 iCall scriptd 監控到子進程返回非零
4. scriptd 報告："child process exited abnormally"
5. 即使主腳本最終 exit 0，錯誤已被記錄

---

## 🔧 解決方案

### 修正方法

將所有 `$(hostname)` 替換為 `$(uname -n)`：

```bash
# 修正前（有問題）
echo "$timestamp $(hostname) INFO: RPZ processing completed" >> "$LOG_FILE"

# 修正後（正常）
echo "$timestamp $(uname -n) INFO: RPZ processing completed" >> "$LOG_FILE"
```

### 修正位置

#### scripts/main.sh (8 處)
```bash
line 124: $(uname -n) INFO: RPZ SOA not changed, skip update
line 129: $(uname -n) ERROR: RPZ SOA check failed
line 135: $(uname -n) INFO: RPZ SOA changed, start processing
line 143: $(uname -n) ERROR: RPZ extraction failed
line 152: $(uname -n) ERROR: RPZ parsing failed
line 161: $(uname -n) ERROR: DataGroup generation failed
line 170: $(uname -n) ERROR: F5 update failed
line 186: $(uname -n) INFO: RPZ processing completed in Xs
```

#### scripts/update_datagroup.sh (3 處)
```bash
line 33: $(uname -n) ERROR: source file not found
line 47: $(uname -n) INFO: updated DataGroup ...
line 51: $(uname -n) ERROR: failed to update DataGroup
```

---

## ✅ 修正後的預期行為

### 無更新情況（已驗證 - 20:35:00）
```
2025-11-12 20:35:00 dns.ryantseng.work INFO: RPZ SOA not changed, skip update
```
✅ 沒有 scriptd 錯誤

### 有更新情況（待下次 SOA 變更驗證）
**預期 Log**：
```
2025-11-12 XX:XX:00 dns.ryantseng.work INFO: RPZ SOA changed, start processing
2025-11-12 XX:XX:00 INFO: dnsxdump exported XXXXX lines
2025-11-12 XX:XX:01 dns.ryantseng.work INFO: updated DataGroup rpztw (58605 records...)
2025-11-12 XX:XX:01 dns.ryantseng.work INFO: updated DataGroup phishtw (821 records...)
[tmm notices: DataGroup queued/finished]
2025-11-12 XX:XX:01 dns.ryantseng.work INFO: RPZ processing completed in Xs
```
✅ **預期沒有 scriptd 錯誤訊息**

---

## 📊 影響分析

### 修正前
- ❌ 每次 SOA 變更執行更新都會產生一個 `err` log
- ❌ 誤導性錯誤訊息（實際功能正常）
- ❌ 可能觸發監控告警
- ❌ 增加 log 檔案中的錯誤記錄
- ✅ 但系統功能完全正常（DataGroup 成功更新）

### 修正後
- ✅ SOA 變更執行更新時不產生錯誤 log
- ✅ 只有正常的 INFO log
- ✅ 不會觸發誤報告警
- ✅ Log 更乾淨易讀
- ✅ 系統功能正常

---

## 🧪 測試驗證

### 測試案例 1: 無更新情況（已驗證）
**執行時間**: 2025-11-12 20:35:00
**結果**: ✅ 通過
```
2025-11-12 20:35:00 dns.ryantseng.work INFO: RPZ SOA not changed, skip update
```
- 沒有 scriptd 錯誤
- 行為符合預期

### 測試案例 2: 有更新情況（待驗證）
**預期執行**: 下次 SOA Serial 變更時（自然觸發或手動修改）
**檢查項目**:
1. ✅ rpztw DataGroup 更新成功
2. ✅ phishtw DataGroup 更新成功
3. ✅ 沒有 "child process exited abnormally" 錯誤
4. ✅ 所有 log 使用 `dns.ryantseng.work` 作為 hostname

**驗證命令**:
```bash
# 檢查最近的更新 log
tail -100 /var/log/ltm | grep -E '(RPZ.*processing|scriptd.*rpz)'

# 確認沒有 scriptd 錯誤
tail -100 /var/log/ltm | grep 'err.*scriptd.*rpz'

# 查看 DataGroup 更新記錄
tail -100 /var/log/ltm | grep 'updated DataGroup'
```

---

## 📝 技術細節

### F5 TMOS 命令行為差異

| 命令 | 輸出 | 退出碼 | 是否適用於腳本 |
|------|------|--------|---------------|
| `hostname` | ⚠️ 警告訊息 + hostname | ❌ 1 | ❌ 不適合 |
| `uname -n` | ✅ hostname | ✅ 0 | ✅ 適合 |
| `tmsh list sys global-settings hostname` | ✅ 配置輸出 | ✅ 0 | ⚠️ 輸出複雜 |

### iCall scriptd 行為

F5 iCall scriptd 會：
1. 監控所有子進程的退出碼
2. 當子進程返回非零時：
   - 檢查 stdout/stderr 是否有輸出
   - 即使主腳本最終 exit 0 也會報錯
3. 記錄為 Tcl error：`child process exited abnormally`

### Bash 命令替換

```bash
# 命令替換 $(...) 會在子 shell 中執行
result=$(command)

# 如果 command 返回非零：
# - 在 set -e 模式下會中斷（我們的情況）
# - 在非 set -e 模式下會繼續但 scriptd 仍會捕獲

# 解決方案：確保所有子命令返回 0
result=$(command) || result="default"  # 方案 1
result=$(command || true)              # 方案 2
result=$(working_command)              # 方案 3（本次採用）
```

---

## 🎓 經驗教訓

### 1. F5 系統命令的特殊性
- F5 TMOS 有些命令與標準 Linux 行為不同
- 需要在實際環境中測試命令返回值
- 不能假設常用命令都返回 0

### 2. 子進程退出碼的重要性
- iCall scriptd 對子進程退出碼極為敏感
- 即使主腳本處理了錯誤，子進程的非零退出仍會被捕獲
- 需要確保**所有**子進程都返回 0（包括命令替換）

### 3. 除錯策略
- 從錯誤模式入手（何時出現、何時不出現）
- 使用 strace 追蹤進程執行
- 使用 `bash -x` 追蹤命令執行
- 直接測試可疑命令的退出碼

### 4. 最佳實踐
- **命令替換**：使用可靠的、已知返回 0 的命令
- **錯誤處理**：對不可控的外部命令使用 `|| true`
- **環境差異**：在目標環境測試，不要依賴本地行為
- **日誌記錄**：只輸出到 stderr（log 函數），避免 stdout 污染

---

## 📚 相關文件

- **修正檔案**:
  - `scripts/main.sh`
  - `scripts/update_datagroup.sh`
- **錯誤 Log 定義**: `docs/ERROR_LOG_DEFINITIONS.md`
- **前次修正記錄**: `ICALL_LOG_ERROR_FIX.md`
- **日誌函數**: `scripts/utils.sh`

---

## 🔗 關聯問題

這是 F5 iCall scriptd 系列問題的第二個修正：

1. **第一個問題** (2025-11-12 17:15-17:55)：
   - debug echo 輸出 + ANSI 顏色碼 + 非零退出碼
   - 解決：移除 echo、禁用顏色、修改退出碼邏輯、重定向輸出

2. **第二個問題** (2025-11-12 20:15-20:35)：⭐ 本次
   - hostname 命令返回 1
   - 解決：替換為 uname -n

### 共同模式
- 都是子進程返回非零導致
- 都只在特定情況下出現（有更新執行時）
- 都不影響實際功能，只產生誤導性錯誤
- 都需要深入追蹤才能定位

---

## ✅ 驗證清單

部署後驗證（待下次 SOA 變更）：
- [ ] 手動觸發更新或等待自然 SOA 變更
- [ ] 檢查 `/var/log/ltm` 確認無 err 級別的 scriptd 訊息
- [ ] 確認 DataGroup 正常更新（rpztw, phishtw）
- [ ] 驗證 hostname 在 log 中正確顯示為 `dns.ryantseng.work`
- [ ] 檢查 iCall 執行統計無異常

---

**修正完成**: 2025-11-12 20:32
**部署時間**: 2025-11-12 20:32
**測試狀態**: ⏳ 待下次 SOA 變更驗證
**預期結果**: ✅ 消除 "child process exited abnormally" 錯誤

**實際驗證**: 待補充（等待下次實際更新執行）

---

## 📝 後續追蹤

### 下次更新時需確認
1. 沒有 scriptd 錯誤
2. hostname 正確顯示
3. 所有功能正常

### 如仍有問題
可能需要檢查：
- 是否還有其他命令返回非零
- cleanup 函數是否有問題
- tmsh 命令是否穩定

---

**文件建立**: 2025-11-12 20:35
**作者**: Claude Code with Ryan
**版本**: 1.0
**最後更新**: 2025-11-12 20:35
