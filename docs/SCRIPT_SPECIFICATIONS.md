# RPZ Local Processor 腳本規格說明書

> **版本**: 1.2
> **文件日期**: 2025-01-21
> **格式**: 簡化 SDD SPEC

---

## 目錄

1. [main.sh - 主控腳本](#1-mainsh---主控腳本)
2. [utils.sh - 工具函數庫](#2-utilssh---工具函數庫)
3. [check_soa.sh - SOA 版本檢查](#3-check_soash---soa-版本檢查)
4. [extract_rpz.sh - 資料提取](#4-extract_rpzsh---資料提取)
5. [parse_rpz.sh - RPZ 解析](#5-parse_rpzsh---rpz-解析)
6. [generate_datagroup.sh - DataGroup 產生](#6-generate_datagroupsh---datagroup-產生)
7. [update_datagroup.sh - F5 更新](#7-update_datagroupsh---f5-更新)

---

## 1. main.sh - 主控腳本

### 1.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/main.sh` |
| **程式碼行數** | 255 行 |
| **執行權限** | admin / root |
| **職責** | 協調整個 RPZ 處理流程，依序呼叫子腳本 |

### 1.2 介面定義

#### 輸入 (Input)

| 類型 | 名稱 | 必要 | 說明 |
|------|------|:----:|------|
| **參數** | `-f, --force` | 否 | 強制執行，跳過 SOA 檢查 |
| **參數** | `-n, --no-cleanup` | 否 | 不清理臨時檔案 |
| **參數** | `-v, --verbose` | 否 | 詳細模式 (LOG_LEVEL=0) |
| **參數** | `-h, --help` | 否 | 顯示使用說明 |
| **環境變數** | `OUTPUT_DIR` | 否 | DataGroup 輸出目錄 (預設: `/config/snmp/rpz_datagroups`) |
| **環境變數** | `LOG_FILE` | 否 | 系統日誌位置 (預設: `/var/log/ltm`) |
| **環境變數** | `LOG_LEVEL` | 否 | 日誌等級 0-3 (預設: 1) |
| **環境變數** | `CLEANUP_TEMP` | 否 | 是否清理臨時檔 (預設: true) |
| **環境變數** | `FORCE_RUN` | 否 | 強制執行 (預設: false) |
| **檔案** | `config/zonelist.txt` | 是 | Zone 清單配置 |

#### 輸出 (Output)

| 類型 | 位置 | 說明 |
|------|------|------|
| **退出碼** | - | 0=成功/無需更新, 1=錯誤 |
| **日誌** | `/var/log/ltm` | RPZ 處理狀態訊息 |
| **日誌** | stderr | 即時執行狀態 (有顏色) |
| **檔案** | `${OUTPUT_DIR}/final/*.txt` | DataGroup 檔案 (透過子腳本) |

### 1.3 執行條件

#### 前置條件 (Preconditions)

| 條件 | 檢查方式 | 失敗行為 |
|------|----------|----------|
| bash 可用 | `check_command "bash"` | 終止，退出碼 1 |
| awk 可用 | `check_command "awk"` | 終止，退出碼 1 |
| sed 可用 | `check_command "sed"` | 終止，退出碼 1 |
| grep 可用 | `check_command "grep"` | 終止，退出碼 1 |
| tmsh 可用 | `command -v tmsh` | 警告，繼續執行 |
| dnsxdump 可用 | `command -v dnsxdump` | 警告，繼續執行 |
| zonelist.txt 存在 | 由子腳本檢查 | 終止，退出碼 1 |

#### 後置條件 (Postconditions)

| 條件 | 說明 |
|------|------|
| SOA 快取已更新 | 若有處理，SOA Serial 已寫入快取 |
| DataGroup 檔案已產生 | `${OUTPUT_DIR}/final/` 下有最新檔案 |
| F5 DataGroups 已更新 | tmsh 已執行 modify/create |
| 配置已儲存 | `tmsh save sys config` 已執行 |
| 臨時檔案已清理 | 超過 7 天的檔案已刪除 (除非 --no-cleanup) |

### 1.4 處理邏輯

```
┌─────────────────────────────────────────────────────────────┐
│                        main()                               │
├─────────────────────────────────────────────────────────────┤
│  1. init()                                                  │
│     ├─ 建立 LOG_DIR, OUTPUT_DIR                            │
│     └─ 檢查必要指令                                         │
│                                                             │
│  2. 步驟 1/5: SOA 檢查                                      │
│     ├─ FORCE_RUN=true → 跳過                                │
│     ├─ check_soa.sh check-all                              │
│     │   ├─ 輸出 "NO_UPDATE" → exit 0 (正常結束)            │
│     │   ├─ 輸出 "UPDATE_NEEDED" → 繼續                     │
│     │   └─ 其他 → exit 1 (錯誤)                            │
│                                                             │
│  3. 步驟 2/5: 資料提取                                      │
│     └─ extract_rpz.sh                                       │
│        └─ 失敗 → exit 1                                     │
│                                                             │
│  4. 步驟 3/5: RPZ 解析                                      │
│     └─ parse_rpz.sh                                         │
│        └─ 失敗 → exit 1                                     │
│                                                             │
│  5. 步驟 4/5: DataGroup 產生                                │
│     └─ generate_datagroup.sh                                │
│        └─ 失敗 → exit 1                                     │
│                                                             │
│  6. 步驟 5/5: F5 更新                                       │
│     └─ update_datagroup.sh                                  │
│        └─ 失敗 → exit 1                                     │
│                                                             │
│  7. cleanup()                                               │
│     └─ 清理超過 7 天的檔案                                   │
│                                                             │
│  8. exit 0                                                  │
└─────────────────────────────────────────────────────────────┘
```

### 1.5 錯誤處理

| 錯誤情境 | 處理方式 | 日誌訊息 |
|----------|----------|----------|
| SOA 檢查失敗 | exit 1 | `ERROR: RPZ SOA check failed` |
| 資料提取失敗 | exit 1 | `ERROR: RPZ extraction failed` |
| RPZ 解析失敗 | exit 1 | `ERROR: RPZ parsing failed` |
| DataGroup 產生失敗 | exit 1 | `ERROR: DataGroup generation failed` |
| F5 更新失敗 | exit 1 | `ERROR: F5 update failed` |
| 任何未預期錯誤 | trap ERR | `ERROR: 執行過程發生錯誤，退出碼: $?` |

### 1.6 依賴關係

```
main.sh
├── source: utils.sh (必要)
├── call: check_soa.sh (步驟 1)
├── call: extract_rpz.sh (步驟 2)
├── call: parse_rpz.sh (步驟 3)
├── call: generate_datagroup.sh (步驟 4)
└── call: update_datagroup.sh (步驟 5)
```

### 1.7 使用範例

```bash
# 標準執行 (由 iCall 呼叫)
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh

# 首次安裝 / 強制更新
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force

# 除錯模式 (保留檔案 + 詳細輸出)
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh -f -n -v

# 自訂輸出目錄
OUTPUT_DIR=/tmp/test bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
```

### 1.8 限制與注意事項

| 項目 | 說明 |
|------|------|
| **權限** | 需要 admin/root 權限執行 tmsh |
| **環境** | 僅支援 F5 BIG-IP (需 tmsh, dnsxdump) |
| **並行** | 不支援同時執行多個 instance |
| **原子性** | 任一步驟失敗即終止，不會 rollback |
| **日誌空間** | 長期執行需注意 /var/log 空間 |

---

## 2. utils.sh - 工具函數庫

### 2.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/utils.sh` |
| **程式碼行數** | 162 行 |
| **執行方式** | 僅供 source 載入，不可直接執行 |
| **職責** | 提供所有腳本共用的工具函數 |

### 2.2 函數規格

#### 2.2.1 日誌函數

##### `log_debug(message)`
| 項目 | 說明 |
|------|------|
| **功能** | 輸出 DEBUG 等級日誌 |
| **參數** | `message` - 日誌訊息 |
| **輸出** | stderr, 格式: `[DEBUG] message` |
| **條件** | 僅當 `LOG_LEVEL <= 0` 時輸出 |
| **顏色** | 藍色 (TTY 環境) |

##### `log_info(message)`
| 項目 | 說明 |
|------|------|
| **功能** | 輸出 INFO 等級日誌 |
| **參數** | `message` - 日誌訊息 |
| **輸出** | stderr, 格式: `[INFO] message` |
| **條件** | 僅當 `LOG_LEVEL <= 1` 時輸出 |
| **顏色** | 綠色 (TTY 環境) |

##### `log_warn(message)`
| 項目 | 說明 |
|------|------|
| **功能** | 輸出 WARN 等級日誌 |
| **參數** | `message` - 日誌訊息 |
| **輸出** | stderr, 格式: `[WARN] message` |
| **條件** | 僅當 `LOG_LEVEL <= 2` 時輸出 |
| **顏色** | 黃色 (TTY 環境) |

##### `log_error(message)`
| 項目 | 說明 |
|------|------|
| **功能** | 輸出 ERROR 等級日誌 |
| **參數** | `message` - 日誌訊息 |
| **輸出** | stderr, 格式: `[ERROR] message` |
| **條件** | 僅當 `LOG_LEVEL <= 3` 時輸出 |
| **顏色** | 紅色 (TTY 環境) |

#### 2.2.2 錯誤處理函數

##### `die(message)`
| 項目 | 說明 |
|------|------|
| **功能** | 輸出錯誤訊息並終止程式 |
| **參數** | `message` - 錯誤訊息 |
| **行為** | 呼叫 `log_error()` 後 `exit 1` |

##### `check_command(cmd)`
| 項目 | 說明 |
|------|------|
| **功能** | 檢查指令是否存在 |
| **參數** | `cmd` - 指令名稱 |
| **成功** | 無輸出，繼續執行 |
| **失敗** | 呼叫 `die("必要指令不存在: $cmd")` |

#### 2.2.3 檔案操作函數

##### `ensure_dir(dir)`
| 項目 | 說明 |
|------|------|
| **功能** | 確保目錄存在，不存在則建立 |
| **參數** | `dir` - 目錄路徑 |
| **成功** | 目錄存在或已建立 |
| **失敗** | 呼叫 `die("無法建立目錄: $dir")` |

##### `backup_file(file)`
| 項目 | 說明 |
|------|------|
| **功能** | 備份檔案 |
| **參數** | `file` - 檔案路徑 |
| **行為** | 複製為 `file.YYYYMMDD_HHMMSS.bak` |
| **檔案不存在** | 無動作 |

##### `read_config(config_file)`
| 項目 | 說明 |
|------|------|
| **功能** | 讀取配置檔 (忽略註解和空行) |
| **參數** | `config_file` - 配置檔路徑 |
| **輸出** | stdout, 有效配置行 |
| **失敗** | 檔案不存在時呼叫 `die()` |

#### 2.2.4 時間函數

##### `timestamp()`
| 項目 | 說明 |
|------|------|
| **功能** | 取得格式化時間戳 |
| **輸出** | `YYYY-MM-DD HH:MM:SS` |

##### `timestamp_compact()`
| 項目 | 說明 |
|------|------|
| **功能** | 取得緊湊時間戳 |
| **輸出** | `YYYYMMDD_HHMMSS` |

##### `timer_start()`
| 項目 | 說明 |
|------|------|
| **功能** | 啟動計時器 |
| **行為** | 設定全域變數 `TIMER_START` |

##### `timer_end()`
| 項目 | 說明 |
|------|------|
| **功能** | 結束計時器 |
| **輸出** | 經過秒數 (integer) |

##### `timer_format(seconds)`
| 項目 | 說明 |
|------|------|
| **功能** | 格式化秒數 |
| **參數** | `seconds` - 秒數 |
| **輸出** | `HH:MM:SS` |

#### 2.2.5 驗證函數

##### `is_valid_ip(ip)`
| 項目 | 說明 |
|------|------|
| **功能** | 驗證 IPv4 格式 |
| **參數** | `ip` - IP 位址字串 |
| **回傳** | 0=有效, 1=無效 |
| **驗證規則** | `^([0-9]{1,3}\.){3}[0-9]{1,3}$` |

##### `is_valid_domain(domain)`
| 項目 | 說明 |
|------|------|
| **功能** | 驗證網域格式 |
| **參數** | `domain` - 網域名稱 |
| **回傳** | 0=有效, 1=無效 |

#### 2.2.6 安全函數

##### `sanitize_input(input)`
| 項目 | 說明 |
|------|------|
| **功能** | 清理輸入字串中的危險字元 |
| **參數** | `input` - 原始字串 |
| **輸出** | 清理後的字串 |
| **移除字元** | `; & | $ \` < > ( )` |

### 2.3 全域常數

| 常數 | 值 | 說明 |
|------|---|------|
| `LOG_DEBUG` | 0 | DEBUG 等級 |
| `LOG_INFO` | 1 | INFO 等級 |
| `LOG_WARN` | 2 | WARN 等級 |
| `LOG_ERROR` | 3 | ERROR 等級 |
| `COLOR_*` | ANSI codes | 顏色碼 (TTY 時啟用) |

### 2.4 特殊行為

#### TTY 自動檢測
```bash
if [[ -t 2 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    # 有 TTY 且未禁用 → 啟用 ANSI 顏色
else
    # 無 TTY (如 iCall) → 禁用顏色，避免日誌亂碼
fi
```

### 2.5 限制與注意事項

| 項目 | 說明 |
|------|------|
| **執行方式** | 僅供 `source` 載入，直接執行無效果 |
| **顏色輸出** | iCall 環境自動禁用 ANSI 顏色 |
| **全域變數** | `TIMER_START` 為全域變數，注意覆蓋 |

---

## 3. check_soa.sh - SOA 版本檢查

### 3.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/check_soa.sh` |
| **程式碼行數** | 208 行 |
| **執行權限** | 一般使用者 (讀取 dnsxdump 需權限) |
| **職責** | 檢查 RPZ Zone SOA Serial 是否變更，決定是否需要處理 |

### 3.2 介面定義

#### 輸入 (Input)

| 類型 | 名稱 | 必要 | 說明 |
|------|------|:----:|------|
| **參數** | `check <zone>` | - | 檢查單一 Zone |
| **參數** | `check-all` | - | 檢查所有 Zones |
| **參數** | `get <zone>` | - | 取得 SOA Serial |
| **參數** | `reset [zone]` | - | 重置快取 |
| **環境變數** | `SOA_CACHE_DIR` | 否 | 快取目錄 (預設: `/config/snmp`) |
| **環境變數** | `DNSXDUMP_CMD` | 否 | dnsxdump 路徑 (預設: `/usr/local/bin/dnsxdump`) |
| **檔案** | `config/zonelist.txt` | 是 | Zone 清單 (check-all 時) |

#### 輸出 (Output)

| 類型 | 值 | 說明 |
|------|------|------|
| **stdout** | `UPDATE_NEEDED` | 至少一個 Zone 有更新 |
| **stdout** | `NO_UPDATE` | 所有 Zone 均無變更 |
| **stdout** | `<serial>` | get 模式時輸出 SOA Serial |
| **退出碼** | 0 | 成功 (包括 NO_UPDATE) |
| **退出碼** | 1 | 檢查失敗 |
| **退出碼** | 2 | 無法取得 SOA |

### 3.3 快取機制

#### 快取檔案格式
```
位置: ${SOA_CACHE_DIR}/.<zone>_soa_serial.last
內容: SOA Serial 數值 (純數字)
範例: /config/snmp/.rpztw_soa_serial.last
      內容: 2025012001
```

#### 快取邏輯
```
┌─────────────────────────────────────────────────────┐
│           check_zone_update_needed()                │
├─────────────────────────────────────────────────────┤
│  1. 取得當前 SOA Serial (dnsxdump)                   │
│     └─ 失敗 → return 2                              │
│                                                     │
│  2. 讀取快取 SOA Serial                              │
│     └─ 不存在 → cached = "0"                         │
│                                                     │
│  3. 首次執行檢查 (cached == "0")                     │
│     ├─ 初始化快取                                    │
│     └─ return 0 (需要更新)                           │
│                                                     │
│  4. 比較 SOA Serial                                  │
│     ├─ current <= cached → return 1 (無需更新)      │
│     └─ current > cached                             │
│         ├─ 更新快取                                  │
│         └─ return 0 (需要更新)                       │
└─────────────────────────────────────────────────────┘
```

### 3.4 處理邏輯

#### check-all 模式
```
┌─────────────────────────────────────────────────────┐
│              check_all_zones()                       │
├─────────────────────────────────────────────────────┤
│  update_needed = 0                                   │
│                                                     │
│  for zone in zonelist.txt:                          │
│      if check_zone_update_needed(zone) == 0:       │
│          update_needed = 1                          │
│                                                     │
│  if update_needed == 1:                             │
│      echo "UPDATE_NEEDED"                           │
│  else:                                              │
│      echo "NO_UPDATE"                               │
│                                                     │
│  return 0  # 永遠返回 0，避免 iCall 誤判             │
└─────────────────────────────────────────────────────┘
```

### 3.5 命令參考

| 命令 | 說明 | 範例 |
|------|------|------|
| `check <zone>` | 檢查單一 Zone 是否需更新 | `check_soa.sh check rpztw` |
| `check-all` | 檢查所有 Zones | `check_soa.sh check-all` |
| `get <zone>` | 僅取得 SOA Serial (不更新快取) | `check_soa.sh get rpztw` |
| `reset` | 重置所有 Zone 快取 | `check_soa.sh reset` |
| `reset <zone>` | 重置指定 Zone 快取 | `check_soa.sh reset rpztw` |

### 3.6 錯誤處理

| 錯誤情境 | 處理方式 | 退出碼 |
|----------|----------|:------:|
| dnsxdump 執行失敗 | log_error, return 2 | 2 |
| 無法取得 SOA Serial | log_warn, return 1 | 1 |
| zonelist.txt 不存在 | die() | 1 |
| 未知命令 | 顯示用法說明 | 1 |

### 3.7 限制與注意事項

| 項目 | 說明 |
|------|------|
| **首次執行** | 會初始化快取並返回 UPDATE_NEEDED |
| **SOA 比較** | 使用數值比較，current > cached 才觸發 |
| **退出碼設計** | check-all 永遠返回 0，透過 stdout 判斷狀態 |
| **原因** | 避免 F5 iCall scriptd 將非零退出碼視為錯誤 |

---

## 4. extract_rpz.sh - 資料提取

### 4.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/extract_rpz.sh` |
| **程式碼行數** | 87 行 |
| **執行權限** | admin / root (執行 dnsxdump) |
| **職責** | 執行 dnsxdump，匯出 DNS Express 完整資料 |

### 4.2 介面定義

#### 輸入 (Input)

| 類型 | 名稱 | 必要 | 說明 |
|------|------|:----:|------|
| **環境變數** | `OUTPUT_DIR` | 否 | 輸出目錄 (預設: `/config/snmp/rpz_datagroups`) |
| **環境變數** | `DNSXDUMP_CMD` | 否 | dnsxdump 路徑 (預設: `/usr/local/bin/dnsxdump`) |
| **環境變數** | `LOG_FILE` | 否 | 日誌檔案 (預設: `/var/log/ltm`) |

#### 輸出 (Output)

| 類型 | 位置 | 說明 |
|------|------|------|
| **檔案** | `${OUTPUT_DIR}/raw/dnsxdump_YYYYMMDD_HHMMSS.out` | dnsxdump 原始輸出 |
| **環境變數** | `DNSXDUMP_FILE` | 輸出檔案路徑 (供後續腳本使用) |
| **退出碼** | 0 | 成功 |
| **退出碼** | 1 | 失敗 |

### 4.3 處理邏輯

```
┌─────────────────────────────────────────────────────┐
│                    main()                            │
├─────────────────────────────────────────────────────┤
│  1. 建立輸出目錄                                     │
│     ensure_dir "${OUTPUT_DIR}/raw"                  │
│                                                     │
│  2. 設定輸出檔案路徑                                 │
│     file = "dnsxdump_$(timestamp_compact).out"      │
│                                                     │
│  3. 執行 dnsxdump                                    │
│     execute_dnsxdump(file)                          │
│                                                     │
│  4. 設定環境變數                                     │
│     export DNSXDUMP_FILE="$file"                    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              execute_dnsxdump()                      │
├─────────────────────────────────────────────────────┤
│  1. 檢查 dnsxdump 存在且可執行                       │
│     └─ 不存在 → return 1                            │
│                                                     │
│  2. 執行 dnsxdump > output_file                     │
│     └─ 失敗 → return 1                              │
│                                                     │
│  3. 驗證輸出檔案非空                                 │
│     └─ 空檔案 → return 1                            │
│                                                     │
│  4. 記錄行數統計                                     │
│     return 0                                         │
└─────────────────────────────────────────────────────┘
```

### 4.4 輸出格式

dnsxdump 輸出為標準 BIND Zone 檔案格式：

```
; DNS Express dump
rpztw.                  3600  IN  SOA   ns.rpz.local. admin.rpz.local. 2025012001 3600 600 86400 30
rpztw.                  3600  IN  NS    ns.rpz.local.
evil.com.rpztw.         1800  IN  A     34.102.218.71
www.evil.com.rpztw.     1800  IN  A     34.102.218.71
*.badsite.com.rpztw.    1800  IN  A     34.102.218.71
24.8.168.192.rpz-ip.rpztw.  300  IN  CNAME  rpz-ip.rpztw.
```

### 4.5 錯誤處理

| 錯誤情境 | 日誌訊息 | 退出碼 |
|----------|----------|:------:|
| dnsxdump 不存在 | `ERROR: dnsxdump command not found` | 1 |
| dnsxdump 執行失敗 | `ERROR: dnsxdump execution failed` | 1 |
| 輸出檔案為空 | `ERROR: dnsxdump output is empty` | 1 |

### 4.6 限制與注意事項

| 項目 | 說明 |
|------|------|
| **環境限制** | 僅在 F5 BIG-IP DNS 環境可用 |
| **權限需求** | 需要執行 dnsxdump 的權限 |
| **執行時間** | 取決於 DNS Express 資料量 |
| **磁碟空間** | 大型 Zone 可能產生較大檔案 |

---

## 5. parse_rpz.sh - RPZ 解析

### 5.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/parse_rpz.sh` |
| **程式碼行數** | 248 行 |
| **執行權限** | 一般使用者 |
| **職責** | 解析 dnsxdump 輸出，提取 FQDN 和 IP 類型 RPZ 記錄 |

### 5.2 介面定義

#### 輸入 (Input)

| 類型 | 名稱 | 必要 | 說明 |
|------|------|:----:|------|
| **環境變數** | `DNSXDUMP_FILE` | 否 | dnsxdump 輸出檔案 (優先使用) |
| **環境變數** | `OUTPUT_DIR` | 否 | 輸出目錄 |
| **環境變數** | `ZONELIST_FILE` | 否 | Zone 清單檔案 |
| **檔案** | `config/zonelist.txt` | 是 | Zone 清單 |
| **檔案** | `${OUTPUT_DIR}/raw/dnsxdump_*.out` | 是 | dnsxdump 輸出 (若無 DNSXDUMP_FILE) |

#### 輸出 (Output)

| 類型 | 位置 | 格式 | 說明 |
|------|------|------|------|
| **檔案** | `${OUTPUT_DIR}/parsed/<zone>_YYYYMMDD_HHMMSS.txt` | `"domain" := "ip",` | FQDN 記錄 |
| **檔案** | `${OUTPUT_DIR}/parsed/rpzip_YYYYMMDD_HHMMSS.txt` | `network ip/mask,` | IP 網段記錄 |
| **環境變數** | `PARSED_TIMESTAMP` | - | 解析時間戳 |
| **環境變數** | `PARSED_ZONES` | - | 處理的 Zone 清單 |

### 5.3 解析規則

#### 5.3.1 FQDN 記錄 (A Record)

| 原始格式 | 輸出格式 | 說明 |
|----------|----------|------|
| `evil.com.rpztw. IN A 34.102.218.71` | `"evil.com" := "34.102.218.71",` | 精確匹配 |
| `*.bad.com.rpztw. IN A 34.102.218.71` | `".bad.com" := "34.102.218.71",` | 萬用字元 |

**萬用字元轉換規則:**
- 原始: `*.example.com` → 輸出: `.example.com`
- 前綴點 (`.`) 表示萬用字元匹配
- 符合 BIND RPZ 語義

#### 5.3.2 IP 網段記錄 (rpz-ip CNAME)

| 原始格式 | 輸出格式 |
|----------|----------|
| `24.8.168.192.rpz-ip.rpztw. IN CNAME rpz-ip.rpztw.` | `network 192.168.8.0/24,` |
| `32.1.0.168.192.rpz-ip.rpztw. IN CNAME rpz-ip.rpztw.` | `network 192.168.0.1/32,` |

**IP 反轉規則:**
- 原始: `<netmask>.<octet4>.<octet3>.<octet2>.<octet1>.rpz-ip.<zone>.`
- 輸出: `network <octet1>.<octet2>.<octet3>.<octet4>/<netmask>,`

### 5.4 處理邏輯

```
┌─────────────────────────────────────────────────────────────────┐
│                         main()                                   │
├─────────────────────────────────────────────────────────────────┤
│  1. 讀取 Zone 清單                                               │
│     zones = get_zone_list()                                     │
│                                                                 │
│  2. 確定輸入檔案                                                 │
│     if DNSXDUMP_FILE exists:                                    │
│         input = DNSXDUMP_FILE                                   │
│     else:                                                       │
│         input = 最新的 dnsxdump_*.out                           │
│                                                                 │
│  3. 執行 AWK 解析                                                │
│     parse_rpz_records(input, output_dir, timestamp, zones)      │
│                                                                 │
│  4. 確保所有輸出檔案存在 (即使為空)                               │
│     for zone in zones:                                          │
│         touch ${output_dir}/${zone}_${timestamp}.txt            │
│     touch ${output_dir}/rpzip_${timestamp}.txt                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.5 AWK 解析邏輯

```
┌─────────────────────────────────────────────────────────────────┐
│                   parse_rpz_records (AWK)                        │
├─────────────────────────────────────────────────────────────────┤
│  BEGIN {                                                         │
│      解析 zone 清單，建立 zone_names[] 映射                       │
│  }                                                               │
│                                                                 │
│  主處理 {                                                        │
│      if ($3 == "IN") {                                          │
│                                                                 │
│          # A 記錄 → FQDN 黑名單                                  │
│          if ($4 == "A") {                                       │
│              for zone in zone_names:                            │
│                  if ($1 matches ".<zone>.$"):                   │
│                      移除 zone 後綴                              │
│                      if 萬用字元 (*.)：                          │
│                          key = "." + domain                     │
│                      else:                                      │
│                          key = domain                           │
│                      zone_data[zone][key] = $5 (IP)             │
│          }                                                      │
│                                                                 │
│          # CNAME + rpz-ip → IP 黑名單                           │
│          if ($4 == "CNAME") {                                   │
│              if ($1 contains "rpz-ip."):                        │
│                  解析反轉 IP 和 netmask                          │
│                  iplist[ip/mask] = 1                            │
│          }                                                      │
│      }                                                          │
│  }                                                               │
│                                                                 │
│  END {                                                           │
│      # 輸出各 zone 的 FQDN                                       │
│      for zone in zone_names:                                    │
│          for key in zone_data[zone]:                            │
│              print "\"key\" := \"ip\"," > zone_file             │
│                                                                 │
│      # 輸出 IP 網段                                              │
│      for ip in iplist:                                          │
│          print "network ip," > rpzip_file                       │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

### 5.6 錯誤處理

| 錯誤情境 | 處理方式 | 退出碼 |
|----------|----------|:------:|
| Zone 清單為空 | die() | 1 |
| zonelist.txt 不存在 | die() | 1 |
| 找不到 dnsxdump 檔案 | die() | 1 |
| AWK 解析錯誤 | 繼續執行，可能產生空檔案 | 0 |

### 5.7 限制與注意事項

| 項目 | 說明 |
|------|------|
| **效能** | 大型 Zone (>100K 記錄) AWK 處理可能耗時 |
| **記錄類型** | 僅支援 A 記錄和 rpz-ip CNAME |
| **AAAA 記錄** | 不支援 IPv6 網段轉換 |
| **Zone 名稱** | 不支援包含特殊正則字元的 Zone 名稱 |

---

## 6. generate_datagroup.sh - DataGroup 產生

### 6.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/generate_datagroup.sh` |
| **程式碼行數** | 123 行 |
| **執行權限** | 一般使用者 |
| **職責** | 將解析後的檔案整理到最終輸出目錄 |

### 6.2 介面定義

#### 輸入 (Input)

| 類型 | 名稱 | 必要 | 說明 |
|------|------|:----:|------|
| **環境變數** | `OUTPUT_DIR` | 否 | 輸出目錄 |
| **環境變數** | `ZONELIST_FILE` | 否 | Zone 清單檔案 |
| **檔案** | `config/zonelist.txt` | 是 | Zone 清單 |
| **檔案** | `${OUTPUT_DIR}/parsed/*_*.txt` | 是 | 解析後的檔案 |

#### 輸出 (Output)

| 類型 | 位置 | 說明 |
|------|------|------|
| **檔案** | `${OUTPUT_DIR}/final/<zone>.txt` | 各 Zone 的 DataGroup 檔案 |
| **檔案** | `${OUTPUT_DIR}/final/rpzip.txt` | IP 網段 DataGroup 檔案 |
| **環境變數** | `FINAL_OUTPUT_DIR` | 最終輸出目錄路徑 |
| **環境變數** | `PROCESSED_ZONES` | 處理的 Zone 清單 |

### 6.3 處理邏輯

```
┌─────────────────────────────────────────────────────┐
│           prepare_final_datagroups()                 │
├─────────────────────────────────────────────────────┤
│  1. 建立最終輸出目錄                                 │
│     ensure_dir "${OUTPUT_DIR}/final"                │
│                                                     │
│  2. 讀取 Zone 清單                                   │
│     zones = get_zone_list()                         │
│                                                     │
│  3. 處理每個 Zone                                    │
│     for zone in zones:                              │
│         parsed_file = 最新的 ${zone}_*.txt          │
│         if parsed_file 存在:                        │
│             cp parsed_file → final/${zone}.txt      │
│         else:                                       │
│             touch final/${zone}.txt                 │
│                                                     │
│  4. 處理 IP DataGroup                               │
│     if rpzip_*.txt 存在且非空:                      │
│         cp → final/rpzip.txt                        │
│     else:                                           │
│         touch final/rpzip.txt                       │
│                                                     │
│  5. 統計並輸出結果                                   │
└─────────────────────────────────────────────────────┘
```

### 6.4 檔案命名規則

| 來源檔案 | 目標檔案 | 說明 |
|----------|----------|------|
| `parsed/rpztw_20250121_143021.txt` | `final/rpztw.txt` | 最新時間戳優先 |
| `parsed/phishtw_20250121_143021.txt` | `final/phishtw.txt` | |
| `parsed/rpzip_20250121_143021.txt` | `final/rpzip.txt` | |

### 6.5 錯誤處理

| 錯誤情境 | 處理方式 | 退出碼 |
|----------|----------|:------:|
| Zone 清單為空 | die() | 1 |
| 無解析檔案 | 建立空檔案，log_debug | 0 |
| 複製失敗 | 繼續處理其他 Zone | 0 |

### 6.6 限制與注意事項

| 項目 | 說明 |
|------|------|
| **檔案選擇** | 使用 `ls -t` 取最新檔案，依賴檔案系統時間 |
| **空檔案** | 會建立空檔案，但 update_datagroup 會跳過 |
| **覆蓋行為** | 直接覆蓋 final/ 中的現有檔案 |

---

## 7. update_datagroup.sh - F5 更新

### 7.1 概述

| 項目 | 說明 |
|------|------|
| **檔案位置** | `/config/snmp/RPZ_Local_Processor/scripts/update_datagroup.sh` |
| **程式碼行數** | 203 行 |
| **執行權限** | admin / root |
| **職責** | 使用 tmsh 建立或更新 F5 External DataGroups |

### 7.2 介面定義

#### 輸入 (Input)

| 類型 | 名稱 | 必要 | 說明 |
|------|------|:----:|------|
| **環境變數** | `OUTPUT_DIR` | 否 | 輸出目錄 |
| **環境變數** | `LOG_FILE` | 否 | 日誌檔案 |
| **環境變數** | `ZONELIST_FILE` | 否 | Zone 清單檔案 |
| **檔案** | `config/zonelist.txt` | 是 | Zone 清單 |
| **檔案** | `${OUTPUT_DIR}/final/*.txt` | 是 | DataGroup 檔案 |

#### 輸出 (Output)

| 類型 | 說明 |
|------|------|
| **F5 DataGroup** | 建立或更新 External DataGroups |
| **F5 Config** | 執行 `tmsh save sys config` |
| **日誌** | 寫入 /var/log/ltm |

### 7.3 處理邏輯

```
┌─────────────────────────────────────────────────────────────────┐
│                    update_all_datagroups()                       │
├─────────────────────────────────────────────────────────────────┤
│  1. 讀取 Zone 清單                                               │
│     zones = get_zone_list()                                     │
│                                                                 │
│  2. 處理每個 Zone                                                │
│     for zone in zones:                                          │
│         source_file = "${FINAL_OUTPUT_DIR}/${zone}.txt"         │
│         if file 存在且非空:                                      │
│             update_single_datagroup(zone, source_file)          │
│         else:                                                   │
│             skip (log_debug)                                    │
│                                                                 │
│  3. 處理 IP DataGroup                                           │
│     if rpzip.txt 存在且非空:                                    │
│         update_single_datagroup("rpzip", rpzip.txt)             │
│                                                                 │
│  4. 儲存配置 (如果有成功更新)                                     │
│     if success_count > 0:                                       │
│         tmsh save sys config                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  update_single_datagroup()                       │
├─────────────────────────────────────────────────────────────────┤
│  1. 檢查來源檔案                                                 │
│     └─ 不存在 → return 1                                        │
│     └─ 為空 → return 0 (跳過)                                   │
│                                                                 │
│  2. 檢查 DataGroup 是否存在                                      │
│     if datagroup_exists(name):                                  │
│         # 更新                                                   │
│         tmsh modify ltm data-group external $name \             │
│             source-path file:$source_file                       │
│     else:                                                       │
│         # 建立                                                   │
│         tmsh create ltm data-group external $name \             │
│             source-path file:$source_file \                     │
│             type string                                         │
│                                                                 │
│  3. 記錄結果                                                     │
│     return 0 (成功) / 1 (失敗)                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.4 tmsh 指令

#### 建立 DataGroup
```bash
tmsh create ltm data-group external <name> \
    source-path file:<path> \
    type string
```

#### 更新 DataGroup
```bash
tmsh modify ltm data-group external <name> \
    source-path file:<path>
```

#### 檢查存在性
```bash
tmsh list ltm data-group external <name>
# 退出碼 0 = 存在, 非 0 = 不存在
```

#### 儲存配置
```bash
tmsh save sys config
```

### 7.5 錯誤處理

| 錯誤情境 | 處理方式 | 日誌訊息 |
|----------|----------|----------|
| 來源檔案不存在 | return 1 | `ERROR: source file not found` |
| DataGroup 建立失敗 | return 1 | `ERROR: failed to create DataGroup` |
| DataGroup 更新失敗 | return 1 | `ERROR: failed to update DataGroup` |
| 配置儲存失敗 | log_warn | `WARN: 配置儲存失敗` |

### 7.6 統計輸出

```
=== 更新完成 ===
成功: 2 個, 失敗: 0 個, 跳過: 1 個
```

### 7.7 限制與注意事項

| 項目 | 說明 |
|------|------|
| **權限** | 需要 admin/root 權限執行 tmsh |
| **DataGroup 類型** | 固定為 `string` (字典型) |
| **空檔案** | 會跳過，不建立空的 DataGroup |
| **原子性** | 每個 DataGroup 獨立更新，部分失敗不影響其他 |
| **配置儲存** | 僅在有成功更新時才儲存配置 |

---

## 附錄 A: 腳本依賴關係圖

```
                    ┌─────────────┐
                    │   main.sh   │
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  │
┌───────────────┐  ┌───────────────┐         │
│   utils.sh    │  │ check_soa.sh  │         │
│   (source)    │  │   (步驟 1)    │         │
└───────────────┘  └───────────────┘         │
        │                                     │
        │          ┌───────────────┐         │
        └─────────►│ extract_rpz   │◄────────┤
                   │   (步驟 2)    │         │
                   └───────────────┘         │
                           │                  │
                           ▼                  │
                   ┌───────────────┐         │
                   │  parse_rpz    │◄────────┤
                   │   (步驟 3)    │         │
                   └───────────────┘         │
                           │                  │
                           ▼                  │
                   ┌───────────────┐         │
                   │  generate_dg  │◄────────┤
                   │   (步驟 4)    │         │
                   └───────────────┘         │
                           │                  │
                           ▼                  │
                   ┌───────────────┐         │
                   │  update_dg    │◄────────┘
                   │   (步驟 5)    │
                   └───────────────┘
```

---

## 附錄 B: 退出碼總表

| 腳本 | 退出碼 | 說明 |
|------|:------:|------|
| **main.sh** | 0 | 成功 / 無需更新 |
| | 1 | 任一步驟失敗 |
| **check_soa.sh** | 0 | 成功 (含 NO_UPDATE) |
| | 1 | 檢查失敗 |
| | 2 | 無法取得 SOA |
| **extract_rpz.sh** | 0 | 成功 |
| | 1 | dnsxdump 失敗 |
| **parse_rpz.sh** | 0 | 成功 |
| | 1 | Zone 清單或輸入檔案問題 |
| **generate_datagroup.sh** | 0 | 成功 |
| | 1 | Zone 清單問題 |
| **update_datagroup.sh** | 0 | 成功 |
| | N | N 個 DataGroup 更新失敗 |

---

## 附錄 C: 環境變數總表

| 變數 | 預設值 | 使用腳本 | 說明 |
|------|--------|----------|------|
| `OUTPUT_DIR` | `/config/snmp/rpz_datagroups` | 全部 | 輸出目錄 |
| `LOG_FILE` | `/var/log/ltm` | main, extract, update | 系統日誌 |
| `LOG_LEVEL` | `1` | 全部 (via utils) | 日誌等級 |
| `DNSXDUMP_CMD` | `/usr/local/bin/dnsxdump` | check_soa, extract | dnsxdump 路徑 |
| `SOA_CACHE_DIR` | `/config/snmp` | check_soa | SOA 快取目錄 |
| `ZONELIST_FILE` | `${PROJECT_ROOT}/config/zonelist.txt` | parse, generate, update | Zone 清單 |
| `CLEANUP_TEMP` | `true` | main | 是否清理臨時檔 |
| `FORCE_RUN` | `false` | main | 強制執行 |
| `NO_COLOR` | - | utils | 禁用顏色輸出 |
| `DNSXDUMP_FILE` | - | parse | dnsxdump 輸出檔案 |
| `PARSED_TIMESTAMP` | - | parse → generate | 解析時間戳 |
| `PARSED_ZONES` | - | parse → generate | 處理的 Zone |
| `FINAL_OUTPUT_DIR` | - | generate → update | 最終輸出目錄 |
| `PROCESSED_ZONES` | - | generate → update | 處理的 Zone |

---

**文件結束**
