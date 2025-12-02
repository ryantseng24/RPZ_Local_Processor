# iCall Log 錯誤修正記錄

## 📅 修正日期
**2025-11-12**

## 🐛 問題描述

### 錯誤 Log
```
Wed Nov 12 11:15:00 CST 2025
err dns.ryantseng.work scriptd[12914] 014f0013
Script (/Common/rpz_processor_script) generated this Tcl error:
(script did not successfully complete: (NO_UPDATE:2763:2763
```

### 表面現象
- ❌ F5 log 中出現 `err` 級別的錯誤訊息
- ❌ 錯誤訊息包含 `NO_UPDATE:2763:2763`
- ✅ 但系統實際運作正常，DataGroup 有正確更新

### 用戶反饋
> "主要是目前測試都可以更新成功，但是 log 裡面有一個奇怪的 log"

---

## 🔍 根本原因分析

### 問題代碼

**檔案**: `scripts/check_soa.sh:109`

```bash
# 比對 SOA Serial
if [[ "$current_soa" -le "$cached_soa" ]]; then
    log_info "Zone $zone_name 無變更 (快取: $cached_soa, 當前: $current_soa)"
    echo "NO_UPDATE:$current_soa:$cached_soa"  # ⚠️ 問題在這裡！
    return 1
fi
```

### 執行流程

```
1. check_soa.sh 執行
   ├─ 檢測 SOA Serial: 2763 (當前) vs 2763 (快取)
   ├─ 判定：無變更
   ├─ 執行 log_info ✅ (輸出到 stderr)
   ├─ 執行 echo "NO_UPDATE:2763:2763" ❌ (輸出到 stdout)
   └─ return 1 (表示無需更新)

2. main.sh 接收
   ├─ 捕獲退出碼 1
   ├─ log_info "SOA Serial 未變更，無需更新" ✅
   └─ exit 0 (正確結束) ✅

3. F5 iCall scriptd 處理
   ├─ 看到中途有子腳本返回非 0
   ├─ 發現 stdout 有輸出 "NO_UPDATE:2763:2763"
   └─ 記錄為 Tcl error ❌ (誤報！)
```

### 為什麼被當作錯誤？

**F5 iCall scriptd 的行為**：
1. 監控腳本執行的所有子進程
2. 當子進程返回非 0 退出碼時，檢查是否有 stdout 輸出
3. 如果有 stdout 輸出，將其視為錯誤訊息
4. 記錄為 `err` 級別的 log

**關鍵問題**：
- `echo` 預設輸出到 **stdout**
- `log_info` 輸出到 **stderr**（透過 `>&2` 重定向）
- iCall scriptd 對 **stdout** 非常敏感

---

## 🔧 解決方案

### 修正方法

移除所有 debug `echo` 輸出，因為：
1. ✅ 已經有完整的 `log_info/log_warn/log_error` 系統
2. ✅ Log 函數正確輸出到 stderr，不會被誤判
3. ✅ 這些 echo 是調試用途，不應在生產環境中存在

### 修正內容

**檔案**: `scripts/check_soa.sh`

**移除的輸出** (3 處)：
```bash
# 1. 初始化時 (line 102)
- echo "INIT:$current_soa"

# 2. 無需更新時 (line 109)
- echo "NO_UPDATE:$current_soa:$cached_soa"

# 3. 有更新時 (line 116)
- echo "UPDATED:$current_soa:$cached_soa"
```

**保留的輸出**：
```bash
# 所有 log_info/log_warn/log_error 都保留
log_info "初始化 SOA 快取: $zone_name (Serial: $current_soa)"
log_info "Zone $zone_name 無變更 (快取: $cached_soa, 當前: $current_soa)"
log_info "Zone $zone_name 有更新 (快取: $cached_soa, 當前: $current_soa)"
```

---

## ✅ 修正後的行為

### 執行流程（修正後）

```
1. check_soa.sh 執行
   ├─ 檢測 SOA Serial: 2763 vs 2763
   ├─ 判定：無變更
   ├─ 執行 log_info ✅ (輸出到 stderr)
   └─ return 1 (表示無需更新)

2. main.sh 接收
   ├─ 捕獲退出碼 1
   ├─ log_info "SOA Serial 未變更，無需更新" ✅
   └─ exit 0 (正確結束) ✅

3. F5 iCall scriptd 處理
   ├─ 看到腳本正常結束 (exit 0) ✅
   ├─ stdout 沒有任何輸出 ✅
   └─ 不記錄錯誤 ✅
```

### 預期 Log

**修正前**：
```
Nov 12 11:15:00 err scriptd[12914]: Script (/Common/rpz_processor_script)
generated this Tcl error: (script did not successfully complete:
(NO_UPDATE:2763:2763
```

**修正後**：
```
Nov 12 11:15:00 INFO: RPZ SOA not changed, skip update
```

乾淨清爽，沒有錯誤訊息！✅

---

## 📊 影響分析

### 修正前
- ❌ 每次 SOA 未變更都會產生一個 `err` log
- ❌ 如果每 5 分鐘執行一次，每小時會有 12 個錯誤 log
- ❌ 可能觸發監控告警
- ❌ 增加 log 檔案大小
- ✅ 但系統功能正常

### 修正後
- ✅ SOA 未變更時不產生錯誤 log
- ✅ 只有正常的 INFO log
- ✅ 不會觸發監控告警
- ✅ Log 更乾淨易讀
- ✅ 系統功能正常

---

## 🧪 測試驗證

### 測試案例 1: SOA 未變更

**預期行為**：
```bash
# 執行腳本
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh

# 預期 log (stderr)
[INFO] 步驟 1/5: 檢查 RPZ Zone SOA Serial
[INFO] Zone rpztw. 無變更 (快取: 2763, 當前: 2763)
[INFO] Zone phishtw. 無變更 (快取: 819, 當前: 819)
[INFO] SOA Serial 未變更，無需更新

# 預期 /var/log/ltm
2025-11-12 11:15:00 INFO: RPZ SOA not changed, skip update

# 預期 iCall log
✅ 無錯誤訊息
```

### 測試案例 2: SOA 有變更

**預期行為**：
```bash
# 執行腳本
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh

# 預期 log (stderr)
[INFO] 步驟 1/5: 檢查 RPZ Zone SOA Serial
[INFO] Zone rpztw. 有更新 (快取: 2763, 當前: 2764)
[INFO] SOA Serial 已變更，繼續處理
[INFO] 步驟 2/5: 提取 DNS Express 資料
...

# 預期 /var/log/ltm
2025-11-12 11:15:00 INFO: RPZ SOA changed, start processing
2025-11-12 11:15:01 INFO: RPZ processing completed in 1s

# 預期 iCall log
✅ 無錯誤訊息
```

---

## 📝 技術細節

### stdout vs stderr

**Bash 輸出重定向**：
```bash
echo "message"        # 輸出到 stdout (file descriptor 1)
echo "message" >&2    # 輸出到 stderr (file descriptor 2)
```

**utils.sh 的 log 函數**：
```bash
log_info() {
    [[ $LOG_LEVEL -le $LOG_INFO ]] && \
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*" >&2  # >&2 重定向到 stderr
}
```

### F5 iCall scriptd 行為

**正常情況**：
```bash
# 腳本返回 0，stdout 無輸出
exit 0  # ✅ 成功
```

**問題情況**：
```bash
# 子腳本返回非 0，stdout 有輸出
echo "NO_UPDATE:2763:2763"  # 輸出到 stdout
exit 1  # 雖然 main.sh 最終 exit 0，但 scriptd 看到了子進程的輸出
```

---

## 📚 相關文件

- **修正檔案**: `scripts/check_soa.sh`
- **日誌函數**: `scripts/utils.sh` (log_info, log_warn, log_error)
- **主流程**: `scripts/main.sh`
- **iCall 配置**: `config/icall_setup.sh`

---

## 🎓 經驗教訓

### 1. iCall 環境的特殊性
- F5 iCall 對腳本輸出非常敏感
- stdout 應該保持乾淨，只有必要的輸出
- Debug 訊息應該使用 log 函數輸出到 stderr

### 2. 錯誤處理最佳實踐
- 使用統一的 log 函數系統
- 避免直接使用 `echo` 輸出到 stdout
- 返回碼和錯誤訊息要分離

### 3. 生產環境 vs 開發環境
- Debug 輸出在開發時有用，但生產環境應移除
- 使用 log level 控制輸出詳細程度
- 保持 log 乾淨易讀

---

## ✅ 驗證清單

部署後驗證：
- [ ] 手動執行腳本，確認無錯誤 log
- [ ] 等待 iCall 自動執行（5 分鐘）
- [ ] 檢查 `/var/log/ltm` 確認無 err 級別訊息
- [ ] 檢查 iCall 執行統計：`tmsh show sys icall handler periodic rpz_processor_handler`
- [ ] 確認 DataGroup 正常更新

---

**修正完成**: 2025-11-12
**修正者**: Claude Code with Ryan
**測試狀態**: ⏳ 待部署驗證
**預期結果**: ✅ 消除誤報的錯誤 log

---

## 🔄 追加修正記錄 (2025-11-12 17:16-17:55)

### 部署後發現的問題

第一次修正（移除 check_soa.sh 中的 echo 語句）部署後，發現仍有錯誤：

```
Nov 12 17:20:00 dns.ryantseng.work err scriptd[12914]: 014f0013:3:
Script (/Common/rpz_processor_script) generated this Tcl error:
(script did not successfully complete: ([0;32m[INFO][0m ==========================================
```

### 根本原因分析（深層）

**F5 iCall scriptd 的行為特性**：
1. 監控所有子進程的退出碼
2. 當子進程返回非零時，捕獲**所有 stderr 輸出**（不僅僅是 stdout）
3. 將 stderr 內容視為錯誤訊息，即使主腳本最終 exit 0
4. ANSI 顏色碼會出現在錯誤訊息中，導致難以閱讀

### 完整解決方案

#### 階段 1: 移除 stdout 輸出 ✅
- **檔案**: `scripts/check_soa.sh`
- **修正**: 移除 3 個 debug echo 語句
- **時間**: 17:16
- **結果**: 部分有效，但仍有 stderr 錯誤

#### 階段 2: 禁用彩色輸出 ✅
- **檔案**: `scripts/utils.sh`
- **修正**: 自動檢測 TTY，非互動環境禁用 ANSI 顏色碼
- **時間**: 17:26
- **程式碼**:
```bash
if [[ -t 2 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    # 有 TTY 且未禁用顏色
    readonly COLOR_GREEN='\033[0;32m'
    # ...
else
    # 無 TTY（如 iCall 環境）或明確禁用顏色
    readonly COLOR_GREEN=''
    # ...
fi
```
- **結果**: 移除了 ANSI 碼，但仍有 stderr 錯誤

#### 階段 3: 修改退出碼邏輯 ✅
- **問題**: 即使使用 `set +e`，iCall scriptd 仍會捕獲子進程的非零退出碼
- **解決方案**:
  1. **check_soa.sh**: 總是返回 0，使用 stdout 輸出狀態字串
  2. **main.sh**: 檢查輸出字串而不是退出碼

- **檔案 1**: `scripts/check_soa.sh`
  ```bash
  # 修正前：
  if [[ $update_needed -eq 1 ]]; then
      log_info "至少有一個 Zone 需要更新"
      return 0
  else
      log_info "所有 Zones 均無變更"
      return 1  # ❌ 導致 iCall 誤判
  fi

  # 修正後：
  if [[ $update_needed -eq 1 ]]; then
      log_info "至少有一個 Zone 需要更新"
      echo "UPDATE_NEEDED"
      return 0  # ✅ 總是成功
  else
      log_info "所有 Zones 均無變更"
      echo "NO_UPDATE"
      return 0  # ✅ 總是成功
  fi
  ```

- **檔案 2**: `scripts/main.sh`
  ```bash
  # 修正前：
  if ! bash "${SCRIPT_DIR}/check_soa.sh" check-all; then
      log_info "SOA Serial 未變更，無需更新"
      exit 0
  fi

  # 修正後：
  local soa_check_output
  soa_check_output=$(bash "${SCRIPT_DIR}/check_soa.sh" check-all 2>&1 | \
                     grep -E '^(UPDATE_NEEDED|NO_UPDATE)$' | tail -1)

  if [[ "$soa_check_output" == "NO_UPDATE" ]]; then
      log_info "SOA Serial 未變更，無需更新"
      exit 0
  elif [[ "$soa_check_output" != "UPDATE_NEEDED" ]]; then
      log_error "SOA 檢查失敗"
      exit 1
  fi
  ```

- **時間**: 17:32
- **結果**: 仍有錯誤（可能因為 iCall 還是捕獲了 stderr）

#### 階段 4: 修改 iCall 配置 ✅ (最終方案)
- **檔案**: F5 iCall script 配置
- **修正**: 重定向所有輸出到檔案，避免 scriptd 捕獲 stderr
- **時間**: 17:40-17:45
- **命令**:
```bash
tmsh modify sys icall script rpz_processor_script definition \
  '{ exec bash /var/tmp/RPZ_Local_Processor/scripts/main.sh >> /var/tmp/icall_debug.log 2>&1 }'
```

### 驗證結果

**修正前**（17:15-17:40）：
```
Nov 12 17:20:00 err scriptd[12914]: Script generated this Tcl error:
(script did not successfully complete: ([0;32m[INFO][0m ==...
Nov 12 17:25:00 err scriptd[12914]: ... ([INFO] ==...  (無顏色碼)
Nov 12 17:30:00 err scriptd[12914]: ... ([INFO] ==...
```

**修正後**（17:50-17:55）：
```
2025-11-12 17:50:00 dns.ryantseng.work INFO: RPZ SOA not changed, skip update
2025-11-12 17:55:00 dns.ryantseng.work INFO: RPZ SOA not changed, skip update
```

✅ **沒有任何 scriptd 錯誤訊息！**

### 技術總結

1. **初步修正有效但不足**：移除 stdout 輸出只解決了部分問題
2. **F5 iCall 的特殊性**：不僅監控 stdout，也監控 stderr，並對子進程退出碼極為敏感
3. **多層解決方案**：
   - 應用層：移除 debug 輸出
   - 函式層：禁用彩色輸出
   - 邏輯層：修改退出碼機制
   - 配置層：重定向輸出（最終關鍵）

### 經驗教訓

1. **F5 iCall 最佳實踐**：
   - 避免子進程返回非零退出碼
   - 或重定向所有輸出避免 scriptd 捕獲
   - stderr 輸出在 iCall 環境中需要特別小心

2. **除錯策略**：
   - 手動執行測試不一定能重現 iCall 環境的問題
   - 需要理解調度器（scriptd）的行為特性
   - 多層次逐步排查，不要放棄

3. **生產環境部署**：
   - 小步快跑，每次修正後驗證
   - 保留 debug 能力（輸出到檔案而不是 stderr）
   - 文件記錄完整的故障排除過程

---

**最終修正完成**: 2025-11-12 17:55
**測試狀態**: ✅ 已驗證（連續 2 次執行無錯誤）
**實際結果**: ✅ 完全消除誤報的錯誤 log
**修正檔案**:
- `scripts/check_soa.sh` (返回值邏輯)
- `scripts/main.sh` (檢查邏輯)
- `scripts/utils.sh` (彩色輸出)
- F5 iCall script 配置 (輸出重定向)
