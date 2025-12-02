# RPZ Local Processor

F5 BIG-IP 本地 RPZ 處理方案 - 將 DNS Express RPZ Zone 轉換為 External DataGroup。

## 功能特點

- **零外部依賴** - 純 Shell Script，F5 原生支援
- **動態 Zone 支援** - 透過 zonelist.txt 配置，無需修改腳本
- **自動 DataGroup 建立** - 不存在時自動建立
- **UCS 備份相容** - 安裝於 /config/snmp，會被 UCS 備份包含
- **iCall 定期執行** - 每 5 分鐘自動檢查並更新

## 系統架構

```
┌─────────────────────────────────────────────────────────┐
│                    F5 BIG-IP DNS                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  DNS Express (RPZ Zones)                                │
│         │                                               │
│         ▼ dnsxdump                                      │
│  ┌─────────────┐      ┌─────────────┐                  │
│  │ extract_rpz │ ───▶ │  parse_rpz  │                  │
│  └─────────────┘      └──────┬──────┘                  │
│                              │                          │
│                              ▼                          │
│                    ┌─────────────────┐                 │
│                    │ update_datagroup│                 │
│                    └────────┬────────┘                 │
│                             │                           │
│                             ▼                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │  External DataGroups (rpztw, phishtw, ...)       │  │
│  │  /config/snmp/rpz_datagroups/final/              │  │
│  └──────────────────────────────────────────────────┘  │
│                             │                           │
│                             ▼                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │  iRule (DNS Traffic Processing)                  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## 快速安裝

### 1. 打包 (開發環境)

```bash
bash package.sh
# 輸出: dist/rpz_local_processor_v1.2_YYYYMMDD_HHMMSS.tar.gz
```

### 2. 部署 (F5 設備)

```bash
# 上傳到 F5
scp dist/rpz_local_processor_*.tar.gz admin@<F5_IP>:/var/tmp/

# SSH 登入後執行
cd /var/tmp
tar xzf rpz_local_processor_*.tar.gz
cd rpz_local_processor_*
bash install.sh
```

### 3. 配置 Zone 清單

```bash
vi /config/snmp/RPZ_Local_Processor/config/zonelist.txt
```

格式 (每行一個 zone，不含結尾的點):
```
rpztw
phishtw
rpz.local
```

### 4. 測試執行

```bash
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
```

### 5. 設定定期執行

```bash
bash /config/snmp/RPZ_Local_Processor/config/icall_setup_api.sh
```

## 目錄結構

```
/config/snmp/
├── RPZ_Local_Processor/          # 程式安裝目錄
│   ├── scripts/
│   │   ├── main.sh              # 主程式
│   │   ├── check_soa.sh         # SOA 變更檢查
│   │   ├── extract_rpz.sh       # dnsxdump 提取
│   │   ├── parse_rpz.sh         # RPZ 解析
│   │   ├── generate_datagroup.sh
│   │   ├── update_datagroup.sh
│   │   └── utils.sh             # 共用函數
│   └── config/
│       ├── zonelist.txt         # Zone 清單配置
│       └── icall_setup_api.sh   # iCall 設定腳本
│
└── rpz_datagroups/               # 輸出目錄
    ├── raw/                      # dnsxdump 原始資料
    ├── parsed/                   # 解析後資料
    ├── final/                    # DataGroup 來源檔
    └── .soa_cache/               # SOA Serial 快取
```

## 命令參考

```bash
# 完整執行 (檢查 SOA 變更)
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh

# 強制執行 (跳過 SOA 檢查)
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force

# 詳細輸出
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force --verbose

# 檢查 DataGroup
tmsh list ltm data-group external

# 檢查 iCall 狀態
tmsh list sys icall handler periodic rpz_update_handler

# 監控日誌
tail -f /var/log/ltm | grep -i rpz
```

## 清除安裝

```bash
# 方法 1: 從部署包執行
cd /var/tmp/rpz_local_processor_*
bash cleanup.sh

# 方法 2: 單獨上傳執行
scp cleanup.sh admin@<F5_IP>:/var/tmp/
ssh admin@<F5_IP> "bash /var/tmp/cleanup.sh"
```

## 已知問題

詳見 [docs/archive/KNOWN_ISSUES.md](docs/archive/KNOWN_ISSUES.md)

## 授權條款

MIT License - Copyright (c) 2025

## 維護者

Ryan Tseng
