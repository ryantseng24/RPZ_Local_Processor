# 部署成功記錄

## 📅 部署資訊

- **部署日期**: 2025-09-30
- **F5 設備**: 10.8.34.234 (dns LAB)
- **部署路徑**: `/var/tmp/RPZ_Local_Processor`
- **狀態**: ✅ 完全成功

---

## 🎯 專案目標

將 F5 DNS Express 中的 RPZ 資料轉換為 F5 External DataGroup 格式，供 iRule 使用。

### 核心理念
- **Pure Shell Script**: 無需 Python 或外部依賴
- **本地執行**: 直接在 F5 設備上運行，無需中轉伺服器
- **簡化架構**: 移除 Landing IP 分類，iRule 自行處理業務邏輯

---

## 🏗️ 系統架構

```
F5 BIG-IP (10.8.34.6)
├── DNS Express (RPZ Zones)
│   ├── rpztw. (29,568 筆)
│   └── phishtw. (445 筆)
│
├── Shell Scripts
│   ├── main.sh (主流程編排)
│   ├── check_soa.sh (SOA Serial 檢查)
│   ├── extract_rpz.sh (dnsxdump 執行)
│   ├── parse_rpz.sh (AWK 解析)
│   ├── generate_datagroup.sh (檔案整理)
│   └── update_datagroup.sh (tmsh 更新)
│
└── DataGroups (最終輸出)
    ├── /var/tmp/rpz_datagroups/final/rpz.txt
    └── /var/tmp/rpz_datagroups/final/phishtw.txt
```

---

## 📝 執行流程 (5 步驟)

### Step 1: SOA Serial 檢查
```bash
# 目的: 避免不必要的處理
# 邏輯: 比對 DNS Express 的 SOA Serial 與快取值
# 快取位置: /var/tmp/rpz_datagroups/.soa_cache/
```

### Step 2: 提取 DNS Express 資料
```bash
# 執行 dnsxdump 匯出完整資料
/usr/local/bin/dnsxdump > /var/tmp/rpz_datagroups/raw/dnsxdump_*.out

# 輸出: 約 185,376 行 (包含所有 DNS Express zones)
```

### Step 3: 解析 RPZ 記錄
```bash
# 使用 AWK 解析三種記錄類型:
# 1. rpztw.   -> rpz.txt (FQDN := IP 格式)
# 2. phishtw. -> phishtw.txt (FQDN := IP 格式)
# 3. rpz-ip   -> (已暫時移除，目前無此類記錄)
```

**AWK 解析邏輯** (保留自原始程式碼):
```awk
# 只處理 IN A 記錄
if ($3 == "IN" && $4 == "A" && substr($1,1,1) != "*") {
    # rpztw zone
    if ($1 ~ /\.rpztw\.?$/) {
        sub(/\.rpztw\.$/, "", $1)
        rpz[$1] = $5  # domain => landing_ip
    }
    # phishtw zone
    else if ($1 ~ /\.phishtw\.?$/) {
        sub(/\.phishtw\.$/, "", $1)
        phishtw[$1] = $5
    }
}

END {
    # 輸出 key := value 格式
    for (d in rpz) print "\"" d "\" := \"" rpz[d] "\"," > rpz_file
    for (d in phishtw) print "\"" d "\" := \"" phishtw[d] "\"," > phishtw_file
}
```

### Step 4: 產生 DataGroup 檔案
```bash
# 將時間戳檔案複製為固定檔名 (供 F5 引用)
/var/tmp/rpz_datagroups/parsed/rpz_*.txt -> /var/tmp/rpz_datagroups/final/rpz.txt
/var/tmp/rpz_datagroups/parsed/phishtw_*.txt -> /var/tmp/rpz_datagroups/final/phishtw.txt
```

### Step 5: 更新 F5 DataGroups
```bash
# 使用 tmsh 更新 External DataGroups
tmsh modify ltm data-group external rpz source-path file:/var/tmp/rpz_datagroups/final/rpz.txt
tmsh modify ltm data-group external phishtw source-path file:/var/tmp/rpz_datagroups/final/phishtw.txt
```

---

## 📊 輸出格式

### rpz.txt (FQDN DataGroup)
```
"malicious.com" := "34.102.218.71",
"phishing.net" := "182.173.0.181",
"evil.org" := "210.64.24.25",
```

### iRule 使用方式（BIND DNS RPZ 邏輯）
```tcl
when DNS_REQUEST {
    set query_name [string tolower [DNS::question name]]
    set qlen [string length $query_name]

    if { [class match -- $query_name ends_with rpz] } {
        set rpz_key [class match -name $query_name ends_with rpz]
        set landing_ip [class match -value $query_name ends_with rpz]

        # BIND RPZ 匹配邏輯
        if { [string index $rpz_key 0] eq "." } {
            # 萬用字元：.example.com 匹配 example.com 及所有子網域
            set rpz_matched 1
        } else {
            # 精確匹配：example.com 只匹配 example.com (長度檢查)
            set keylen [string length $rpz_key]
            if { $qlen == $keylen } {
                set rpz_matched 1
            }
        }

        if { $rpz_matched } {
            # 使用 Landing IP 回應
            DNS::answer insert "$query_name. 30 IN A $landing_ip"
        }
    }
}
```

---

## 🚀 執行方式

### 手動執行
```bash
# 完整執行 (含 SOA 檢查)
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh

# 強制執行 (跳過 SOA 檢查)
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force

# 詳細輸出
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --verbose

# 保留臨時檔案 (除錯用)
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --no-cleanup
```

### 定期執行 (iCall - 已採用)
```bash
# 使用 F5 iCall 每 5 分鐘執行
# 配置詳見 docs/SCHEDULE_SETUP.md

tmsh create sys icall script rpz_processor_script definition \{
    exec bash /var/tmp/RPZ_Local_Processor/scripts/main.sh
\}

tmsh create sys icall handler periodic rpz_processor_handler \
    interval 300 \
    script rpz_processor_script
```

---

## 🐛 除錯過程記錄

### 問題 1: `((count++))` 導致 `set -e` 中斷
**原因**: 當 count=0 時，`((count++))` 先評估舊值 0 (返回狀態 1)，觸發 `set -e` 中斷
**解決**: 改用 `count=$((count + 1))` 語法

**影響檔案**:
- extract_rpz.sh (line 108)
- generate_datagroup.sh (line 60, 68, 76)
- update_datagroup.sh (line 70, 83)

### 問題 2: `hostname` 命令在 TMOS 環境返回錯誤
**原因**: F5 TMOS shell 的 hostname 命令返回提示訊息且退出狀態為 1
**解決**: 移除所有 `$(hostname)` 調用，直接使用時間戳記錄日誌

**影響檔案**:
- extract_rpz.sh (line 34, 41, 48, 54)

### 問題 3: `echo | xargs` 觸發 TMOS 警告
**原因**: TMOS 環境下的 echo 命令會觸發警告訊息
**解決**: 改用純 bash 字串處理 `${var#...}` 和 `${var%...}`

**影響檔案**:
- extract_rpz.sh (line 110-112) - 最終簡化後移除

### 問題 4: 過度設計的 zone 提取邏輯
**原因**: 試圖在 Step 2 按 zone 分別提取，增加複雜度且容易出錯
**解決**: 簡化為只執行 dnsxdump，讓 AWK 在 Step 3 直接處理完整檔案

**簡化前**: extract_rpz.sh 122 行，包含 `extract_zone_data()` 函數
**簡化後**: extract_rpz.sh 82 行，只執行 dnsxdump

---

## ⚠️ 重要注意事項

### 1. TMOS Shell 環境特性
- **避免使用**: `hostname`, `echo | xargs`, 複雜的管道操作
- **推薦使用**: 純 bash 語法，直接變數操作
- **錯誤處理**: 所有外部命令都加上 `|| true` 或錯誤檢查

### 2. `set -euo pipefail` 的影響
- **`((expr))`**: 結果為 0 時退出狀態為 1，會觸發 `set -e`
- **`grep`**: 找不到匹配時返回 1，需加 `|| true`
- **`wc -l <`**: 檔案不存在時會失敗，需用 `|| echo "0"`

### 3. DataGroup 格式要求
- **字串型**: 必須用雙引號包裹，格式 `"key" := "value",`
- **結尾逗號**: 每一行都需要結尾逗號
- **萬用字元**: 跳過 `*` 開頭的記錄 (AWK: `substr($1,1,1) != "*"`)

### 4. 檔案路徑結構
```
/var/tmp/rpz_datagroups/
├── .soa_cache/              # SOA Serial 快取
│   ├── rpztw.soa
│   └── phishtw.soa
├── raw/                     # dnsxdump 原始輸出
│   └── dnsxdump_*.out
├── parsed/                  # AWK 解析後 (時間戳檔名)
│   ├── rpz_*.txt
│   ├── phishtw_*.txt
│   └── ip_*.txt
└── final/                   # 最終輸出 (固定檔名)
    ├── rpz.txt
    └── phishtw.txt
```

---

## 📈 效能數據

```
資料規模:
- DNS Express 總記錄: 185,376 行
- rpztw 有效記錄: 58,602 筆
  ├── 萬用字元記錄: 29,035 筆 (.domain 格式)
  └── 精確記錄: 29,567 筆 (domain 格式)
- phishtw 有效記錄: 819 筆
  ├── 萬用字元記錄: 374 筆
  └── 精確記錄: 445 筆

執行時間:
- 完整流程: ~1 秒
- dnsxdump: ~0.5 秒
- AWK 解析: ~0.3 秒
- tmsh 更新: ~0.2 秒
```

---

## 🔍 驗證方式

### 1. 檢查 DataGroup 格式
```bash
# 查看前 10 筆
head -10 /var/tmp/rpz_datagroups/final/rpz.txt

# 預期格式:
# "tw23.joom.ac" := "34.102.218.71",
# "tw27.joom.ac" := "34.102.218.71",
```

### 2. 檢查 F5 DataGroup 狀態
```bash
# 查看 DataGroup 配置
tmsh list ltm data-group external rpz
tmsh list ltm data-group external phishtw

# 查詢特定 domain
tmsh list ltm data-group external rpz | grep "tw23.joom.ac"
```

### 3. 測試 iRule 查詢
```bash
# 在 F5 上執行 TCL 測試
tmsh
(tmos)# run /ltm data-group internal __appsvcs_update
```

### 4. 檢查日誌
```bash
# 查看執行日誌
tail -100 /var/log/ltm | grep rpz

# 查看完整日誌
cat /var/log/rpz_processor.log
```

---

## 🔄 與方法 A (Python 版本) 的比較

| 項目 | 方法 A (RPZ_to_DataGroup) | 方法 B (本專案) |
|------|---------------------------|-----------------|
| **技術** | Python 3 | Pure Shell Script |
| **架構** | 中轉伺服器 + HTTP Server | F5 本地執行 |
| **資料來源** | AXFR from DNS Server | DNS Express |
| **部署** | 外部伺服器 (10.8.38.223) | F5 內部 (10.8.34.6) |
| **依賴** | Python modules, requests | Bash built-in only |
| **複雜度** | 高 (多台同步) | 低 (單機運行) |
| **維護** | 需管理中轉伺服器 | 僅管理 F5 設備 |

---

## 📚 相關文件

- `README.md` - 專案概述與快速開始
- `SIMPLIFICATION_SUMMARY.md` - 架構簡化說明
- `REFACTOR_SUMMARY.md` - 程式碼重構記錄
- `DEPLOYMENT_GUIDE.md` - 完整部署指南

---

## 🎓 經驗教訓

### 1. Keep It Simple, Stupid (KISS)
最初設計過度複雜 (Landing IP 分類、zone 分別提取)，簡化後反而更穩定。

### 2. 尊重原始程式碼
用戶提供的 80 行簡單腳本是可運作的，重構時應保留核心邏輯，只做模組化。

### 3. 環境特性很重要
F5 TMOS shell 與標準 Linux shell 有差異，需實際測試而非假設。

### 4. 錯誤處理要充分
`set -euo pipefail` 雖然嚴格，但需要仔細處理每個可能失敗的命令。

---

## ✅ 部署檢查清單

- [x] SSH 訪問 F5 設備 (10.8.34.234)
- [x] 上傳所有 scripts 到 `/var/tmp/RPZ_Local_Processor/scripts/`
- [x] 配置檔案 `config/rpz_zones.conf` 正確
- [x] 執行權限 `chmod +x scripts/*.sh`
- [x] 手動測試 `main.sh --force --verbose`
- [x] 驗證 DataGroup 格式
- [x] 確認 F5 DataGroups 已更新
- [x] 設定定期執行 (iCall 已配置)
- [x] 監控日誌輸出

---

**專案狀態**: ✅ 生產就緒
**最後更新**: 2025-09-30 16:54 CST
**維護者**: Ryan Tseng