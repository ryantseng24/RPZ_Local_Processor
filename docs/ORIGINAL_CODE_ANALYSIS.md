# 原始程式碼分析

## 📋 程式功能總覽

### 核心功能
1. **SOA Serial 版本檢查** - 避免重複處理
2. **DNS Express 資料提取** - 使用 `dnsxdump`
3. **RPZ 記錄解析** - AWK 處理三種類型
4. **DataGroup 檔案產生** - 輸出 F5 格式
5. **F5 DataGroup 更新** - 使用 `tmsh modify`

---

## 🔍 詳細分析

### 1. SOA Serial 版本控制機制

```bash
# 取得當前 SOA
CURR_SOA=$(/usr/local/bin/dnsxdump | grep rpztw | grep SOA | awk '{print $7}')

# 讀取前次 SOA
PREV_SOA=$(cat "$SOA_FILE")

# 比對是否變更
if [[ "$CURR_SOA" -le "$PREV_SOA" ]]; then
    # SOA 未變更，跳過處理
    exit 0
fi
```

**用途**:
- ✅ 避免 Zone 未更新時的無效處理
- ✅ 節省 CPU 和 I/O 資源
- ✅ 減少不必要的 DataGroup 更新

**儲存位置**: `/config/snmp/.rpz_soa_serial.last`

---

### 2. DNS Express 資料提取

```bash
/usr/local/bin/dnsxdump > /var/tmp/dnsxdump_${TIMESTAMP}.out
```

**工具**: `dnsxdump` - F5 內建工具，用於導出 DNS Express 資料

**輸出格式**:
```
example.com.rpztw.       IN  A       34.102.218.71
malware.com.phishtw.     IN  A       182.173.0.170
32.192.168.1.2.rpz-ip.rpztw.  IN  CNAME   .
```

---

### 3. AWK 解析邏輯

#### 三種記錄類型處理

**類型 1: FQDN (rpztw zone)**
```awk
if ($1 ~ /\.rpztw\.?$/) {
    sub(/\.rpztw\.$/, "", $1)  # 移除後綴
    rpz[$1] = $5               # 儲存 domain => landing_ip
}
```
**範例輸入**: `malicious.com.rpztw. IN A 34.102.218.71`
**處理結果**: `rpz["malicious.com"] = "34.102.218.71"`

---

**類型 2: FQDN (phishtw zone)**
```awk
else if ($1 ~ /\.phishtw\.?$/) {
    sub(/\.phishtw\.$/, "", $1)
    phishtw[$1] = $5
}
```
**用途**: 獨立的 phishing 網域清單

---

**類型 3: IP 網段 (rpz-ip)**
```awk
else if ($4 == "CNAME" && index($1, "rpz-ip.rpztw.") > 0) {
    sub(/\.rpz-ip\.rpztw\.$/, "", $1)
    split($1, ip_parts, ".")
    if (length(ip_parts) >= 5) {
        netmask = ip_parts[1]
        reversed_ip = ip_parts[5] "." ip_parts[4] "." ip_parts[3] "." ip_parts[2]
        iplist[reversed_ip "/" netmask] = 1
    }
}
```

**範例輸入**: `32.192.168.1.2.rpz-ip.rpztw. IN CNAME .`

**處理步驟**:
1. 移除 `.rpz-ip.rpztw.` 後綴 → `32.192.168.1.2`
2. 分割為陣列 → `[32, 192, 168, 1, 2]`
3. 提取 netmask (第一個) → `32`
4. 反轉 IP (2-5 元素) → `2.1.168.192`
5. 組合 → `2.1.168.192/32`

---

### 4. DataGroup 輸出格式

**FQDN DataGroup** (`rpz_file`):
```
"malicious.com" := "34.102.218.71",
"phishing.net" := "182.173.0.181",
```

**IP DataGroup** (`ip_file`):
```
network 1.2.3.0/24,
network 4.5.6.7/32,
```

---

### 5. F5 DataGroup 更新

```bash
tmsh modify ltm data-group external rpz source-path file:$RPZ_FILE
```

**說明**:
- 更新名為 `rpz` 的 external data-group
- 指向新產生的檔案路徑
- F5 會自動重新載入檔案內容

---

## 🎯 識別出的可改進點

### 1. 模組化不足
- ❌ 所有功能在單一檔案中
- ✅ 應拆分為獨立模組

### 2. 錯誤處理簡單
```bash
if ! /usr/local/bin/dnsxdump > ... ; then
    echo "... failed" >> "$LOG_FILE"
    exit 1
fi
```
- ❌ 僅記錄錯誤訊息
- ✅ 應加入更詳細的除錯資訊

### 3. 硬編碼路徑
```bash
LOG_FILE="/var/log/ltm"
SOA_FILE="/config/snmp/.rpz_soa_serial.last"
```
- ❌ 路徑寫死在程式碼中
- ✅ 應使用配置檔案或環境變數

### 4. 缺少日誌等級
```bash
echo "$TIMESTAMP $HOSTNAME ..." >> "$LOG_FILE"
```
- ❌ 所有訊息同等級
- ✅ 應區分 INFO / WARN / ERROR

### 5. 單一 Zone 處理
- ❌ 僅處理 `rpztw` 和 `phishtw`
- ✅ 應支援動態 Zone 清單

### 6. 臨時檔案未清理
```bash
rm -f /var/tmp/dnsxdump_${TIMESTAMP}.out
rm -f $RPZ_FILE
```
- ❌ 僅清理部分檔案
- ✅ 應清理所有臨時檔案

---

## 📊 效能分析

### 優點
1. ✅ **SOA 檢查機制** - 避免無效處理
2. ✅ **AWK 單次掃描** - 效能優異
3. ✅ **僅更新變更的 DataGroup**

### 潛在問題
1. ⚠️ **完整 dnsxdump** - 每次都導出完整資料
2. ⚠️ **臨時檔案 I/O** - 可考慮管道處理

---

## 🔄 重構策略

### 模組分割

| 功能 | 原始位置 | 重構目標 |
|------|---------|---------|
| SOA 檢查 | Line 14-34 | `scripts/check_soa.sh` |
| dnsxdump | Line 40-43 | `scripts/extract_rpz.sh` |
| AWK 解析 | Line 45-73 | `scripts/parse_rpz.sh` |
| DataGroup 更新 | Line 75-79 | `scripts/update_datagroup.sh` |
| 主流程 | 整個檔案 | `scripts/main.sh` |

### 配置外部化

| 硬編碼項目 | 配置檔案 |
|-----------|---------|
| rpztw, phishtw | `config/rpz_zones.conf` |
| 路徑 (/var/tmp) | `config/paths.conf` |
| Landing IP 映射 | `config/datagroup_mapping.conf` |

---

## 📝 下一步重構計畫

1. ✅ 建立 `check_soa.sh` - SOA 版本管理
2. ✅ 更新 `extract_rpz.sh` - 包裝 dnsxdump
3. ✅ 更新 `parse_rpz.sh` - 整合 AWK 邏輯
4. ✅ 建立 `update_datagroup.sh` - tmsh 操作
5. ✅ 更新 `main.sh` - 串接所有模組
6. ✅ 更新配置檔案 - 支援多 Zone

---

**分析完成時間**: 2025-09-30
**原始程式碼行數**: ~80 行
**預計重構後**: ~250 行 (分散在 5-6 個模組)