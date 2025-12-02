# 架構簡化總結

## 🎯 簡化動機

根據使用者需求，移除過度設計的 Landing IP 分類功能，回歸核心需求：
- ✅ RPZ 資料直接轉換為 key := value 格式
- ✅ iRule 自行處理 Landing IP 的邏輯判斷
- ✅ 減少配置複雜度

---

## 📊 變更對比

### 簡化前 (過度設計)

```
流程:
RPZ 資料 
  → 解析 (AWK)
  → 按 Landing IP 分類
  → 產生多個 DataGroup
    ├── dg_rpz_gcp.txt (34.102.218.71)
    ├── dg_rpz_local.txt (182.173.0.181)
    └── dg_rpz_twnic.txt (210.64.24.25)

配置檔:
- rpz_zones.conf
- datagroup_mapping.conf ← 不需要！

iRule: 需要預先知道要查詢哪個 DataGroup
```

### 簡化後 (精簡設計) ✅

```
流程:
RPZ 資料
  → 解析 (AWK)
  → 直接輸出 key := value 格式
  → 單一 DataGroup
    └── rpz.txt
        "malicious.com" := "34.102.218.71",
        "phishing.net" := "182.173.0.181",

配置檔:
- rpz_zones.conf ← 僅需這個！

iRule: 直接查詢取值
  set reply_ip [class match -value $fqdn ends_with rpz]
  # reply_ip 就是 Landing IP
```

---

## 🔧 程式碼變更

### 1. 移除配置檔

```bash
# 刪除
config/datagroup_mapping.conf
```

### 2. 簡化 parse_rpz.sh

**移除的函數**:
- `classify_by_landing_ip()` - 約 40 行

**保留的核心**:
- `parse_rpz_records()` - AWK 解析邏輯完全保留

**變更前** (195 行):
```bash
# 執行 AWK 解析
parse_rpz_records "$dnsxdump_file" ...

# 進階分類 (根據 Landing IP)
if [[ -f "${PROJECT_ROOT}/config/datagroup_mapping.conf" ]]; then
    classify_by_landing_ip "$rpz_output"  # ← 移除這段
else
    log_warn "未找到 Landing IP 映射配置，跳過分類"
fi
```

**變更後** (155 行):
```bash
# 執行 AWK 解析
parse_rpz_records "$dnsxdump_file" ...

# 直接輸出，不再分類
log_info "解析完成"
```

### 3. 重寫 generate_datagroup.sh

**變更前** (複雜):
- 讀取 mapping 配置
- 按 Landing IP 分類
- 產生多個 DataGroup

**變更後** (簡單):
```bash
prepare_final_datagroups() {
    # 直接複製解析結果到 final 目錄
    cp "$rpz_file" "${FINAL_OUTPUT_DIR}/rpz.txt"
    cp "$phishtw_file" "${FINAL_OUTPUT_DIR}/phishtw.txt"
    cp "$ip_file" "${FINAL_OUTPUT_DIR}/rpzip.txt"
}
```

### 4. 更新 update_datagroup.sh

**變更前**:
```bash
# 從 parsed/ 目錄讀取時間戳檔案
rpz_file=$(ls -t "${PARSED_DATA_DIR}"/rpz_*.txt | head -1)
```

**變更後**:
```bash
# 從 final/ 目錄讀取固定檔名
rpz_file="${FINAL_OUTPUT_DIR}/rpz.txt"
```

---

## 📁 目錄結構變更

### 簡化前

```
/var/tmp/rpz_datagroups/
├── raw/
│   └── dnsxdump_*.out
├── parsed/
│   ├── rpz_*.txt (原始解析)
│   ├── dg_rpz_gcp.fqdn (分類後)
│   ├── dg_rpz_local.fqdn
│   └── dg_rpz_twnic.fqdn
└── datagroups/ (最終輸出)
```

### 簡化後

```
/var/tmp/rpz_datagroups/
├── raw/
│   └── dnsxdump_*.out
├── parsed/
│   ├── rpz_<timestamp>.txt
│   ├── phishtw_<timestamp>.txt
│   └── ip_<timestamp>.txt
└── final/ (固定檔名)
    ├── rpz.txt       ← F5 引用這個
    ├── phishtw.txt
    └── rpzip.txt
```

---

## ✅ 檔案格式確認

### rpz.txt (FQDN DataGroup)

```
"malicious.com" := "34.102.218.71",
"phishing.net" := "182.173.0.181",
"evil.org" := "210.64.24.25",
```

**iRule 使用方式**:
```tcl
set fqdn_name [string tolower [DNS::question name]]
set found [class match -- $fqdn_name ends_with rpz]

if { $found } {
    # 直接取得 Landing IP
    set landing_ip [class match -value $fqdn_name ends_with rpz]
    
    # iRule 自行決定後續動作
    if { $landing_ip eq "34.102.218.71" } {
        # GCP Landing IP 的處理
    } elseif { $landing_ip eq "182.173.0.181" } {
        # Local Landing IP 的處理
    }
}
```

### rpzip.txt (IP DataGroup)

```
network 1.2.3.0/24,
network 4.5.6.7/32,
```

---

## 📈 簡化效益

| 項目 | 簡化前 | 簡化後 | 改善 |
|------|-------|--------|------|
| **配置檔** | 2 個 | 1 個 | ✅ -50% |
| **parse_rpz.sh** | 195 行 | 155 行 | ✅ -20% |
| **DataGroup 數量** | N+2 個 | 3 個固定 | ✅ 簡化 |
| **維護複雜度** | 高 | 低 | ✅ 降低 |
| **部署步驟** | 需配置 mapping | 僅配置 zones | ✅ 簡化 |

---

## 🎓 設計哲學

### 之前的設計 (過度工程)
- ❌ 試圖在 Shell Script 中處理業務邏輯
- ❌ Landing IP 分類屬於「決策邏輯」，不應在資料處理層
- ❌ 增加配置複雜度

### 現在的設計 (職責分離)
- ✅ Shell Script: 僅負責資料轉換
- ✅ iRule: 負責業務邏輯與決策
- ✅ 配置簡單，維護容易

**原則**: "Keep It Simple, Stupid" (KISS)

---

## 🔄 升級指南

如果你已經部署舊版本：

### 步驟 1: 備份

```bash
cp -r /var/tmp/RPZ_Local_Processor /var/tmp/RPZ_Local_Processor.backup
```

### 步驟 2: 更新程式碼

```bash
cd /var/tmp/RPZ_Local_Processor
# 上傳新版本覆蓋
```

### 步驟 3: 移除舊配置

```bash
rm config/datagroup_mapping.conf
```

### 步驟 4: 清理舊 DataGroups (可選)

```bash
# 如果有舊的分類 DataGroups
tmsh delete ltm data-group external dg_rpz_gcp
tmsh delete ltm data-group external dg_rpz_local
tmsh delete ltm data-group external dg_rpz_twnic
```

### 步驟 5: 測試執行

```bash
bash scripts/main.sh --force --verbose
```

### 步驟 6: 檢查輸出

```bash
ls -lh /var/tmp/rpz_datagroups/final/
head -10 /var/tmp/rpz_datagroups/final/rpz.txt
```

---

## ✅ 驗證清單

- [ ] 配置檔僅剩 `rpz_zones.conf`
- [ ] 執行 `main.sh` 無錯誤
- [ ] `/var/tmp/rpz_datagroups/final/` 有 3 個檔案
- [ ] `rpz.txt` 格式為 `"domain" := "ip",`
- [ ] iRule 能正確查詢並取得 Landing IP
- [ ] DNS 查詢回應正確

---

**簡化完成**: 2025-09-30
**程式碼減少**: 40+ 行
**複雜度降低**: 顯著
**維護性提升**: 顯著
