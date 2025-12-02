# 路徑修正記錄

## 📅 修正日期
**2025-11-10**

## 🎯 修正原因

在對照 F5 LAB 環境（10.8.34.234）後，發現部分文件中記錄的部署路徑與實際環境不符。

### 問題發現
- **實際部署路徑**: `/var/tmp/RPZ_Local_Processor/`
- **文件記錄路徑**: `/config/snmp/RPZ_Local_Processor/` (錯誤)

### 根本原因
上次部署時未正確更新文件，或部署位置在後期變更但未同步更新文件記錄。

---

## ✅ F5 LAB 環境實際狀態驗證

### 連接資訊
- **設備**: 10.8.34.234 (dns LAB)
- **帳號**: admin/uniforce
- **驗證日期**: 2025-11-10 15:00

### 實際配置
```bash
# 專案位置
/var/tmp/RPZ_Local_Processor/

# iCall 配置
sys icall script rpz_processor_script {
    definition {
        exec bash /var/tmp/RPZ_Local_Processor/scripts/main.sh
    }
}

sys icall handler periodic rpz_processor_handler {
    interval 300
    script rpz_processor_script
}

# 執行狀態
- 執行次數: 834 次
- 狀態: active
- 最後執行: 2025-11-10 15:00:00
```

### 檔案驗證
```bash
/var/tmp/RPZ_Local_Processor/
├── scripts/                    ✅ 存在
│   ├── check_soa.sh
│   ├── extract_rpz.sh
│   ├── generate_datagroup.sh
│   ├── main.sh
│   ├── parse_rpz.sh           (2025-11-07 更新)
│   ├── update_datagroup.sh    (2025-11-07 更新)
│   └── utils.sh
├── irules/                     ✅ 存在
│   ├── dns_rpz_irule.tcl
│   └── rpzdg_local_v1.tcl     (2025-11-07，當前使用)
├── config/
│   └── rpz_zones.conf         (rpztw, phishtw)
└── config/icall_setup.sh      ✅ 存在
```

### DataGroup 輸出
```bash
/var/tmp/rpz_datagroups/final/
├── rpz.txt       2.2M  ✅ 正常
├── phishtw.txt   31K   ✅ 正常
└── rpzip.txt     0     (無 IP 記錄，正常)
```

---

## 📝 修正內容

### 1. DEPLOYMENT_SUCCESS.md
**修正項目**:
- 部署路徑: `/config/snmp/` → `/var/tmp/`
- F5 設備 IP: `10.8.34.6` → `10.8.34.234`
- 執行方式: 更新為 iCall 配置
- 檢查清單: 更新設備 IP 和路徑

**影響行數**: 4 處修正

### 2. DEPLOYMENT_GUIDE.md
**修正項目**:
- 上傳路徑: `/config/snmp/` → `/var/tmp/`
- 所有腳本路徑: 統一改為 `/var/tmp/RPZ_Local_Processor/`
- 步驟 6: 從 cron 改為 iCall 設定說明
- iRule 檔案: `dns_rpz_irule.tcl` → `rpzdg_local_v1.tcl`
- 效能優化: cron 頻率 → iCall 間隔調整
- 支援資訊: 更新專案位置和執行方式

**影響行數**: 8 處修正

### 3. config/cron_example.txt
**修正項目**:
- 檔案標題: 增加「已改用 iCall」說明
- 注意事項: 更新專案位置和建議使用 iCall
- 所有範例路徑: `/config/snmp/` → `/var/tmp/`
- Shell 指令: `sh` → `bash`
- 日誌路徑: `/shared/log/` → `/var/log/`
- 新增: iCall 推薦說明和快速設定指引

**影響行數**: 全檔案更新

### 4. SIMPLIFICATION_SUMMARY.md
**修正項目**:
- 升級指南備份路徑: `/config/snmp/` → `/var/tmp/`

**影響行數**: 2 處修正

---

## 🗂️ 檔案整理

### iRule 版本管理

**舊版本歸檔**:
```bash
# 移動舊版 iRule
rpzdg_v15.tcl → irules/archive/rpzdg_v15.tcl
```

**建立說明文件**:
- `irules/archive/README.md` - 說明歸檔檔案的版本差異

**當前使用版本**:
- `irules/rpzdg_local_v1.tcl` (2025-11-07)

---

## 📊 修正前後對照表

| 項目 | 修正前 | 修正後 | 狀態 |
|------|--------|--------|------|
| **專案路徑** | `/config/snmp/RPZ_Local_Processor` | `/var/tmp/RPZ_Local_Processor` | ✅ 修正 |
| **F5 設備** | 10.8.34.6 (dnsr10600) | 10.8.34.234 (dns LAB) | ✅ 修正 |
| **執行方式** | cron | iCall (interval 300) | ✅ 修正 |
| **iRule 版本** | rpzdg_v15.tcl (多處) | rpzdg_local_v1.tcl | ✅ 整理 |
| **文件一致性** | 4 個文件路徑錯誤 | 全部修正為實際路徑 | ✅ 統一 |

---

## ✅ 驗證清單

- [x] 連接 F5 LAB 驗證實際路徑
- [x] 檢查 iCall 配置狀態
- [x] 確認專案檔案存在性
- [x] 驗證 DataGroup 輸出正常
- [x] 更新 DEPLOYMENT_SUCCESS.md
- [x] 更新 DEPLOYMENT_GUIDE.md
- [x] 更新 config/cron_example.txt
- [x] 更新 SIMPLIFICATION_SUMMARY.md
- [x] 歸檔舊版 iRule 檔案
- [x] 建立 archive 說明文件
- [x] 建立此修正記錄

---

## 🎯 後續建議

### 1. Git 提交
建議以下提交訊息：
```
docs: 修正部署路徑為實際 LAB 環境配置

- 更新所有文件中的部署路徑 (/config/snmp → /var/tmp)
- 修正 F5 設備資訊 (10.8.34.6 → 10.8.34.234)
- 更新執行方式說明 (cron → iCall)
- 歸檔舊版 iRule (rpzdg_v15.tcl)
- 新增路徑修正記錄文件

對照 F5 LAB 環境實際配置進行文件同步更新。
```

### 2. 文件維護
- ✅ 所有文件已與實際環境一致
- ✅ iCall 配置已記錄在 docs/SCHEDULE_SETUP.md
- ✅ 舊版 iRule 已歸檔並說明

### 3. 部署注意
如果需要在其他 F5 設備部署：
- 確認使用 `/var/tmp/` 路徑
- 使用 iCall 而非 cron
- 使用 `rpzdg_local_v1.tcl` iRule 版本

---

## 📞 相關資訊

- **LAB 環境**: 10.8.34.234 (admin/uniforce)
- **專案位置**: `/var/tmp/RPZ_Local_Processor/`
- **iCall 狀態**: active (834 次執行)
- **執行頻率**: 每 5 分鐘 (300 秒)
- **DataGroup**:
  - rpztw: 58,602 筆 (萬用字元 29,035 + 精確 29,567)
  - phishtw: 819 筆 (萬用字元 374 + 精確 445)

---

**修正完成**: 2025-11-10 15:10
**執行者**: Claude Code with Ryan
**狀態**: ✅ 全部完成
