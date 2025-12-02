# RPZ Local Processor - 錯誤 Log 定義

## 📋 目錄
- [概述](#概述)
- [錯誤級別說明](#錯誤級別說明)
- [錯誤 Log 清單](#錯誤-log-清單)
- [監控建議](#監控建議)

---

## 概述

此文件記錄 RPZ Local Processor 系統中所有定義的錯誤和警告 log。
所有錯誤訊息會同時記錄到：
- **stderr**：透過 `log_error()` / `log_warn()` 函數輸出
- **/var/log/ltm**：透過 `echo >> $LOG_FILE` 寫入（僅 ERROR 級別）

**Log 檔案位置**：`/var/log/ltm`
**日誌格式**：`YYYY-MM-DD HH:MM:SS hostname LEVEL: message`

---

## 錯誤級別說明

| 級別 | 函數 | 說明 | 影響 |
|------|------|------|------|
| **ERROR** | `log_error()` | 嚴重錯誤，腳本會退出 | 處理流程中斷 |
| **WARN** | `log_warn()` | 警告訊息，不影響執行 | 繼續執行但需注意 |
| **INFO** | `log_info()` | 正常資訊訊息 | 無影響 |
| **DEBUG** | `log_debug()` | 除錯訊息 | 無影響 |

---

## 錯誤 Log 清單

### 1️⃣ 步驟 1: SOA Serial 檢查 (`check_soa.sh`)

#### ❌ ERROR: SOA Serial 檢查失敗

**條件**：
- 無法從 DNS Express 取得 Zone 的 SOA Serial
- dnsxdump 執行失敗或返回空值

**Log 位置**：
- `scripts/check_soa.sh:90`
- `scripts/main.sh:129` (主流程)

**實際訊息**：
```
stderr: [ERROR] 無法取得 rpztw. 的 SOA Serial
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: RPZ SOA check failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ iCall 會記錄執行失敗
- ❌ 不會繼續提取和更新 DataGroup

**排查方向**：
- 檢查 dnsxdump 指令是否正常：`/usr/local/bin/dnsxdump`
- 確認 DNS Express Zone 是否正常載入：`tmsh list ltm dns zone`
- 查看 Zone 是否有 SOA 記錄

---

#### ⚠️ WARN: 無法取得 SOA Serial (子函數)

**條件**：
- `get_zone_soa()` 函數執行失敗

**Log 位置**：
- `scripts/check_soa.sh:36`

**實際訊息**：
```
stderr: [WARN] 無法取得 rpztw. 的 SOA Serial
```

**影響**：
- ⚠️ 函數返回失敗，但由呼叫方決定處理方式
- 通常會升級為 ERROR

---

#### ⚠️ WARN: 清除 SOA 快取

**條件**：
- 手動執行 `check_soa.sh reset` 指令

**Log 位置**：
- `scripts/check_soa.sh:186, 189`

**實際訊息**：
```
stderr: [WARN] 清除所有 Zone 的 SOA 快取
stderr: [WARN] 清除 rpztw. 的 SOA 快取
```

**影響**：
- ⚠️ 僅為通知訊息
- 下次檢查時會重新初始化 SOA 快取

---

### 2️⃣ 步驟 2: 提取 DNS Express 資料 (`extract_rpz.sh`)

#### ❌ ERROR: dnsxdump 指令不存在

**條件**：
- dnsxdump 指令檔案不存在
- 或無執行權限

**Log 位置**：
- `scripts/extract_rpz.sh:33-34`
- `scripts/main.sh:143` (主流程)

**實際訊息**：
```
stderr: [ERROR] dnsxdump 指令不存在或無執行權限: /usr/local/bin/dnsxdump
/var/log/ltm: 2025-11-12 10:00:00 ERROR: dnsxdump command not found
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: RPZ extraction failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ 無法提取 DNS Express 資料

**排查方向**：
- 確認檔案存在：`ls -lh /usr/local/bin/dnsxdump`
- 檢查執行權限：應為 `-rwxr-xr-x`
- 確認在 F5 DNS 環境中執行

---

#### ❌ ERROR: dnsxdump 執行失敗

**條件**：
- dnsxdump 執行返回非零退出碼

**Log 位置**：
- `scripts/extract_rpz.sh:40-41`
- `scripts/main.sh:143` (主流程)

**實際訊息**：
```
stderr: [ERROR] 執行 dnsxdump 失敗
/var/log/ltm: 2025-11-12 10:00:00 ERROR: dnsxdump execution failed
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: RPZ extraction failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ 無法提取 DNS Express 資料

**排查方向**：
- 手動執行 dnsxdump 查看錯誤：`/usr/local/bin/dnsxdump`
- 檢查 DNS Express 記憶體狀態：`tmsh show ltm dns cache records rrset`
- 查看系統資源：`free -h`, `df -h`

---

#### ❌ ERROR: dnsxdump 輸出檔案為空

**條件**：
- dnsxdump 執行成功但輸出檔案大小為 0
- 或檔案不存在

**Log 位置**：
- `scripts/extract_rpz.sh:47-48`
- `scripts/main.sh:143` (主流程)

**實際訊息**：
```
stderr: [ERROR] dnsxdump 輸出檔案為空
/var/log/ltm: 2025-11-12 10:00:00 ERROR: dnsxdump output is empty
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: RPZ extraction failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ 無資料可供後續解析

**排查方向**：
- 檢查 DNS Express 是否有資料：`tmsh list ltm dns zone`
- 確認 Zone 是否已同步：`tmsh show ltm dns zone rpztw.`
- 查看磁碟空間：`df -h /var/tmp`

---

### 3️⃣ 步驟 3: 解析 RPZ 記錄 (`parse_rpz.sh`)

#### ❌ ERROR: RPZ 解析失敗

**條件**：
- `parse_rpz.sh` 腳本執行返回非零退出碼
- AWK 處理過程發生錯誤

**Log 位置**：
- `scripts/main.sh:151-152`

**實際訊息**：
```
stderr: [ERROR] RPZ 解析失敗
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: RPZ parsing failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ 無法產生 DataGroup 檔案

**排查方向**：
- 檢查 dnsxdump 輸出格式是否正確
- 查看 AWK 處理邏輯是否匹配資料格式
- 確認臨時目錄權限：`ls -ld /var/tmp/rpz_datagroups`

---

### 4️⃣ 步驟 4: 產生 DataGroup 檔案 (`generate_datagroup.sh`)

#### ⚠️ WARN: 找不到 RPZ 解析檔案

**條件**：
- 期望的解析檔案不存在（如 rpztw.parsed.txt）
- 但這是非致命錯誤，會跳過該檔案

**Log 位置**：
- `scripts/generate_datagroup.sh:62`

**實際訊息**：
```
stderr: [WARN] 找不到 RPZ 解析檔案
```

**影響**：
- ⚠️ 跳過該檔案的 DataGroup 產生
- ✅ 繼續處理其他檔案

**排查方向**：
- 確認 parse_rpz.sh 是否成功執行
- 檢查解析輸出目錄：`ls -lh /var/tmp/rpz_datagroups/parsed/`

---

#### ❌ ERROR: DataGroup 產生失敗

**條件**：
- `generate_datagroup.sh` 腳本執行返回非零退出碼

**Log 位置**：
- `scripts/main.sh:160-161`

**實際訊息**：
```
stderr: [ERROR] DataGroup 產生失敗
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: DataGroup generation failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ 無法更新 F5 DataGroup

**排查方向**：
- 檢查解析檔案是否存在
- 確認輸出目錄權限
- 查看磁碟空間

---

### 5️⃣ 步驟 5: 更新 F5 DataGroup (`update_datagroup.sh`)

#### ❌ ERROR: 來源檔案不存在

**條件**：
- 要更新的 DataGroup 檔案不存在（如 rpz.txt）

**Log 位置**：
- `scripts/update_datagroup.sh:32-33`
- `scripts/main.sh:170` (主流程)

**實際訊息**：
```
stderr: [ERROR] 來源檔案不存在: /var/tmp/rpz_datagroups/final/rpz.txt
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: source file not found: /var/tmp/rpz_datagroups/final/rpz.txt
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: F5 update failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ DataGroup 不會被更新

**排查方向**：
- 確認 generate_datagroup.sh 是否成功
- 檢查檔案路徑：`ls -lh /var/tmp/rpz_datagroups/final/`

---

#### ⚠️ WARN: 來源檔案為空

**條件**：
- DataGroup 檔案存在但大小為 0
- 表示該 Zone 沒有記錄

**Log 位置**：
- `scripts/update_datagroup.sh:39`

**實際訊息**：
```
stderr: [WARN] 來源檔案為空，跳過更新: /var/tmp/rpz_datagroups/final/rpzip.txt
```

**影響**：
- ⚠️ 跳過該 DataGroup 的更新
- ✅ 繼續處理其他 DataGroup

---

#### ❌ ERROR: DataGroup 更新失敗

**條件**：
- tmsh 指令執行失敗
- 權限不足或 DataGroup 不存在

**Log 位置**：
- `scripts/update_datagroup.sh:50-51`
- `scripts/main.sh:170` (主流程)

**實際訊息**：
```
stderr: [ERROR] DataGroup rpztw_34_102_218_71 更新失敗
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: failed to update DataGroup rpztw_34_102_218_71
/var/log/ltm: 2025-11-12 10:00:00 dns.ryantseng.work ERROR: F5 update failed
```

**影響**：
- ❌ 主流程中斷，腳本 `exit 1`
- ❌ 部分或全部 DataGroup 未更新

**排查方向**：
- 檢查 DataGroup 是否存在：`tmsh list ltm data-group external rpztw_*`
- 確認權限：以 admin 身份執行
- 查看 tmsh 錯誤訊息

---

#### ⚠️ WARN: 找不到 RPZ DataGroup 檔案

**條件**：
- 在批次更新時找不到期望的檔案

**Log 位置**：
- `scripts/update_datagroup.sh:75`

**實際訊息**：
```
stderr: [WARN] 找不到 RPZ DataGroup 檔案: /var/tmp/rpz_datagroups/final/rpz.txt
```

**影響**：
- ⚠️ 跳過該檔案
- ✅ 繼續處理其他檔案

---

### 6️⃣ 主流程其他錯誤 (`main.sh`)

#### ⚠️ WARN: 強制執行模式

**條件**：
- 設定環境變數 `FORCE_RUN=true`
- 跳過 SOA Serial 檢查

**Log 位置**：
- `scripts/main.sh:113`

**實際訊息**：
```
stderr: [WARN] 強制執行模式，跳過 SOA 檢查
```

**影響**：
- ⚠️ 即使 SOA 未變更也會執行完整流程
- ✅ 用於手動強制更新

---

#### ⚠️ WARN: tmsh 指令不存在

**條件**：
- 不在 F5 環境中執行
- tmsh 指令無法找到

**Log 位置**：
- `scripts/main.sh:63`

**實際訊息**：
```
stderr: [WARN] tmsh 指令不存在，可能不在 F5 環境中
```

**影響**：
- ⚠️ 僅為提醒
- ✅ 不影響前置處理階段

---

#### ⚠️ WARN: dnsxdump 指令不存在

**條件**：
- 不在 F5 DNS 環境中執行
- dnsxdump 指令無法找到

**Log 位置**：
- `scripts/main.sh:67`

**實際訊息**：
```
stderr: [WARN] dnsxdump 指令不存在，可能不在 F5 DNS 環境中
```

**影響**：
- ⚠️ 僅為提醒
- ✅ 不影響前置處理階段

---

#### ❌ ERROR: 執行過程發生錯誤 (Trap)

**條件**：
- 任何未捕獲的錯誤觸發 ERR trap

**Log 位置**：
- `scripts/main.sh:251`

**實際訊息**：
```
stderr: [ERROR] 執行過程發生錯誤，退出碼: 1
```

**影響**：
- ❌ 腳本異常終止

---

## 監控建議

### 1. 關鍵錯誤監控

建議在監控系統中設定告警，監控以下錯誤訊息：

```bash
# 搜尋 /var/log/ltm 中的所有 ERROR 訊息
grep "ERROR:" /var/log/ltm | grep "RPZ\|DataGroup\|dnsxdump"
```

**告警級別**：
- 🔴 **Critical**：連續 3 次 ERROR（可能系統故障）
- 🟡 **Warning**：單次 ERROR（可能暫時性問題）

### 2. 正常運作確認

**無更新情況**（正常）：
```
2025-11-12 10:00:00 dns.ryantseng.work INFO: RPZ SOA not changed, skip update
```

**有更新情況**（正常）：
```
2025-11-12 10:05:00 dns.ryantseng.work INFO: RPZ SOA changed, start processing
2025-11-12 10:05:15 dns.ryantseng.work INFO: RPZ processing completed in 15s
```

### 3. iCall 執行狀態檢查

```bash
# 檢查執行次數和狀態
tmsh show sys icall handler periodic rpz_processor_handler

# 檢查最近的執行 log
tail -100 /var/log/ltm | grep -E "(RPZ|DataGroup)"

# 檢查是否有 scriptd 錯誤
tail -100 /var/log/ltm | grep "err.*scriptd"
```

### 4. DataGroup 狀態檢查

```bash
# 檢查 DataGroup 記錄數
tmsh list ltm data-group external rpztw_* | grep "records"

# 檢查最後更新時間
ls -lh /var/tmp/rpz_datagroups/final/
```

---

## 總結

### ERROR 級別（會中斷執行）

| 錯誤訊息 | 位置 | 觸發條件 |
|---------|------|---------|
| `ERROR: RPZ SOA check failed` | main.sh:129 | SOA 檢查異常 |
| `ERROR: dnsxdump command not found` | extract_rpz.sh:34 | dnsxdump 不存在 |
| `ERROR: dnsxdump execution failed` | extract_rpz.sh:41 | dnsxdump 執行失敗 |
| `ERROR: dnsxdump output is empty` | extract_rpz.sh:48 | dnsxdump 輸出為空 |
| `ERROR: RPZ extraction failed` | main.sh:143 | 資料提取失敗 |
| `ERROR: RPZ parsing failed` | main.sh:152 | 資料解析失敗 |
| `ERROR: DataGroup generation failed` | main.sh:161 | DataGroup 產生失敗 |
| `ERROR: source file not found` | update_datagroup.sh:33 | 來源檔案不存在 |
| `ERROR: failed to update DataGroup` | update_datagroup.sh:51 | DataGroup 更新失敗 |
| `ERROR: F5 update failed` | main.sh:170 | F5 更新失敗 |

**共計**：10 種 ERROR 訊息

### WARN 級別（不影響執行）

| 警告訊息 | 位置 | 說明 |
|---------|------|------|
| 強制執行模式 | main.sh:113 | FORCE_RUN=true |
| tmsh 指令不存在 | main.sh:63 | 非 F5 環境 |
| dnsxdump 指令不存在 | main.sh:67 | 非 F5 DNS 環境 |
| 清除 SOA 快取 | check_soa.sh:186,189 | 手動 reset |
| 找不到解析檔案 | generate_datagroup.sh:62 | 檔案不存在 |
| 來源檔案為空 | update_datagroup.sh:39 | 空檔案跳過 |
| 找不到 DataGroup 檔案 | update_datagroup.sh:75 | 批次更新跳過 |

**共計**：7 種 WARN 訊息

---

**文件建立**：2025-11-12
**作者**：Claude Code with Ryan
**版本**：1.0
**最後更新**：2025-11-12
