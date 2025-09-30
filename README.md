# RPZ Local Processor - F5 On-Device Solution

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 專案概述

本專案是 RPZ to DataGroup 的**簡化版本**，採用 **F5 本地處理架構**，無需中轉伺服器。

### 與原方案的差異

| 項目 | 方法 A (RPZ_to_DataGroup) | 方法 B (本專案) |
|------|---------------------------|----------------|
| **架構** | 中轉伺服器 + HTTP Server | F5 本地執行 |
| **技術** | Python 3 | Pure Shell Script |
| **資料來源** | AXFR from DNS Server | DNS Express (F5 內建) |
| **依賴** | Python modules | Bash built-in only |
| **部署** | 外部伺服器 (10.8.38.223) | F5 Device 內部 |
| **維護** | 需管理多台同步 | 各設備獨立運行 |

### 核心優勢

✅ **零外部依賴** - 純 Shell Script，F5 原生支援
✅ **架構簡化** - 無需中轉伺服器和 HTTP 服務
✅ **資料在地化** - 直接從 DNS Express 讀取
✅ **部署容易** - 一鍵安裝，無需 Python 環境
✅ **高可用性** - 單點故障風險降低

---

## 系統架構

```
┌─────────────────────────────────────────────────────┐
│              F5 BIG-IP DNS Device                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────┐    Shell Script    ┌──────────┐ │
│  │ DNS Express  │ ───────────────────▶│ Parser   │ │
│  │ (RPZ Zones)  │                     └─────┬────┘ │
│  └──────────────┘                           │      │
│                                              ▼      │
│                                     ┌────────────┐ │
│                                     │  Generate  │ │
│                                     │ DataGroups │ │
│                                     └──────┬─────┘ │
│                                            │       │
│                                            ▼       │
│  ┌──────────────────────────────────────────────┐ │
│  │  External DataGroup Files                    │ │
│  │  /var/tmp/rpz_datagroups/*.txt               │ │
│  └──────────────────────────────────────────────┘ │
│                         │                         │
│                         ▼                         │
│  ┌──────────────────────────────────────────────┐ │
│  │  iRule (DNS Traffic Processing)              │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## 快速開始

### 前置條件

- F5 BIG-IP DNS 設備
- TMOS Shell 訪問權限
- DNS Express 已配置並運行
- Bash 環境 (TMOS 內建)

### 安裝步驟

```bash
# 1. 將專案檔案上傳到 F5 設備
scp -r RPZ_Local_Processor/ root@<F5_IP>:/var/tmp/

# 2. SSH 登入 F5
ssh root@<F5_IP>

# 3. 執行安裝
cd /var/tmp/RPZ_Local_Processor
bash install.sh

# 4. 執行轉換
bash scripts/main.sh
```

---

## 專案結構

```
RPZ_Local_Processor/
├── README.md                    # 本文件
├── install.sh                   # 一鍵安裝腳本
├── config/
│   ├── rpz_zones.conf          # RPZ Zone 清單
│   └── cron_example.txt        # Cron 設定範例
├── scripts/
│   ├── main.sh                 # 主執行腳本
│   ├── extract_rpz.sh          # 從 DNS Express 提取 RPZ
│   ├── parse_rpz.sh            # 解析 RPZ 記錄
│   ├── generate_datagroup.sh   # 產生 DataGroup 檔案
│   └── utils.sh                # 共用函數庫
├── irules/
│   ├── dns_rpz_irule_v2.tcl    # DNS 處理 iRule
│   └── deploy_irule.sh         # iRule 部署腳本
├── tests/
│   ├── test_data/              # 測試資料
│   └── run_tests.sh            # 測試腳本
├── logs/                        # 執行日誌
└── docs/
    ├── ARCHITECTURE.md         # 架構說明
    ├── MIGRATION.md            # 從方法 A 遷移指南
    └── F5_SHELL_GUIDE.md       # F5 Shell 環境說明
```

---

## 使用說明

### 配置文件

**config/rpz_zones.conf** - 定義要處理的 RPZ Zones
```bash
# Format: zone_name
rpztw.
phishtw.
```

### 手動執行

```bash
# 完整執行
bash scripts/main.sh

# 單步執行
bash scripts/extract_rpz.sh        # 提取 RPZ 資料
bash scripts/parse_rpz.sh          # 解析記錄
bash scripts/generate_datagroup.sh # 產生 DataGroup 檔案
```

### 排程執行

```bash
# 使用 iCall 定期執行 (推薦)
# 詳見 docs/ICALL_SETUP.md

# 或使用 cron (如果 F5 支援)
*/5 * * * * /var/tmp/RPZ_Local_Processor/scripts/main.sh >> /var/tmp/rpz_processor.log 2>&1
```

---

## 輸出檔案

DataGroup 檔案會產生在：
```
/var/tmp/rpz_datagroups/final/
├── rpz.txt          # RPZ FQDN DataGroup (key := value 格式)
├── phishtw.txt      # PhishTW FQDN DataGroup
└── rpzip.txt        # IP 網段 DataGroup
```

**檔案格式範例**：
```
# rpz.txt - FQDN DataGroup
"malicious.com" := "34.102.218.71",
"phishing.net" := "182.173.0.181",
"evil.org" := "210.64.24.25",

# rpzip.txt - IP DataGroup
network 1.2.3.0/24,
network 4.5.6.7/32,
```

---

## 進階功能

### 日誌管理

```bash
# 查看執行日誌
tail -f logs/rpz_processor.log

# 清理舊日誌
find logs/ -name "*.log" -mtime +7 -delete
```

### 效能監控

```bash
# 執行時間統計
bash scripts/main.sh --profile

# 查看處理記錄數
bash scripts/main.sh --stats
```

---

## 疑難排解

### 常見問題

**Q: DNS Express 找不到 Zone 資料**
```bash
# 檢查 DNS Express 狀態
tmsh list ltm dns zone
tmsh show ltm dns zone <zone_name>
```

**Q: 權限不足**
```bash
# 確保腳本有執行權限
chmod +x scripts/*.sh
```

**Q: DataGroup 未更新**
```bash
# 檢查 DataGroup source-path
tmsh list ltm data-group external
```

---

## 與方法 A 的遷移

如果你正在使用原版 RPZ_to_DataGroup：

1. 保持原系統運行
2. 在 F5 上部署本方案
3. 比對 DataGroup 輸出內容
4. 驗證 DNS 解析結果一致
5. 逐步切換 iRule 引用
6. 確認無誤後停用中轉伺服器

詳見：[docs/MIGRATION.md](docs/MIGRATION.md)

---

## 授權條款

MIT License

Copyright (c) 2025 UNIFORCE

---

## 聯絡資訊

- 維護者: Ryan Tseng
- 原專案: [RPZ_to_DataGroup](../RPZ_to_DataGroup/)

**狀態**: 🚧 開發中 - 等待程式碼重構