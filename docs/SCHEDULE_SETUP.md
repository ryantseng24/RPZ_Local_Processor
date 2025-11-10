# RPZ 定期更新設定指南

本文件說明如何在 F5 上設定定期自動更新 RPZ DataGroups。

---

## 方案一：使用 iCall（推薦）

### 優點
✅ F5 原生支援，整合度高
✅ 配置持久化（自動儲存到配置檔）
✅ 可透過 tmsh 管理
✅ 支援複雜的觸發條件

### 設定步驟

#### 1. 建立 iCall Script

```bash
tmsh create sys icall script rpz_processor_script definition \{
    exec bash /var/tmp/RPZ_Local_Processor/scripts/main.sh
\}
```

#### 2. 建立 iCall Periodic Handler

**每 5 分鐘執行一次**：
```bash
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 300 \
    script rpz_processor_script
```

**每 10 分鐘執行一次**：
```bash
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 600 \
    script rpz_processor_script
```

**每小時執行一次**：
```bash
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 3600 \
    script rpz_processor_script
```

#### 3. 儲存配置

```bash
tmsh save sys config
```

---

## 管理命令

### 查看配置

```bash
# 查看 Handler 狀態
tmsh list sys icall handler periodic rpz_processor_handler

# 查看 Script 配置
tmsh list sys icall script rpz_processor_script

# 查看執行統計
tmsh show sys icall handler periodic rpz_processor_handler
```

### 啟用/停用

```bash
# 停用
tmsh modify sys icall handler periodic rpz_processor_handler status inactive

# 啟用
tmsh modify sys icall handler periodic rpz_processor_handler status active
```

### 手動觸發執行

```bash
# 直接執行腳本（不等待排程）
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force
```

### 修改執行頻率

```bash
# 改為每 15 分鐘
tmsh modify sys icall handler periodic rpz_processor_handler interval 900

# 儲存配置
tmsh save sys config
```

### 移除設定

```bash
# 刪除 Handler
tmsh delete sys icall handler periodic rpz_processor_handler

# 刪除 Script
tmsh delete sys icall script rpz_processor_script

# 儲存配置
tmsh save sys config
```

---

## 方案二：使用 cron

### 優點
✅ 傳統方式，容易理解
✅ 支援複雜的時間表達式

### 缺點
⚠️ F5 某些版本可能不支援 cron
⚠️ 配置不會自動備份

### 設定步驟

#### 1. 編輯 crontab

```bash
# 切換到 root
su -

# 編輯 crontab
crontab -e
```

#### 2. 新增排程

```bash
# 每 5 分鐘執行
*/5 * * * * /var/tmp/RPZ_Local_Processor/scripts/main.sh >> /var/log/rpz_processor.log 2>&1

# 每 10 分鐘執行
*/10 * * * * /var/tmp/RPZ_Local_Processor/scripts/main.sh >> /var/log/rpz_processor.log 2>&1

# 每小時執行
0 * * * * /var/tmp/RPZ_Local_Processor/scripts/main.sh >> /var/log/rpz_processor.log 2>&1

# 每天凌晨 2 點執行
0 2 * * * /var/tmp/RPZ_Local_Processor/scripts/main.sh >> /var/log/rpz_processor.log 2>&1
```

#### 3. 檢查 cron 服務

```bash
# 檢查 cron 是否運行
ps aux | grep cron

# 如果沒有運行，啟動它（某些 F5 版本可能不支援）
service crond start
```

---

## 監控與除錯

### 查看執行日誌

```bash
# 查看最新的執行記錄
tail -100 /var/log/ltm | grep RPZ

# 即時監控
tail -f /var/log/ltm | grep RPZ

# 查看詳細日誌（如果使用 cron）
tail -f /var/log/rpz_processor.log
```

### 檢查 SOA 快取

```bash
# 查看當前快取的 SOA Serial
cat /config/snmp/.rpztw._soa_serial.last
cat /config/snmp/.phishtw._soa_serial.last

# 重置快取（強制下次更新）
bash /var/tmp/RPZ_Local_Processor/scripts/check_soa.sh reset
```

### 手動測試執行

```bash
# 測試執行（正常模式，會檢查 SOA）
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh

# 強制執行（跳過 SOA 檢查）
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force

# 詳細模式
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force --verbose
```

---

## 推薦設定

### 生產環境

**執行頻率**：每 5-10 分鐘
```bash
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 300 \
    script rpz_processor_script
```

**說明**：
- SOA 檢查機制會自動跳過未變更的執行
- 5 分鐘間隔可以快速反應 DNS 更新
- 實際處理只在 SOA 變更時發生

### 測試環境

**執行頻率**：每 30 分鐘
```bash
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 1800 \
    script rpz_processor_script
```

---

## 故障排查

### iCall 沒有執行

1. **檢查 Handler 狀態**：
   ```bash
   tmsh list sys icall handler periodic rpz_processor_handler
   # 確認 status 是 active
   ```

2. **檢查腳本路徑**：
   ```bash
   tmsh list sys icall script rpz_processor_script
   # 確認路徑正確
   ```

3. **檢查執行統計**：
   ```bash
   tmsh show sys icall handler periodic rpz_processor_handler
   # 查看 last-run-time 和 failures
   ```

4. **手動執行測試**：
   ```bash
   bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force --verbose
   ```

### SOA 沒有變更但想強制更新

```bash
# 重置 SOA 快取
bash /var/tmp/RPZ_Local_Processor/scripts/check_soa.sh reset

# 或直接強制執行
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force
```

### DataGroup 更新失敗

1. **檢查檔案權限**：
   ```bash
   ls -la /var/tmp/rpz_datagroups/final/
   ```

2. **檢查 DataGroup 是否存在**：
   ```bash
   tmsh list ltm data-group external rpztw phishtw
   ```

3. **查看錯誤訊息**：
   ```bash
   tail -100 /var/log/ltm | grep ERROR
   ```

---

## 自動化部署腳本

使用 `config/icall_setup.sh` 快速設定：

```bash
# SSH 到 F5
ssh admin@<F5_IP>

# 切換到 root
su -

# 執行設定腳本
bash /var/tmp/RPZ_Local_Processor/config/icall_setup.sh

# 或指定不同的執行間隔（秒）
INTERVAL=600 bash /var/tmp/RPZ_Local_Processor/config/icall_setup.sh
```

---

## 最佳實踐

1. **使用 iCall 而非 cron**：更穩定、更易管理
2. **保留 SOA 檢查**：避免不必要的處理
3. **定期檢查日誌**：確保執行正常
4. **備份配置**：定期執行 `tmsh save sys config`
5. **監控 DataGroup 大小**：注意記憶體使用

---

**設定完成後**，系統會自動檢查 SOA Serial 並在資料變更時更新 DataGroups！
