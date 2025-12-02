# RPZ Local Processor - 部署指南

## 📦 部署前準備

### 環境需求
- ✅ F5 BIG-IP DNS 設備
- ✅ DNS Express 已啟用並運行
- ✅ Root 或 admin 權限
- ✅ Bash 環境 (TMOS 內建)

### 檢查清單
```bash
# 1. 檢查 dnsxdump 指令
/usr/local/bin/dnsxdump | head -10

# 2. 檢查 tmsh 指令
tmsh list ltm dns zone

# 3. 檢查 DataGroup 是否存在
tmsh list ltm data-group external rpz
tmsh list ltm data-group external phishtw
tmsh list ltm data-group external rpzip

# 4. 如果不存在，建立 DataGroup
tmsh create ltm data-group external rpz type string
tmsh create ltm data-group external phishtw type string
tmsh create ltm data-group external rpzip type ip
```

---

## 🚀 快速部署

### 步驟 1: 上傳專案到 F5

```bash
# 從本地上傳到 F5 (使用 scp)
cd /Users/ryan/project/
tar czf RPZ_Local_Processor.tar.gz RPZ_Local_Processor/
scp RPZ_Local_Processor.tar.gz admin@<F5_IP>:/var/tmp/

# 或使用你的偏好方法上傳
```

### 步驟 2: 在 F5 上解壓並安裝

```bash
# SSH 登入 F5
ssh admin@<F5_IP>

# 解壓專案
cd /var/tmp
tar xzf RPZ_Local_Processor.tar.gz
cd RPZ_Local_Processor

# 執行安裝腳本
bash install.sh
```

**安裝腳本會自動**:
- ✅ 檢查系統環境
- ✅ 建立輸出目錄 `/var/tmp/rpz_datagroups/`
- ✅ 設定腳本執行權限
- ✅ 檢查配置檔案

### 步驟 3: 配置 Zone 清單

```bash
# 編輯 RPZ Zone 清單
vi config/rpz_zones.conf
```

**範例內容**:
```
rpztw.
phishtw.
```

### 步驟 4: 配置 Landing IP 映射 (可選)

```bash
# 如果需要按 Landing IP 分類 FQDN
vi config/datagroup_mapping.conf
```

**範例內容**:
```
34.102.218.71=dg_rpz_gcp
182.173.0.181=dg_rpz_local
```

### 步驟 5: 測試執行

```bash
# 手動執行一次 (詳細模式)
bash scripts/main.sh --verbose --no-cleanup

# 檢查輸出
ls -lh /var/tmp/rpz_datagroups/

# 檢查日誌
tail -f /var/log/ltm
```

### 步驟 6: 設定 iCall 定期執行（推薦）

```bash
# 建立 iCall script
tmsh create sys icall script rpz_processor_script definition \{
    exec bash /var/tmp/RPZ_Local_Processor/scripts/main.sh
\}

# 建立 iCall handler (每 5 分鐘執行)
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 300 \
    script rpz_processor_script

# 儲存配置
tmsh save sys config

# 檢查狀態
tmsh show sys icall handler periodic rpz_processor_handler
```

或使用快速設定腳本：
```bash
bash /var/tmp/RPZ_Local_Processor/config/icall_setup.sh
```

### 步驟 7: 部署 iRule

```bash
# 建立 iRule (如果還沒有)
tmsh create ltm rule rpz_dns_filter

# 編輯 iRule 內容
tmsh edit ltm rule rpz_dns_filter

# 貼上 irules/dns_rpz_irule.tcl 的內容
# 儲存並退出

# 或使用指令直接載入
tmsh load sys config file /var/tmp/RPZ_Local_Processor/irules/rpzdg_local_v1.tcl

# 將 iRule 套用到 DNS Virtual Server
tmsh modify ltm virtual <YOUR_DNS_VS> rules { rpz_dns_filter }

# 儲存配置
tmsh save sys config
```

---

## 🔍 驗證部署

### 檢查 Cron 執行

```bash
# 查看 cron 日誌
tail -f /shared/log/rpz_processor.log

# 檢查最近執行記錄
grep "RPZ processing" /var/log/ltm | tail -10
```

### 檢查 DataGroup 內容

```bash
# 查看 DataGroup 記錄數
tmsh list ltm data-group external rpz | grep records

# 查看實際內容 (前 10 筆)
head -10 /var/tmp/rpz_datagroups/parsed/rpz_*.txt
```

### 測試 DNS 查詢

```bash
# 從 F5 本機測試
dig @localhost <malicious_domain> A

# 應該返回 RPZ 定義的 Landing IP
```

---

## 📊 監控與維護

### 日常檢查

```bash
# 1. 檢查 SOA Serial
bash /var/tmp/RPZ_Local_Processor/scripts/check_soa.sh get rpztw.

# 2. 檢查處理日誌
tail -50 /var/log/ltm | grep RPZ

# 3. 檢查磁碟空間
du -sh /var/tmp/rpz_datagroups/
```

### 除錯模式

```bash
# 強制執行 + 保留臨時檔案 + 詳細日誌
bash scripts/main.sh --force --no-cleanup --verbose

# 檢查中間檔案
ls -lh /var/tmp/rpz_datagroups/raw/
ls -lh /var/tmp/rpz_datagroups/parsed/
```

### 清理舊檔案

```bash
# 手動清理超過 7 天的檔案
find /var/tmp/rpz_datagroups/ -type f -mtime +7 -delete

# 或使用腳本內建的清理功能 (預設啟用)
```

---

## 🔧 常見問題

### Q1: SOA 檢查一直顯示「未變更」

**原因**: DNS Express Zone 沒有更新

**解決方案**:
```bash
# 檢查 DNS Express 狀態
tmsh show ltm dns zone rpztw.

# 手動觸發 Zone Transfer
tmsh modify ltm dns zone rpztw. transfer-source <master_dns_ip>

# 強制執行處理 (跳過 SOA 檢查)
bash scripts/main.sh --force
```

### Q2: dnsxdump 指令執行失敗

**原因**: DNS Express 未啟用或無資料

**解決方案**:
```bash
# 檢查 DNS Express 設定
tmsh list ltm dns zone

# 確認 Zone 有資料
/usr/local/bin/dnsxdump | grep rpztw
```

### Q3: DataGroup 更新失敗

**原因**: DataGroup 不存在或路徑錯誤

**解決方案**:
```bash
# 建立 DataGroup
tmsh create ltm data-group external rpz type string

# 檢查檔案路徑
ls -lh /var/tmp/rpz_datagroups/parsed/

# 手動更新測試
tmsh modify ltm data-group external rpz source-path file:/var/tmp/rpz_datagroups/parsed/rpz_<timestamp>.txt
```

### Q4: iRule 沒有作用

**原因**: iRule 未套用到 Virtual Server 或邏輯錯誤

**解決方案**:
```bash
# 檢查 iRule 是否套用
tmsh list ltm virtual <VS_NAME> rules

# 檢查 iRule 語法
tmsh list ltm rule rpz_dns_filter

# 啟用 iRule 日誌除錯
# 在 iRule 中取消註解 log 行
```

---

## 📈 效能優化

### 減少執行頻率

如果 RPZ 更新不頻繁，可以降低 Cron 執行頻率：

```bash
# 使用 iCall 修改間隔為 30 分鐘 (1800 秒)
tmsh modify sys icall handler periodic rpz_processor_handler interval 1800
tmsh save sys config
```

### SOA 檢查機制

內建的 SOA 檢查會在 Zone 未更新時自動跳過處理，無需額外配置。

---

## 🔄 從舊版本遷移

如果你正在使用原始的 `convert_rpz.sh`:

### 步驟 1: 備份舊設定

```bash
cp /config/snmp/convert_rpz.sh /config/snmp/convert_rpz.sh.backup
cp /config/snmp/.rpz_soa_serial.last /config/snmp/.rpz_soa_serial.last.backup
```

### 步驟 2: 停用舊 Cron

```bash
crontab -e
# 註解掉舊的 cron 設定
# * * * * * sh /config/snmp/convert_rpz.sh >> /shared/log/convert.log 2>&1
```

### 步驟 3: 部署新版本

按照上方的快速部署步驟操作。

### 步驟 4: 驗證並切換

```bash
# 手動執行新版本
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh

# 比對輸出結果
diff /var/tmp/output_*.rpz /var/tmp/rpz_datagroups/parsed/rpz_*.txt

# 確認無誤後啟用新 Cron
```

---

## 📞 支援資訊

- **專案位置**: `/var/tmp/RPZ_Local_Processor/`
- **日誌位置**: `/var/log/ltm`
- **輸出位置**: `/var/tmp/rpz_datagroups/`
- **配置檔案**: `config/rpz_zones.conf`
- **執行方式**: iCall (每 5 分鐘)

---

**部署完成後建議**:
1. ✅ 監控第一次執行的完整日誌
2. ✅ 確認 DataGroup 已正確更新
3. ✅ 測試 DNS 查詢回應正確
4. ✅ 觀察系統資源使用情況
5. ✅ 設定日誌輪轉避免磁碟滿

**部署完成時間**: 預計 15-30 分鐘
**維護者**: Ryan Tseng
**最後更新**: 2025-09-30