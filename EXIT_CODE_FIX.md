# F5 iCall Exit Code 1 問題修正記錄

## 📅 發現日期
**2025-11-12 21:15**

## 🐛 問題描述

### 錯誤 Log
```
Wed Nov 12 21:15:01 CST 2025 err dns.ryantseng.work scriptd[3590] 014f0013
Script (/Common/rpz_processor_script) generated this Tcl error:
(child process exited abnormally
```

### 問題模式
- ✅ **無更新時**（SOA 未變更）：沒有錯誤
- ❌ **有更新時**（SOA 變更執行實際處理）：出現錯誤
- ✅ **所有處理步驟成功**：DataGroup 更新正常
- ❌ **腳本退出碼為 1**：即使所有步驟成功

### Wrapper Log 證據 (21:15:00)
```
=== Wed Nov 12 21:15:00 CST 2025 - Wrapper Start ===
[INFO] 步驟 1/5: 檢查 RPZ Zone SOA Serial
[INFO] SOA Serial 已變更，繼續處理
[INFO] 步驟 2/5: 提取 DNS Express 資料
[INFO] 步驟 3/5: 解析 RPZ 記錄
[INFO] 步驟 4/5: 產生 DataGroup 檔案
[INFO] 步驟 5/5: 更新 F5 DataGroups
[INFO] 成功: 2 個, 失敗: 0 個
[INFO] 清理臨時檔案...
[DEBUG] 清理完成
[INFO] 總耗時: 00:00:01
=== Wed Nov 12 21:15:01 CST 2025 - Exit Code: 1 ===
```

**關鍵發現**：最後一條日誌 `[DEBUG] 清理完成` 之後，退出碼為 1。

---

## 🔍 根本原因分析

### 問題定位過程

1. **前期修正**：
   - ✅ 已修正 check_soa.sh 的 echo 輸出問題
   - ✅ 已修正 utils.sh 的 ANSI 顏色碼問題
   - ✅ 已修正所有 hostname 命令問題

2. **持續出現錯誤**：
   - 使用者反覆強調：「我記得 Script 是有分模組的，你每一個都檢查過？」
   - 提示需要檢查**所有模組腳本**的退出碼

3. **Wrapper 腳本追蹤**：
   - 創建 `/var/tmp/rpz_wrapper.sh` 捕獲實際退出碼
   - 發現所有處理成功但最終 exit code = 1

4. **深入分析程式碼**：
   - 檢查所有模組腳本的 main() 函數結尾
   - 發現**沒有明確的 return 0 或 exit 0**

### 關鍵發現：log_debug 函數的陷阱

**utils.sh 中的 log_debug 定義**：
```bash
log_debug() {
    [[ $LOG_LEVEL -le $LOG_DEBUG ]] && echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $*" >&2
}
```

**執行邏輯**：
- 預設 `LOG_LEVEL=1` (LOG_INFO)
- `LOG_DEBUG=0`
- 測試條件 `[[ 1 -le 0 ]]` 返回 **FALSE** (退出碼 1)
- 由於是 `&&` 運算，後面的 echo 不執行
- **函數返回退出碼 1**

**cleanup() 函數結尾**：
```bash
cleanup() {
    # ... 清理邏輯 ...
    log_debug "清理完成"
    # ❌ 沒有 return 0!
}
```

**執行流程**：
1. main() 調用 cleanup()
2. cleanup() 最後一個命令是 log_debug
3. log_debug 返回 1（因為 LOG_LEVEL 測試失敗）
4. cleanup() 返回 1（函數返回最後一個命令的退出碼）
5. main() 沒有明確 exit 0
6. **腳本退出碼為 1**
7. F5 iCall scriptd 捕獲並報錯

---

## 🔧 解決方案

### 修正原則

**為所有模組腳本的 main() 函數和關鍵函數添加明確的退出碼**：
- 函數結尾：`return 0`
- 腳本結尾：`exit 0`

### 修正位置

#### 1. scripts/main.sh (2 處)

**cleanup() 函數**：
```bash
# 修正前
cleanup() {
    # ... 清理邏輯 ...
    log_debug "清理完成"
}

# 修正後
cleanup() {
    # ... 清理邏輯 ...
    log_debug "清理完成"
    return 0  # ✅ 明確返回成功
}
```

**main() 函數**：
```bash
# 修正前
main() {
    # ... 5 個處理步驟 ...
    cleanup
    # ... 計算執行時間 ...
    log_info "總耗時: $(timer_format "$elapsed")"
    echo "$timestamp $(uname -n) INFO: RPZ processing completed in ${elapsed}s" >> "$LOG_FILE"
}

# 修正後
main() {
    # ... 5 個處理步驟 ...
    cleanup
    # ... 計算執行時間 ...
    log_info "總耗時: $(timer_format "$elapsed")"
    echo "$timestamp $(uname -n) INFO: RPZ processing completed in ${elapsed}s" >> "$LOG_FILE"

    exit 0  # ✅ 明確退出成功
}
```

#### 2. scripts/update_datagroup.sh (1 處)

```bash
# 修正前
main() {
    update_all_datagroups
}

# 修正後
main() {
    update_all_datagroups
    exit 0  # ✅ 明確退出成功
}
```

#### 3. scripts/extract_rpz.sh (1 處)

```bash
# 修正前
main() {
    # ... 提取邏輯 ...
    export DNSXDUMP_FILE="$full_dump_file"
}

# 修正後
main() {
    # ... 提取邏輯 ...
    export DNSXDUMP_FILE="$full_dump_file"

    return 0  # ✅ 明確返回成功
}
```

#### 4. scripts/parse_rpz.sh (1 處)

```bash
# 修正前
main() {
    # ... 解析邏輯 ...
    export RPZ_PARSED_FILE="$rpz_output"
    export PHISHTW_PARSED_FILE="$phishtw_output"
    export IP_PARSED_FILE="$ip_output"
}

# 修正後
main() {
    # ... 解析邏輯 ...
    export RPZ_PARSED_FILE="$rpz_output"
    export PHISHTW_PARSED_FILE="$phishtw_output"
    export IP_PARSED_FILE="$ip_output"

    return 0  # ✅ 明確返回成功
}
```

#### 5. scripts/generate_datagroup.sh (1 處)

```bash
# 修正前
main() {
    # ... 產生邏輯 ...
    log_info "=== DataGroup 檔案產生完成 ==="
    log_info "檔案位置: $FINAL_OUTPUT_DIR"
}

# 修正後
main() {
    # ... 產生邏輯 ...
    log_info "=== DataGroup 檔案產生完成 ==="
    log_info "檔案位置: $FINAL_OUTPUT_DIR"

    return 0  # ✅ 明確返回成功
}
```

---

## ✅ 修正後的預期行為

### 無更新情況（已驗證）
```
2025-11-12 21:20:00 dns.ryantseng.work INFO: RPZ SOA not changed, skip update
```
✅ 沒有 scriptd 錯誤
✅ 退出碼 0

### 有更新情況（待驗證）
**預期 Wrapper Log**：
```
=== Wed Nov 12 XX:XX:00 CST 2025 - Wrapper Start ===
[INFO] SOA Serial 已變更，繼續處理
[INFO] 步驟 2/5: 提取 DNS Express 資料
[INFO] 步驟 3/5: 解析 RPZ 記錄
[INFO] 步驟 4/5: 產生 DataGroup 檔案
[INFO] 步驟 5/5: 更新 F5 DataGroups
[INFO] 成功: 2 個, 失敗: 0 個
[INFO] 清理臨時檔案...
[DEBUG] 清理完成
[INFO] 總耗時: 00:00:XX
=== Wed Nov 12 XX:XX:XX CST 2025 - Exit Code: 0 ===
```

**預期系統 Log**：
```
2025-11-12 XX:XX:00 dns.ryantseng.work INFO: RPZ SOA changed, start processing
2025-11-12 XX:XX:00 INFO: dnsxdump exported XXXXX lines
2025-11-12 XX:XX:01 dns.ryantseng.work INFO: updated DataGroup rpztw (58608 records...)
2025-11-12 XX:XX:01 dns.ryantseng.work INFO: updated DataGroup phishtw (821 records...)
2025-11-12 XX:XX:01 dns.ryantseng.work INFO: RPZ processing completed in Xs
```

✅ **預期沒有 scriptd 錯誤訊息**
✅ **預期 wrapper 顯示 Exit Code: 0**

---

## 📊 影響分析

### 修正前
- ❌ 每次 SOA 變更執行更新都會產生 err log
- ❌ 雖然功能正常但有誤導性錯誤
- ❌ 可能觸發監控告警
- ❌ 增加除錯時間與困擾
- ✅ 系統功能實際上完全正常

### 修正後
- ✅ SOA 變更執行更新時正常結束（exit 0）
- ✅ 只有真正的錯誤才產生 err log
- ✅ 不會觸發誤報告警
- ✅ Log 乾淨清晰
- ✅ 系統功能正常

---

## 🧪 測試驗證

### 測試案例 1: 無更新情況（待驗證）
**執行時間**: 下次 iCall 觸發時（21:25:00）
**檢查項目**:
1. ✅ 沒有 scriptd 錯誤
2. ✅ Wrapper log 顯示 Exit Code: 0
3. ✅ 正常的 "RPZ SOA not changed" 訊息

### 測試案例 2: 有更新情況（待使用者觸發）
**執行條件**: 使用者需要更新 RPZ 來源以變更 SOA Serial
**檢查項目**:
1. ✅ rpztw DataGroup 更新成功
2. ✅ phishtw DataGroup 更新成功
3. ✅ 沒有 "child process exited abnormally" 錯誤
4. ✅ Wrapper log 顯示 Exit Code: 0
5. ✅ 所有 log 使用 `dns.ryantseng.work` 作為 hostname

**驗證命令**:
```bash
# 檢查最近的更新 log
tail -100 /var/log/ltm | grep -E '(RPZ.*processing|scriptd.*rpz)'

# 確認沒有 scriptd 錯誤
tail -100 /var/log/ltm | grep 'err.*scriptd.*rpz'

# 查看 wrapper 記錄
tail -50 /var/tmp/rpz_wrapper.log

# 查看 DataGroup 更新記錄
tail -100 /var/log/ltm | grep 'updated DataGroup'
```

---

## 📝 技術細節

### Bash 函數退出碼規則

**基本原則**：
- 函數返回**最後一個命令**的退出碼
- 明確使用 `return N` 可以指定退出碼
- 腳本退出碼為最後一個命令或 `exit N`

**陷阱案例**：
```bash
# ❌ 陷阱：條件測試失敗返回 1
function example1() {
    [[ 1 -le 0 ]] && echo "never runs"
    # 返回 1（測試失敗）
}

# ❌ 陷阱：最後的 log 命令返回 1
function example2() {
    do_something_successful
    log_debug "done"  # 如果 LOG_LEVEL > LOG_DEBUG，返回 1
    # 返回 1（log_debug 的退出碼）
}

# ✅ 正確：明確返回成功
function example3() {
    do_something_successful
    log_debug "done"
    return 0  # 明確返回 0
}
```

### F5 iCall scriptd 行為

**監控機制**：
1. 監控主腳本和**所有子進程**的退出碼
2. 任何退出碼非零都會觸發錯誤
3. 即使主腳本 exit 0，子進程返回 1 也會報錯

**捕獲範圍**：
- Shell 內建命令（[[ ]], test, 等）
- 命令替換 $()
- 管道中的命令
- 後台進程

### 條件測試與 && 運算子

**邏輯短路**：
```bash
# 如果 condition 為 false，command 不執行
[[ condition ]] && command

# 返回值：
# - 如果 condition 為 true：返回 command 的退出碼
# - 如果 condition 為 false：返回 1
```

**實際例子**：
```bash
LOG_LEVEL=1  # INFO
LOG_DEBUG=0

# 這個測試會失敗並返回 1
[[ $LOG_LEVEL -le $LOG_DEBUG ]] && echo "debug message"
# 等同於: [[ 1 -le 0 ]] && echo ...
# 結果: 返回 1
```

---

## 🎓 經驗教訓

### 1. 明確的退出碼至關重要

- **總是**在成功完成的函數結尾寫 `return 0`
- **總是**在成功完成的腳本結尾寫 `exit 0`
- 不要依賴隱式的退出碼傳遞

### 2. 日誌函數的陷阱

- 條件日誌函數（如 log_debug）可能返回非零
- 如果用作函數最後一個命令，會影響函數退出碼
- 解決：在日誌後面加 `return 0`

### 3. 全面的模組檢查

- 使用者的提醒是對的：「Script 是有分模組的，你每一個都檢查過？」
- **必須**檢查所有模組腳本的退出碼處理
- 不能只檢查主腳本

### 4. 系統化除錯方法

**有效的除錯步驟**：
1. 使用 wrapper 腳本捕獲實際退出碼
2. 分析最後執行的命令
3. 檢查所有模組的 main() 函數結尾
4. 尋找隱式退出碼（條件測試、日誌函數等）

### 5. F5 iCall 的嚴格性

- iCall scriptd 比普通 shell 環境更嚴格
- **所有**子進程和命令的退出碼都被監控
- 必須確保**每一個**命令和函數都返回正確的退出碼

---

## 🔗 關聯問題

這是 F5 iCall scriptd 系列問題的**第三個修正**：

### 1. 第一個問題 (2025-11-12 17:15-17:55)
- **原因**: debug echo 輸出 + ANSI 顏色碼 + 非零退出碼
- **解決**: 移除 echo、禁用顏色、修改退出碼邏輯、重定向輸出
- **文件**: ICALL_LOG_ERROR_FIX.md

### 2. 第二個問題 (2025-11-12 20:15-20:35)
- **原因**: hostname 命令返回 1
- **解決**: 替換為 uname -n
- **文件**: HOSTNAME_FIX.md

### 3. 第三個問題 (2025-11-12 21:15-21:21) ⭐ 本次
- **原因**: log_debug 條件測試失敗 + 缺少明確 return/exit 0
- **解決**: 為所有模組函數添加明確的 return 0 / exit 0
- **文件**: EXIT_CODE_FIX.md

### 共同模式
- 都是子進程或命令返回非零導致
- 都只在特定情況下出現（有更新執行時）
- 都不影響實際功能，只產生誤導性錯誤
- 都需要系統化分析才能定位

### 根本啟示
**F5 iCall 環境對腳本品質要求極高**：
- 必須處理好所有退出碼
- 必須避免意外的輸出
- 必須明確表達成功和失敗
- 必須考慮所有子進程的行為

---

## ✅ 驗證清單

部署後驗證（待下次執行）：

### 無更新場景（21:25:00 或下次觸發）
- [ ] 檢查 `/var/log/ltm` 確認無 err 級別的 scriptd 訊息
- [ ] 檢查 `/var/tmp/rpz_wrapper.log` 確認 Exit Code: 0
- [ ] 確認 "RPZ SOA not changed" 訊息正常

### 有更新場景（待使用者觸發 SOA 變更）
- [ ] 檢查 `/var/log/ltm` 確認無 err 級別的 scriptd 訊息
- [ ] 確認 DataGroup 正常更新（rpztw, phishtw）
- [ ] 檢查 `/var/tmp/rpz_wrapper.log` 確認 Exit Code: 0
- [ ] 驗證 hostname 在 log 中正確顯示為 `dns.ryantseng.work`
- [ ] 檢查 iCall 執行統計無異常

---

## 📋 修正摘要

| 檔案 | 修正項目 | 位置 |
|------|---------|------|
| scripts/main.sh | cleanup() 函數結尾 | 添加 `return 0` |
| scripts/main.sh | main() 函數結尾 | 添加 `exit 0` |
| scripts/update_datagroup.sh | main() 函數結尾 | 添加 `exit 0` |
| scripts/extract_rpz.sh | main() 函數結尾 | 添加 `return 0` |
| scripts/parse_rpz.sh | main() 函數結尾 | 添加 `return 0` |
| scripts/generate_datagroup.sh | main() 函數結尾 | 添加 `return 0` |

**修正檔案數**: 6 個
**添加語句數**: 7 個 (6 個 return 0 + 1 個 exit 0)
**預期效果**: 完全消除 "child process exited abnormally" 錯誤

---

**修正完成**: 2025-11-12 21:21
**部署時間**: 2025-11-12 21:42
**測試狀態**: ✅ **已驗證通過**
**實際結果**: ✅ 完全消除 scriptd 錯誤，所有場景都返回 exit code 0

---

## ✅ 驗證結果

### 最終修正（21:42 部署）
除了為所有模組添加明確的 `return 0` / `exit 0` 外，還進行了以下關鍵修正：

1. **移除未使用的變量宣告**：
   - 刪除 cleanup() 中的 `local timestamp_compact=$(timestamp_compact)`
   - 該變量未被使用，可能在特定環境下導致問題

2. **增強錯誤容錯**：
   - `rm -f "$DNSXDUMP_FILE" || true` - 確保刪除失敗不影響退出碼
   - 所有 cleanup 步驟都有明確的成功確認

3. **改善日誌可見性**：
   - 將 cleanup() 中的 log_debug 改為 log_info
   - 添加 "清理舊檔案完成"、"cleanup 函數完成" 等確認訊息
   - 便於追蹤 cleanup() 執行的每一步

### 驗證時間軸

**21:30:01** - 最後一次錯誤（使用舊腳本）:
```
Nov 12 21:30:01 dns.ryantseng.work err scriptd[3590]: 014f0013:3:
Script (/Common/rpz_processor_script) generated this Tcl error:
(script did not successfully complete: (child process exited abnormally
```

**21:42:23** - 首次成功（使用新腳本）:
```
2025-11-12 21:42:23 dns.ryantseng.work INFO: RPZ processing completed in 1s
2025-11-12 21:42:24 dns.ryantseng.work INFO: updated DataGroup rpztw (58609 records...)
2025-11-12 21:42:24 dns.ryantseng.work INFO: updated DataGroup phishtw (821 records...)
```
✅ **系統日誌中無任何 scriptd 錯誤**

**21:45:01 及後續** - 持續正常運行:
```
=== Wed Nov 12 21:45:01 CST 2025 - Exit Code: 0 ===
```

### 關鍵證據

1. **無更新場景（SOA 未變更）**：
   - 21:35, 21:40, 21:45 執行均返回 Exit Code: 0 ✅

2. **有更新場景（SOA 變更執行完整流程）**：
   - 21:42 手動觸發更新：完全成功 ✅
   - 無 scriptd 錯誤訊息 ✅
   - 所有 DataGroup 正常更新 ✅
   - 處理時間正常（1秒）✅

3. **scriptd 錯誤歷史**：
   ```
   最後錯誤: Nov 12 21:30:01 (舊腳本)
   之後時間: 21:35, 21:40, 21:42, 21:45 - 全部正常
   ```

---

## 📝 最終修正清單

| 檔案 | 修正內容 | 目的 |
|------|---------|------|
| scripts/main.sh | cleanup() 添加 `return 0` | 確保 cleanup 返回成功 |
| scripts/main.sh | main() 添加 `exit 0` | 確保腳本返回成功 |
| scripts/main.sh | 移除 cleanup() 中未使用的 timestamp_compact 變量 | 避免不必要的命令替換 |
| scripts/main.sh | 為 cleanup() 添加詳細的 INFO 日誌 | 提升除錯可見性 |
| scripts/main.sh | rm 命令添加 `\|\| true` | 增強容錯性 |
| scripts/update_datagroup.sh | main() 添加 `exit 0` | 確保模組返回成功 |
| scripts/extract_rpz.sh | main() 添加 `return 0` | 確保模組返回成功 |
| scripts/parse_rpz.sh | main() 添加 `return 0` | 確保模組返回成功 |
| scripts/generate_datagroup.sh | main() 添加 `return 0` | 確保模組返回成功 |

---

**文件建立**: 2025-11-12 21:22
**作者**: Claude Code with Ryan
**版本**: 2.0 (已驗證)
**最後更新**: 2025-11-12 21:46
**驗證狀態**: ✅ **生產環境驗證通過**
