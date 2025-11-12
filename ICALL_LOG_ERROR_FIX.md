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
