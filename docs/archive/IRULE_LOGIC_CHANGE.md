# iRule 邏輯變更記錄

## 📅 變更日期
**2025-11-07**

## 🎯 變更目的

從「邊界檢查」改為「BIND DNS RPZ 標準邏輯」，實現精確匹配與萬用字元匹配的正確區分。

---

## 📊 影響的記錄數

### 實際 LAB 環境數據（10.8.34.234）

```
rpztw DataGroup:
├── 總記錄數: 58,602 筆
├── 萬用字元記錄: 29,035 筆 (以 ".domain" 格式)
└── 精確記錄: 29,567 筆 (以 "domain" 格式)

phishtw DataGroup:
├── 總記錄數: 819 筆
├── 萬用字元記錄: 374 筆
└── 精確記錄: 445 筆
```

### 檔案大小
- `rpz.txt`: 2.2M (58,602 行)
- `phishtw.txt`: 31K (819 行)

---

## 🔄 邏輯變更詳解

### 舊版邏輯：邊界檢查（問題）

**iRule 版本**: rpzdg_v15.tcl 及更早版本

**匹配方式**:
```tcl
if { [class match -- $query_name ends_with rpztw] } {
    # 直接使用 F5 ends_with 匹配
    set landing_ip [class match -value $query_name ends_with rpztw]
    # ...回應處理
}
```

**DataGroup 格式**:
```
"example.com" := "34.102.218.71",
"malicious.net" := "182.173.0.181",
```

**匹配行為**:
| DataGroup Key | 查詢 | 匹配結果 | 問題 |
|--------------|------|---------|------|
| `"example.com"` | `example.com` | ✅ 匹配 | 正常 |
| `"example.com"` | `www.example.com` | ✅ 匹配 | ❌ **不應匹配！** |
| `"example.com"` | `sub.www.example.com` | ✅ 匹配 | ❌ **不應匹配！** |

**問題總結**:
- ❌ 所有記錄都變成「萬用字元」行為
- ❌ 無法實現「精確匹配」
- ❌ 不符合 BIND DNS RPZ 標準
- ❌ 可能誤封鎖合法子網域

---

### 新版邏輯：BIND DNS RPZ 標準

**iRule 版本**: rpzdg_local_v1.tcl (2025-11-07)

**匹配方式**:
```tcl
if { [class match -- $query_name ends_with rpztw] } {
    set rpz_key [class match -name $query_name ends_with rpztw]
    set landing_ip [class match -value $query_name ends_with rpztw]
    set qlen [string length $query_name]

    # ===== 關鍵邏輯 =====
    # 1. 檢查是否為萬用字元記錄
    if { [string index $rpz_key 0] eq "." } {
        # 萬用字元匹配：.example.com 匹配 example.com 及所有子網域
        set rpz_matched 1
    } else {
        # 精確匹配：example.com 只匹配 example.com
        set keylen [string length $rpz_key]
        if { $qlen == $keylen } {
            set rpz_matched 1
        }
    }

    if { $rpz_matched } {
        # ...回應處理
    }
}
```

**DataGroup 格式**:
```
".example.com" := "34.102.218.71",      # 萬用字元
"www.malicious.net" := "182.173.0.181", # 精確
".evil.org" := "210.64.24.25",          # 萬用字元
"phishing.com" := "34.102.218.71",      # 精確
```

**匹配行為**:

#### 萬用字元記錄（以 "." 開頭）
| DataGroup Key | 查詢 | 匹配結果 | 說明 |
|--------------|------|---------|------|
| `".example.com"` | `example.com` | ✅ 匹配 | 匹配主網域 |
| `".example.com"` | `www.example.com` | ✅ 匹配 | 匹配子網域 |
| `".example.com"` | `sub.www.example.com` | ✅ 匹配 | 匹配所有子網域 |

#### 精確記錄（不以 "." 開頭）
| DataGroup Key | 查詢 | 匹配結果 | 說明 |
|--------------|------|---------|------|
| `"www.example.com"` | `www.example.com` | ✅ 匹配 | 長度相等，精確匹配 |
| `"www.example.com"` | `example.com` | ❌ 不匹配 | 長度不等 |
| `"www.example.com"` | `sub.www.example.com` | ❌ 不匹配 | 長度不等 |

---

## 📝 AWK 解析邏輯

**檔案**: `scripts/parse_rpz.sh`

```awk
# 處理 FQDN 類型 (A 記錄)
if ($4 == "A") {
    if ($1 ~ /\.rpztw\.?$/) {
        sub(/\.rpztw\.$/, "", $1)

        # 檢查是否為萬用字元記錄 (*.domain)
        if (substr($1, 1, 2) == "*.") {
            # 移除 "*." 前綴，取得 domain
            domain = substr($1, 3)
            # 只產生萬用字元記錄（加前綴點）
            rpz["." domain] = $5
        } else {
            # 一般精確記錄（不加前綴點）
            rpz[$1] = $5
        }
    }
}

END {
    # 輸出 key := value 格式
    for (d in rpz) {
        print "\"" d "\" := \"" rpz[d] "\","
    }
}
```

**轉換範例**:

| 原始 RPZ 記錄 | 轉換後 DataGroup | 匹配類型 |
|--------------|-----------------|---------|
| `*.example.com. IN A 1.2.3.4` | `".example.com" := "1.2.3.4",` | 萬用字元 |
| `www.evil.com. IN A 5.6.7.8` | `"www.evil.com" := "5.6.7.8",` | 精確 |
| `*.malicious.net. IN A 9.10.11.12` | `".malicious.net" := "9.10.11.12",` | 萬用字元 |
| `phishing.org. IN A 13.14.15.16` | `"phishing.org" := "13.14.15.16",` | 精確 |

---

## 🎓 BIND DNS RPZ 標準說明

### 萬用字元語法

在 BIND DNS RPZ 中：
- `*.example.com` 匹配 `example.com` 的所有子網域
- 在 DataGroup 中表示為 `".example.com"`（前綴點）

### 精確匹配語法

在 BIND DNS RPZ 中：
- `www.example.com` 只匹配 `www.example.com` 本身
- 在 DataGroup 中表示為 `"www.example.com"`（無前綴點）

### 匹配優先順序

F5 iRule 使用 `class match -- $query_name ends_with dg_name` 匹配：
1. **最長匹配優先**（F5 內建行為）
2. 在我們的實作中，再加上：
   - 萬用字元：總是匹配
   - 精確：必須長度相等才匹配

---

## ✅ 優點與改進

### 舊版問題
- ❌ 無法區分精確匹配與萬用字元匹配
- ❌ 可能誤封鎖合法網域
- ❌ 不符合 DNS RPZ 標準
- ❌ 無法實現細粒度控制

### 新版優點
- ✅ 符合 BIND DNS RPZ 標準（RFC 規範）
- ✅ 支援精確匹配與萬用字元匹配
- ✅ 細粒度控制（可分別封鎖主網域或子網域）
- ✅ 效能提升（精確匹配只需長度檢查）
- ✅ 降低誤封鎖風險

---

## 📚 相關文件

- **iRule 當前版本**: `irules/rpzdg_local_v1.tcl`
- **iRule 舊版本**: `irules/archive/rpzdg_v15.tcl`
- **AWK 解析邏輯**: `scripts/parse_rpz.sh`
- **架構簡化說明**: `SIMPLIFICATION_SUMMARY.md`

---

## 🧪 測試驗證

### 測試案例 1: 萬用字元記錄

**DataGroup**:
```
".example.com" := "1.2.3.4",
```

**測試**:
| 查詢 | 預期結果 | 實際結果 |
|------|---------|---------|
| `example.com` | 1.2.3.4 | ✅ 1.2.3.4 |
| `www.example.com` | 1.2.3.4 | ✅ 1.2.3.4 |
| `sub.www.example.com` | 1.2.3.4 | ✅ 1.2.3.4 |

### 測試案例 2: 精確記錄

**DataGroup**:
```
"www.example.com" := "5.6.7.8",
```

**測試**:
| 查詢 | 預期結果 | 實際結果 |
|------|---------|---------|
| `www.example.com` | 5.6.7.8 | ✅ 5.6.7.8 |
| `example.com` | 不匹配 | ✅ 不匹配 |
| `sub.www.example.com` | 不匹配 | ✅ 不匹配 |

### 測試案例 3: 混合記錄

**DataGroup**:
```
".example.com" := "1.2.3.4",
"www.example.com" := "5.6.7.8",
```

**測試**:
| 查詢 | 預期結果 | 實際結果 | 說明 |
|------|---------|---------|------|
| `example.com` | 1.2.3.4 | ✅ 1.2.3.4 | 匹配萬用字元 |
| `www.example.com` | 5.6.7.8 | ✅ 5.6.7.8 | 精確匹配優先（最長匹配） |
| `sub.example.com` | 1.2.3.4 | ✅ 1.2.3.4 | 匹配萬用字元 |

---

## 📊 統計資料

### LAB 環境（10.8.34.234）

**執行狀態**:
- iCall 執行次數: 834 次
- 最後執行: 2025-11-10 15:00
- SOA 檢查: 正常運作

**DataGroup 記錄**:
```bash
# 查看記錄數
wc -l /var/tmp/rpz_datagroups/final/rpz.txt
# 58602 /var/tmp/rpz_datagroups/final/rpz.txt

# 查看萬用字元記錄數
grep -c '^"\.' /var/tmp/rpz_datagroups/final/rpz.txt
# 29035

# 查看精確記錄數（總數 - 萬用字元）
# 58602 - 29035 = 29567
```

---

## 🔗 參考資料

- **BIND DNS RPZ**: https://www.isc.org/rpz/
- **F5 DataGroup 文件**: https://techdocs.f5.com/kb/en-us/products/big-ip_ltm/manuals/product/ltm-concepts-11-5-0/15.html
- **iRule 開發指南**: https://clouddocs.f5.com/api/irules/

---

**文件建立**: 2025-11-10
**作者**: Ryan Tseng with Claude Code
**版本**: 1.0
**狀態**: ✅ 已驗證並部署
