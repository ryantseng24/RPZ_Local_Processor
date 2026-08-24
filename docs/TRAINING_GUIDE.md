# RPZ Local Processor 教育訓練手冊

> **版本**: 1.2
> **文件日期**: 2025-01-21
> **適用對象**: F5 BIG-IP DNS 管理人員

---

## 目錄

1. [課程大綱與時間規劃](#1-課程大綱與時間規劃)
2. [系統架構概述](#2-系統架構概述)
3. [安裝與移除操作](#3-安裝與移除操作)
4. [腳本詳細說明](#4-腳本詳細說明)
5. [可調整設定與適用場景](#5-可調整設定與適用場景)
6. [問題排查與除錯](#6-問題排查與除錯)
7. [iRule 與黑白名單機制](#7-irule-與黑白名單機制)
8. [實作練習](#8-實作練習)
9. [附錄](#9-附錄)

---

## 1. 課程大綱與時間規劃

### 建議總時長: 4 小時

| 單元 | 主題 | 建議時間 | 內容 |
|------|------|----------|------|
| 1 | 系統架構概述 | 20 分鐘 | 架構圖、資料流程、核心概念 |
| 2 | 安裝與移除操作 | 40 分鐘 | 完整安裝流程、移除流程、驗證方法 |
| 3 | 腳本詳細說明 | 50 分鐘 | 7 個核心腳本的功能、參數、限制 |
| 4 | 可調整設定 | 30 分鐘 | 環境變數、配置檔、適用場景 |
| 5 | 問題排查與除錯 | 40 分鐘 | 日誌分析、常見問題、除錯工具 |
| 6 | iRule 與黑白名單 | 30 分鐘 | iRule 邏輯、匹配規則、DataGroup |
| 7 | 實作練習 | 50 分鐘 | Hands-on Lab |
| - | 休息時間 | 20 分鐘 | 分段休息 |

---

## 2. 系統架構概述

### 2.1 整體架構圖

```
┌─────────────────────────────────────────────────────────────────────┐
│                         F5 BIG-IP DNS                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┐                                               │
│  │  DNS Express     │  ← Zone Transfer (AXFR) 從 Infoblox/BIND     │
│  │  (RPZ Zones)     │                                               │
│  └────────┬─────────┘                                               │
│           │                                                         │
│           ▼  dnsxdump (F5 內建工具)                                  │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                  RPZ Local Processor                           │ │
│  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────┐  │ │
│  │  │ check_soa   │ → │ extract_rpz │ → │     parse_rpz       │  │ │
│  │  │ (SOA 檢查)  │   │ (資料提取)  │   │ (AWK 解析 FQDN/IP)  │  │ │
│  │  └─────────────┘   └─────────────┘   └──────────┬──────────┘  │ │
│  │                                                  │             │ │
│  │  ┌─────────────────────┐   ┌─────────────────────┴──────────┐ │ │
│  │  │  update_datagroup   │ ← │      generate_datagroup        │ │ │
│  │  │  (tmsh 更新 F5)     │   │  (整理最終檔案)                │ │ │
│  │  └──────────┬──────────┘   └────────────────────────────────┘ │ │
│  └─────────────┼────────────────────────────────────────────────┘ │
│                │                                                   │
│                ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │              External DataGroups                             │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐               │  │
│  │  │  rpztw    │  │  phishtw  │  │  rpzip    │  ...          │  │
│  │  │  (FQDN)   │  │  (FQDN)   │  │  (IP)     │               │  │
│  │  └───────────┘  └───────────┘  └───────────┘               │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                │                                                   │
│                ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                      DNS iRule                               │  │
│  │           rpzdg_local_v1.tcl (DNS_REQUEST 事件)              │  │
│  │  查詢順序: white_Domains → rpztw → phishtw → blacklist      │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 核心概念

| 術語 | 說明 |
|------|------|
| **RPZ** | Response Policy Zone - DNS 回應策略區域，用於 DNS 層級的安全過濾 |
| **DNS Express** | F5 快取 DNS 區域的機制，透過 Zone Transfer 取得資料 |
| **dnsxdump** | F5 內建工具，匯出 DNS Express 中的所有記錄 |
| **External DataGroup** | F5 外部資料群組，資料存放在檔案中，可動態更新 |
| **iCall** | F5 內建的定期任務排程機制 |
| **SOA Serial** | Zone 版本號碼，用於判斷是否有更新 |

### 2.3 資料流程

```
1. DNS Express 定期從 RPZ 來源同步 Zone 資料
2. iCall 每 5 分鐘觸發 main.sh
3. check_soa.sh 比對 SOA Serial，若無變更則結束
4. extract_rpz.sh 執行 dnsxdump 匯出完整資料
5. parse_rpz.sh 解析 FQDN (A 記錄) 和 IP (rpz-ip CNAME)
6. generate_datagroup.sh 整理到 final/ 目錄
7. update_datagroup.sh 使用 tmsh 更新 F5 DataGroups
8. DNS iRule 即時查詢 DataGroups 處理 DNS 請求
```

---

## 3. 安裝與移除操作

### 3.1 安裝前準備

#### 系統需求
- F5 BIG-IP 15.x / 16.x / 17.x
- DNS Express 已啟用並同步 RPZ Zone
- admin 或 root 權限

#### 確認環境
```bash
# 確認 tmsh 可用
tmsh show sys version

# 確認 dnsxdump 可用
/usr/local/bin/dnsxdump | head -10

# 確認 DNS Express Zone 已同步
tmsh list ltm dns zone
```

### 3.2 完整安裝流程

#### 步驟 1: 上傳部署包
```bash
# 從本機上傳到 F5
scp rpz_local_processor_v1.2_*.tar.gz admin@<F5_IP>:/var/tmp/

# 或使用 F5 GUI 上傳
# System → File Management → Upload
```

#### 步驟 2: 解壓縮
```bash
cd /var/tmp
tar xzf rpz_local_processor_v1.2_*.tar.gz
cd rpz_local_processor_v1.2_*
```

#### 步驟 3: 執行安裝
```bash
bash install.sh
```

**安裝輸出範例:**
```
==========================================
  RPZ Local Processor 安裝程式
==========================================

來源目錄: /var/tmp/rpz_local_processor_v1.2_20251202
安裝目錄: /config/snmp/RPZ_Local_Processor
輸出目錄: /config/snmp/rpz_datagroups

[1/6] 檢查系統環境...
  ✓ bash
  ✓ awk
  ✓ sed
  ✓ grep

[2/6] 檢查 F5 環境...
  ✓ tmsh 指令可用
  ✓ dnsxdump 指令可用

[3/6] 建立目錄結構...
  ✓ /config/snmp/RPZ_Local_Processor
  ✓ /config/snmp/rpz_datagroups

[4/6] 複製檔案...
  ✓ scripts/*.sh
  ✓ config/zonelist.txt
  ✓ config/icall_setup_api.sh

[5/6] 設定執行權限...
  ✓ 執行權限已設定

[6/6] 驗證安裝...
  ✓ main.sh
  ✓ utils.sh
  ✓ parse_rpz.sh
  ✓ zonelist.txt

==========================================
  安裝完成！
==========================================
```

#### 步驟 4: 配置 Zone 清單
```bash
vi /config/snmp/RPZ_Local_Processor/config/zonelist.txt
```

**配置範例:**
```
# RPZ Zone 清單配置
# 每行一個 Zone 名稱 (不含結尾的點)

rpztw
phishtw
```

#### 步驟 5: 首次測試執行
```bash
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force --verbose
```

#### 步驟 6: 設定 iCall 定期執行
```bash
bash /config/snmp/RPZ_Local_Processor/config/icall_setup_api.sh
```

#### 步驟 7: 驗證安裝結果
```bash
# 檢查 DataGroup 檔案
ls -lh /config/snmp/rpz_datagroups/final/

# 檢查 F5 DataGroups
tmsh list ltm data-group external

# 檢查 iCall 配置
tmsh list sys icall handler periodic rpz_processor_handler
```

### 3.3 完整移除流程

#### 步驟 1: 上傳清除腳本
```bash
scp cleanup.sh admin@<F5_IP>:/var/tmp/
```

#### 步驟 2: 執行清除
```bash
cd /var/tmp
bash cleanup.sh
```

**清除輸出範例:**
```
==========================================
  RPZ Local Processor 清除程式
==========================================

此腳本將移除以下項目:

  [iCall 配置]
    - Handler: rpz_update_handler
    - Script:  rpz_update_script

  [程式目錄]
    - /config/snmp/RPZ_Local_Processor

  [輸出目錄]
    - /config/snmp/rpz_datagroups

  [DataGroups] (可選)

確定要繼續嗎? (yes/N): yes

=== 開始清理程序 ===

[1/5] 移除 iCall 配置...
  ✓ 已移除 Handler: rpz_update_handler
  ✓ 已移除 Script: rpz_update_script

[2/5] 移除程式目錄...
  ✓ 已移除: /config/snmp/RPZ_Local_Processor

[3/5] 移除輸出目錄...
  → 目錄大小: 2.3M
  ✓ 已移除: /config/snmp/rpz_datagroups

[4/5] 清理暫存檔案...
  ✓ 已清理 wrapper 檔案
  ✓ 已清理部署套件

[5/5] 移除 DataGroups...
  偵測到以下 External DataGroups:
    [RPZ] rpztw
    [RPZ] phishtw
    [其他] white_Domains

  是否移除 RPZ 相關 DataGroups? (y/N): y
  ✓ 已移除 DataGroup: rpztw
  ✓ 已移除 DataGroup: phishtw

儲存配置...
  ✓ 配置已儲存

=== 驗證清理結果 ===

  ✓ iCall 配置已清除
  ✓ 程式目錄已清除
  ✓ 輸出目錄已清除

==========================================
  ✅ 清除完成！環境已清理乾淨
==========================================
```

### 3.4 安裝目錄結構

```
/config/snmp/
├── RPZ_Local_Processor/           # 主程式目錄
│   ├── scripts/                   # 執行腳本
│   │   ├── main.sh               # 主控腳本
│   │   ├── utils.sh              # 工具函數庫
│   │   ├── check_soa.sh          # SOA 檢查
│   │   ├── extract_rpz.sh        # 資料提取
│   │   ├── parse_rpz.sh          # RPZ 解析
│   │   ├── generate_datagroup.sh # DataGroup 產生
│   │   └── update_datagroup.sh   # F5 更新
│   └── config/                    # 配置目錄
│       ├── zonelist.txt          # Zone 清單 ★ 主要配置檔
│       └── icall_setup_api.sh    # iCall 設定
│
├── rpz_datagroups/                # 資料輸出目錄
│   ├── raw/                       # dnsxdump 原始輸出
│   ├── parsed/                    # 解析後的中間檔案
│   ├── final/                     # 最終 DataGroup 檔案 ★
│   │   ├── rpztw.txt             # FQDN 黑名單
│   │   ├── phishtw.txt           # 釣魚網站清單
│   │   └── rpzip.txt             # IP 網段清單
│   └── .soa_cache/               # SOA Serial 快取
│
├── rpz_wrapper.sh                 # iCall wrapper 腳本
└── rpz_wrapper.log                # wrapper 執行日誌
```

---

## 4. 腳本詳細說明

> **完整規格**: 請參閱 [SCRIPT_SPECIFICATIONS.md](./SCRIPT_SPECIFICATIONS.md)

本章節提供腳本功能速覽，詳細的輸入/輸出定義、前後置條件、錯誤處理請查閱規格文件。

### 4.1 腳本總覽

| 腳本 | 行數 | 職責 | 權限需求 |
|------|:----:|------|:--------:|
| **main.sh** | 255 | 主控腳本，協調 5 步驟流程 | admin |
| **utils.sh** | 162 | 共用工具函數庫 | - |
| **check_soa.sh** | 208 | SOA Serial 版本檢查 | 一般 |
| **extract_rpz.sh** | 87 | dnsxdump 資料提取 | admin |
| **parse_rpz.sh** | 248 | AWK 解析 FQDN/IP 記錄 | 一般 |
| **generate_datagroup.sh** | 123 | 整理最終 DataGroup 檔案 | 一般 |
| **update_datagroup.sh** | 203 | tmsh 更新 F5 DataGroups | admin |

### 4.2 main.sh - 主控腳本

```
┌─────────────────────────────────────────────────────────────┐
│                        執行流程                              │
├─────────────────────────────────────────────────────────────┤
│  init() → 檢查環境                                          │
│     ↓                                                       │
│  步驟 1: check_soa.sh → NO_UPDATE? → exit 0                │
│     ↓ UPDATE_NEEDED                                         │
│  步驟 2: extract_rpz.sh → dnsxdump                         │
│     ↓                                                       │
│  步驟 3: parse_rpz.sh → AWK 解析                           │
│     ↓                                                       │
│  步驟 4: generate_datagroup.sh → 整理檔案                   │
│     ↓                                                       │
│  步驟 5: update_datagroup.sh → tmsh 更新                    │
│     ↓                                                       │
│  cleanup() → exit 0                                         │
└─────────────────────────────────────────────────────────────┘
```

| 參數 | 說明 |
|------|------|
| `-f, --force` | 強制執行，跳過 SOA 檢查 |
| `-n, --no-cleanup` | 不清理臨時檔案 |
| `-v, --verbose` | 詳細模式 (DEBUG) |

**常用範例:**
```bash
# 標準執行
bash main.sh

# 首次安裝 / 強制更新
bash main.sh --force

# 除錯模式
bash main.sh -f -n -v
```

---

### 4.3 utils.sh - 工具函數庫

**僅供 source 載入，不可直接執行**

| 分類 | 函數 | 說明 |
|------|------|------|
| **日誌** | `log_debug/info/warn/error` | 分級日誌輸出 |
| **錯誤** | `die`, `check_command` | 錯誤處理 |
| **檔案** | `ensure_dir`, `backup_file`, `read_config` | 檔案操作 |
| **時間** | `timestamp`, `timestamp_compact`, `timer_*` | 時間處理 |
| **驗證** | `is_valid_ip`, `is_valid_domain` | 格式驗證 |
| **安全** | `sanitize_input` | 清理危險字元 |

**特殊行為:** 自動檢測 TTY，在 iCall 環境禁用 ANSI 顏色碼

---

### 4.4 check_soa.sh - SOA 版本檢查

**目的:** 避免不必要的處理，節省資源

```
當前 SOA ←── dnsxdump
    ↓
比較 ←── 快取 SOA (/config/snmp/.<zone>_soa_serial.last)
    ↓
current > cached? → UPDATE_NEEDED (繼續處理)
                 → NO_UPDATE (exit 0)
```

| 命令 | 說明 |
|------|------|
| `check-all` | 檢查所有 Zones (main.sh 使用) |
| `check <zone>` | 檢查單一 Zone |
| `get <zone>` | 取得 SOA Serial |
| `reset [zone]` | 重置快取 |

---

### 4.5 extract_rpz.sh - 資料提取

**執行:** `/usr/local/bin/dnsxdump > raw/dnsxdump_YYYYMMDD_HHMMSS.out`

**輸出格式:** BIND Zone 檔案格式
```
evil.com.rpztw.         1800  IN  A     34.102.218.71
*.badsite.com.rpztw.    1800  IN  A     34.102.218.71
24.8.168.192.rpz-ip.rpztw.  300  IN  CNAME  rpz-ip.rpztw.
```

---

### 4.6 parse_rpz.sh - RPZ 解析

**核心:** AWK 解析 dnsxdump 輸出

#### 轉換規則

| 記錄類型 | 原始格式 | 輸出格式 |
|----------|----------|----------|
| FQDN | `evil.com.rpztw. IN A 1.2.3.4` | `"evil.com" := "1.2.3.4",` |
| 萬用字元 | `*.bad.com.rpztw. IN A 1.2.3.4` | `".bad.com" := "1.2.3.4",` |
| IP 網段 | `24.8.168.192.rpz-ip.rpztw. IN CNAME ...` | `network 192.168.8.0/24,` |

**萬用字元規則:** `*.example.com` → `.example.com` (前綴點表示萬用字元)

---

### 4.7 generate_datagroup.sh - DataGroup 產生

**功能:** 複製 `parsed/` 最新檔案到 `final/`

| 來源 | 目標 |
|------|------|
| `parsed/rpztw_20250121_143021.txt` | `final/rpztw.txt` |
| `parsed/phishtw_20250121_143021.txt` | `final/phishtw.txt` |
| `parsed/rpzip_20250121_143021.txt` | `final/rpzip.txt` |

---

### 4.8 update_datagroup.sh - F5 更新

**核心 tmsh 指令:**

```bash
# 檢查存在性
tmsh list ltm data-group external <name>

# 建立 (不存在時)
tmsh create ltm data-group external <name> \
    source-path file:<path> type string

# 更新 (存在時)
tmsh modify ltm data-group external <name> \
    source-path file:<path>

# 儲存配置
tmsh save sys config
```

---

### 4.9 腳本限制總表

| 腳本 | 主要限制 |
|------|----------|
| **main.sh** | 需 admin 權限、依賴 dnsxdump、不支援並行執行 |
| **utils.sh** | 僅供 source 載入 |
| **check_soa.sh** | 首次執行會初始化、使用數值比較 (>) |
| **extract_rpz.sh** | 僅 F5 DNS 環境、執行時間取決於資料量 |
| **parse_rpz.sh** | 大 Zone 耗時、不支援 AAAA 網段 |
| **generate_datagroup.sh** | 依賴檔案系統時間排序 |
| **update_datagroup.sh** | 需 admin 權限、DataGroup 類型固定為 string |

---

## 5. 可調整設定與適用場景

### 5.1 環境變數

| 變數 | 預設值 | 說明 | 適用場景 |
|------|--------|------|----------|
| `OUTPUT_DIR` | `/config/snmp/rpz_datagroups` | DataGroup 輸出目錄 | 變更儲存位置 |
| `LOG_FILE` | `/var/log/ltm` | 系統日誌檔案 | 變更日誌位置 |
| `LOG_LEVEL` | `1` (INFO) | 日誌等級 0-3 | 除錯時設為 0 |
| `DNSXDUMP_CMD` | `/usr/local/bin/dnsxdump` | dnsxdump 路徑 | 非標準安裝路徑 |
| `SOA_CACHE_DIR` | `/config/snmp` | SOA 快取目錄 | 變更快取位置 |
| `CLEANUP_TEMP` | `true` | 是否清理臨時檔 | 除錯時設為 false |
| `FORCE_RUN` | `false` | 強制執行 | 跳過 SOA 檢查 |

#### 使用方式
```bash
# 單次執行時設定
LOG_LEVEL=0 OUTPUT_DIR=/tmp/test bash main.sh --force

# 永久設定 (在 wrapper 腳本中)
export LOG_LEVEL=0
bash main.sh
```

### 5.2 配置檔案

#### zonelist.txt - Zone 清單配置

**位置**: `/config/snmp/RPZ_Local_Processor/config/zonelist.txt`

**格式**:
```
# 註解以 # 開頭
# 每行一個 Zone 名稱 (不含結尾的點)

rpztw
phishtw
malware
spam
```

**注意事項**:
- Zone 名稱同時作為 DataGroup 名稱
- 新增 Zone 後需執行一次 `main.sh --force` 初始化
- 安裝時會保留現有配置 (不覆蓋)

#### 適用場景

| 場景 | 配置方式 |
|------|----------|
| 單一 RPZ Zone | 僅保留一個 Zone 名稱 |
| 多個 RPZ Zones | 每行一個 Zone 名稱 |
| 測試環境 | 使用測試用 Zone 名稱 |
| 生產環境 | 配置正式 Zone 名稱 |

### 5.3 iCall 設定

#### 執行間隔調整

**位置**: `icall_setup_api.sh` 中的 `INTERVAL` 變數

```bash
# 預設 5 分鐘 (300 秒)
INTERVAL="${INTERVAL:-300}"

# 調整為 10 分鐘
INTERVAL=600 bash icall_setup_api.sh

# 調整為 1 分鐘 (高頻更新需求)
INTERVAL=60 bash icall_setup_api.sh
```

#### 適用場景

| 間隔 | 適用場景 |
|------|----------|
| 60 秒 | 高安全性需求，需要快速回應威脅 |
| 300 秒 (預設) | 一般生產環境 |
| 600 秒 | 大型 Zone，減少系統負載 |
| 3600 秒 | 低更新頻率的環境 |

### 5.4 DataGroup 檔案格式

#### FQDN 格式 (字典型)
```
"domain" := "landing_ip",
```

#### IP 網段格式
```
network ip/mask,
```

#### 自訂 Landing IP

若需變更 Landing IP，需修改 RPZ Zone 來源，或在 iRule 中覆寫。

---

## 6. 問題排查與除錯

### 6.1 日誌位置

| 日誌 | 位置 | 用途 |
|------|------|------|
| F5 系統日誌 | `/var/log/ltm` | RPZ 處理狀態、錯誤訊息 |
| Wrapper 日誌 | `/config/snmp/rpz_wrapper.log` | iCall 執行詳情 |
| 本地除錯 | 標準錯誤輸出 | 即時除錯訊息 |

### 6.2 日誌訊息說明

#### 正常訊息
```
INFO: RPZ SOA not changed, skip update    # SOA 未變更，跳過處理
INFO: RPZ SOA changed, start processing   # SOA 變更，開始處理
INFO: dnsxdump exported 12345 lines       # dnsxdump 匯出完成
INFO: updated DataGroup rpztw (5000 records) # DataGroup 更新成功
INFO: RPZ processing completed in 7s      # 處理完成
```

#### 錯誤訊息
```
ERROR: dnsxdump command not found         # dnsxdump 不存在
ERROR: dnsxdump output is empty           # dnsxdump 輸出為空
ERROR: RPZ extraction failed              # 資料提取失敗
ERROR: RPZ parsing failed                 # 解析失敗
ERROR: failed to update DataGroup rpztw   # DataGroup 更新失敗
```

### 6.3 常見問題與解決方案

#### 問題 1: SOA 檢查總是顯示 NO_UPDATE

**症狀**: 即使 RPZ 來源有更新，仍顯示無需更新

**診斷**:
```bash
# 檢查當前 SOA
bash /config/snmp/RPZ_Local_Processor/scripts/check_soa.sh get rpztw

# 檢查快取的 SOA
cat /config/snmp/.rpztw_soa_serial.last

# 比較兩者
```

**解決方案**:
```bash
# 重置 SOA 快取
bash /config/snmp/RPZ_Local_Processor/scripts/check_soa.sh reset

# 或強制執行
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
```

---

#### 問題 2: dnsxdump 輸出為空

**症狀**: 錯誤訊息 "dnsxdump output is empty"

**診斷**:
```bash
# 手動執行 dnsxdump
/usr/local/bin/dnsxdump | head -50

# 檢查 DNS Express Zone
tmsh list ltm dns zone
tmsh show ltm dns zone <zone_name>
```

**可能原因**:
- DNS Express 未同步 Zone
- Zone Transfer 失敗
- RPZ Zone 尚未設定

**解決方案**:
- 確認 DNS Express Zone 已同步
- 檢查 Zone Transfer 來源可達性
- 驗證 RPZ Zone 設定

---

#### 問題 3: DataGroup 更新失敗

**症狀**: 錯誤訊息 "failed to update DataGroup"

**診斷**:
```bash
# 檢查 DataGroup 狀態
tmsh list ltm data-group external rpztw

# 檢查檔案是否存在
ls -lh /config/snmp/rpz_datagroups/final/rpztw.txt

# 手動測試更新
tmsh modify ltm data-group external rpztw source-path file:/config/snmp/rpz_datagroups/final/rpztw.txt
```

**可能原因**:
- 檔案格式錯誤
- 權限不足
- DataGroup 被其他程序鎖定

**解決方案**:
- 檢查檔案格式是否正確
- 確認使用 admin 權限執行
- 重新啟動 tmm 服務 (最後手段)

---

#### 問題 4: iCall 未執行

**症狀**: 定期更新未觸發

**診斷**:
```bash
# 檢查 iCall handler 狀態
tmsh list sys icall handler periodic rpz_processor_handler

# 檢查 handler 是否啟用
tmsh list sys icall handler periodic rpz_processor_handler status

# 檢查執行日誌
tail -f /config/snmp/rpz_wrapper.log
```

**可能原因**:
- Handler 狀態為 inactive
- Script 路徑錯誤
- 權限問題

**解決方案**:
```bash
# 啟用 handler
tmsh modify sys icall handler periodic rpz_processor_handler status active

# 重新建立 iCall
bash /config/snmp/RPZ_Local_Processor/config/icall_setup_api.sh
```

---

### 6.4 除錯工具與指令

#### 基本檢查
```bash
# 檢查安裝完整性
ls -lh /config/snmp/RPZ_Local_Processor/scripts/
ls -lh /config/snmp/rpz_datagroups/final/

# 檢查 DataGroups
tmsh list ltm data-group external one-line

# 檢查 iCall 配置
tmsh list sys icall handler periodic
tmsh list sys icall script
```

#### 日誌監控
```bash
# 即時監控系統日誌
tail -f /var/log/ltm | grep -E '(RPZ|rpz|DataGroup)'

# 監控 wrapper 日誌
tail -f /config/snmp/rpz_wrapper.log

# 查看最近的 RPZ 相關日誌
grep -E '(RPZ|rpz)' /var/log/ltm | tail -50
```

#### 手動測試
```bash
# 詳細模式執行
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh -f -n -v

# 單獨測試各腳本
bash /config/snmp/RPZ_Local_Processor/scripts/check_soa.sh check-all
bash /config/snmp/RPZ_Local_Processor/scripts/extract_rpz.sh
bash /config/snmp/RPZ_Local_Processor/scripts/parse_rpz.sh
```

#### DataGroup 驗證
```bash
# 查看 DataGroup 內容
tmsh list ltm data-group external rpztw records

# 查看 DataGroup 統計
tmsh show ltm data-group external rpztw

# 測試查詢
tmsh run /util bash -c 'class lookup -value evil.com equals rpztw'
```

---

## 7. iRule 與黑白名單機制

### 7.1 iRule 概述

**檔案**: `rpzdg_local_v1.tcl`
**事件**: `DNS_REQUEST`
**功能**: 攔截 DNS 請求，查詢 DataGroups，返回自訂回應

### 7.2 處理流程

```
DNS 請求進入
    ↓
┌───────────────────────────────────────┐
│ 1. White Domains (白名單)              │
│    DataGroup: white_Domains           │
│    匹配 → 放行 (return)               │
└───────────────────────────────────────┘
    ↓ 不匹配
┌───────────────────────────────────────┐
│ 2. RPZ Blacklist (rpztw)              │
│    DataGroup: rpztw                   │
│    匹配 → 返回 Landing IP / SOA       │
└───────────────────────────────────────┘
    ↓ 不匹配
┌───────────────────────────────────────┐
│ 3. PhishTW (phishtw)                  │
│    DataGroup: phishtw                 │
│    匹配 → 返回 Landing IP / SOA       │
└───────────────────────────────────────┘
    ↓ 不匹配
┌───────────────────────────────────────┐
│ 4. Local Blacklist (blacklist_Domains)│
│    DataGroup: blacklist_Domains       │
│    匹配 → 返回固定 IP                  │
└───────────────────────────────────────┘
    ↓ 不匹配
放行 (繼續正常 DNS 解析)
```

### 7.3 DataGroup 類型與格式

| DataGroup | 類型 | 格式 | 來源 |
|-----------|------|------|------|
| `white_Domains` | 字典 (string) | `"domain" := "",` | 手動維護 |
| `rpztw` | 字典 (string) | `"domain" := "landing_ip",` | RPZ Zone 自動轉換 |
| `phishtw` | 字典 (string) | `"domain" := "landing_ip",` | RPZ Zone 自動轉換 |
| `blacklist_Domains` | 字典 (string) | `"domain" := "",` | 手動維護 |

### 7.4 匹配規則 (BIND RPZ 相容)

#### 精確匹配
```
DataGroup: "evil.com" := "1.2.3.4",
查詢: evil.com      → 匹配 ✓
查詢: www.evil.com  → 不匹配 ✗
查詢: aevil.com     → 不匹配 ✗
```

#### 萬用字元匹配
```
DataGroup: ".evil.com" := "1.2.3.4",  # 前綴點表示萬用字元
查詢: evil.com      → 匹配 ✓ (本身)
查詢: www.evil.com  → 匹配 ✓ (子網域)
查詢: a.b.evil.com  → 匹配 ✓ (多層子網域)
查詢: notevil.com   → 不匹配 ✗
```

#### iRule 實作邏輯
```tcl
# 檢查是否為萬用字元 key (前綴點)
if { [string index $rpz_key 0] eq "." } {
    # 萬用字元匹配：.evil.com 匹配 *.evil.com 和 evil.com
    set rpz_matched 1
} else {
    # 精確匹配：evil.com 只匹配 evil.com
    set keylen [string length $rpz_key]
    if { $qlen == $keylen } {
        set rpz_matched 1
    }
}
```

### 7.5 回應類型

| 查詢類型 | 黑名單回應 | 說明 |
|----------|------------|------|
| A 記錄 | Landing IP | 導向安全頁面 |
| AAAA 記錄 | IPv6 Landing | 導向安全頁面 (IPv6) |
| 其他類型 | SOA 記錄 | 表示網域存在但無此記錄 |

#### A 記錄回應範例
```tcl
DNS::answer clear
DNS::answer insert "$query_name. 30 [DNS::question class] A $landing_ip"
DNS::return
```

#### SOA 記錄回應範例
```tcl
DNS::answer clear
DNS::answer insert "$query_name. 30 IN SOA ns.rpz.local. admin.rpz.local. 2023010101 3600 600 86400 30"
DNS::return
```

### 7.6 白名單設定

白名單 DataGroup (`white_Domains`) 需手動建立和維護：

```bash
# 建立白名單檔案
cat > /config/snmp/white_domains.txt << 'EOF'
"safe.example.com" := "",
".trusted.com" := "",
"internal.company.com" := "",
EOF

# 建立 DataGroup
tmsh create ltm data-group external white_Domains \
    source-path file:/config/snmp/white_domains.txt \
    type string

# 更新白名單
vi /config/snmp/white_domains.txt
tmsh modify ltm data-group external white_Domains \
    source-path file:/config/snmp/white_domains.txt
```

### 7.7 本地黑名單設定

本地黑名單 (`blacklist_Domains`) 返回固定 IP：

| 查詢類型 | 固定回應 |
|----------|----------|
| A | `34.102.218.71` |
| AAAA | `2600:1901:0:9b4c::` |

```bash
# 建立本地黑名單
cat > /config/snmp/blacklist_domains.txt << 'EOF'
"blocked.local" := "",
".internal-block.com" := "",
EOF

tmsh create ltm data-group external blacklist_Domains \
    source-path file:/config/snmp/blacklist_domains.txt \
    type string
```

---

## 8. 實作練習

### 8.1 Lab 1: 完整安裝練習

**目標**: 從零開始完成 RPZ Local Processor 安裝

**步驟**:
1. 上傳部署包到 F5
2. 解壓縮並執行 install.sh
3. 配置 zonelist.txt
4. 執行首次測試
5. 設定 iCall 自動更新
6. 驗證安裝結果

**驗證項目**:
- [ ] 安裝腳本執行成功
- [ ] zonelist.txt 已配置正確 Zone
- [ ] main.sh --force 執行成功
- [ ] DataGroup 檔案已產生
- [ ] F5 DataGroups 已建立
- [ ] iCall handler 已啟用

---

### 8.2 Lab 2: 問題排查練習

**目標**: 模擬並解決常見問題

**場景 1: SOA 快取問題**
```bash
# 模擬：手動修改 SOA 快取為較大值
echo "9999999999" > /config/snmp/.rpztw_soa_serial.last

# 執行更新 (應該顯示 NO_UPDATE)
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh

# 診斷並修復
# ... (學員實作)
```

**場景 2: DataGroup 格式錯誤**
```bash
# 模擬：破壞 DataGroup 檔案格式
echo "invalid format" >> /config/snmp/rpz_datagroups/final/rpztw.txt

# 執行更新 (應該失敗)
bash /config/snmp/RPZ_Local_Processor/scripts/update_datagroup.sh

# 診斷並修復
# ... (學員實作)
```

---

### 8.3 Lab 3: iRule 測試練習

**目標**: 驗證黑白名單匹配規則

**準備**:
```bash
# 新增測試記錄到 rpztw DataGroup
echo '"test-block.lab" := "10.0.0.1",' >> /config/snmp/rpz_datagroups/final/rpztw.txt
echo '".wildcard-test.lab" := "10.0.0.2",' >> /config/snmp/rpz_datagroups/final/rpztw.txt
tmsh modify ltm data-group external rpztw source-path file:/config/snmp/rpz_datagroups/final/rpztw.txt
```

**測試案例**:

| 查詢 | 預期結果 |
|------|----------|
| `dig test-block.lab @<F5_DNS>` | 返回 10.0.0.1 |
| `dig www.test-block.lab @<F5_DNS>` | 正常解析 (不匹配) |
| `dig wildcard-test.lab @<F5_DNS>` | 返回 10.0.0.2 |
| `dig www.wildcard-test.lab @<F5_DNS>` | 返回 10.0.0.2 |
| `dig a.b.wildcard-test.lab @<F5_DNS>` | 返回 10.0.0.2 |

---

### 8.4 Lab 4: 完整移除練習

**目標**: 完整移除 RPZ Local Processor

**步驟**:
1. 上傳 cleanup.sh
2. 執行清除腳本
3. 選擇是否移除 DataGroups
4. 驗證清除結果

**驗證項目**:
- [ ] iCall 配置已移除
- [ ] 程式目錄已清除
- [ ] 輸出目錄已清除
- [ ] DataGroups 已移除 (如選擇)

---

## 9. 附錄

### 9.1 快速參考卡

#### 常用指令
```bash
# 手動執行更新
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force

# 檢查日誌
tail -f /var/log/ltm | grep RPZ

# 檢查 DataGroups
tmsh list ltm data-group external one-line

# 檢查 iCall 狀態
tmsh list sys icall handler periodic rpz_processor_handler

# 暫停 iCall
tmsh modify sys icall handler periodic rpz_processor_handler status inactive

# 恢復 iCall
tmsh modify sys icall handler periodic rpz_processor_handler status active

# 重置 SOA 快取
bash /config/snmp/RPZ_Local_Processor/scripts/check_soa.sh reset
```

#### 關鍵路徑
```
程式目錄:  /config/snmp/RPZ_Local_Processor/
配置檔案:  /config/snmp/RPZ_Local_Processor/config/zonelist.txt
輸出目錄:  /config/snmp/rpz_datagroups/final/
系統日誌:  /var/log/ltm
Wrapper:   /config/snmp/rpz_wrapper.log
SOA 快取:  /config/snmp/.<zone>_soa_serial.last
```

### 9.2 腳本限制總表

| 腳本 | 限制 |
|------|------|
| **main.sh** | 需 admin 權限、依賴 dnsxdump |
| **utils.sh** | 僅供 source 載入 |
| **check_soa.sh** | 依賴 dnsxdump、首次執行會初始化 |
| **extract_rpz.sh** | 僅 F5 DNS 環境可用 |
| **parse_rpz.sh** | 大型 Zone 耗時較長、不支援 AAAA 網段 |
| **generate_datagroup.sh** | 空檔案會建立但不更新 |
| **update_datagroup.sh** | 需 admin 權限、類型固定為 string |

### 9.3 錯誤代碼說明

| 退出碼 | 說明 |
|--------|------|
| 0 | 成功 / 無需更新 |
| 1 | 一般錯誤 |
| 2 | SOA 檢查失敗 |

### 9.4 聯絡資訊

如有問題請聯繫:
- 專案維護者: [聯絡資訊]
- 技術支援: [支援管道]

---

**文件結束**
