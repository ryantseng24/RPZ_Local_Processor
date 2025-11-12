# RPZ Local Processor - 完整清理指南

## 📋 概述

本文檔提供完整的清理指令，用於徹底移除 F5 設備上的 RPZ Local Processor 相關配置與檔案。

---

## 🚀 快速清理（推薦）

### 方式 1: 使用自動化清理腳本

```bash
# 從本地執行（自動 SSH 到 F5）
sshpass -p '<password>' scp -o StrictHostKeyChecking=no cleanup.sh admin@<F5_IP>:/var/tmp/
sshpass -p '<password>' ssh -o StrictHostKeyChecking=no admin@<F5_IP> "bash /var/tmp/cleanup.sh"

# 或直接在 F5 上執行
ssh admin@<F5_IP>
bash /var/tmp/cleanup.sh
```

### 方式 2: 一鍵清理指令

```bash
# SSH 到 F5 後執行
ssh admin@<F5_IP>

# 複製整段執行
bash << 'EOF'
# 停用並刪除 iCall
tmsh modify sys icall handler periodic rpz_processor_handler status inactive 2>/dev/null || true
sleep 2
tmsh delete sys icall handler periodic rpz_processor_handler 2>/dev/null || true
tmsh delete sys icall script rpz_processor_script 2>/dev/null || true

# 刪除 DataGroups
tmsh delete ltm data-group external rpztw 2>/dev/null || true
tmsh delete ltm data-group external phishtw 2>/dev/null || true
tmsh delete ltm data-group external rpzip 2>/dev/null || true
tmsh delete sys file data-group rpztw 2>/dev/null || true
tmsh delete sys file data-group phishtw 2>/dev/null || true
tmsh delete sys file data-group rpzip 2>/dev/null || true

# 儲存配置
tmsh save sys config

# 刪除檔案與目錄
rm -rf /var/tmp/RPZ_Local_Processor
rm -rf /var/tmp/rpz_datagroups
rm -f /var/tmp/rpz_wrapper.sh
rm -f /var/tmp/rpz_wrapper.log
rm -f /var/tmp/RPZ_Local_Processor.tar.gz

echo "清理完成！"
EOF
```

---

## 📝 詳細清理步驟

### 步驟 1: 停用並刪除 iCall 配置

#### 1.1 停用 iCall Handler（避免執行中被刪除）
```bash
tmsh modify sys icall handler periodic rpz_processor_handler status inactive
```

**說明**: 將 Handler 設為 inactive，停止自動執行

#### 1.2 等待執行中的任務完成
```bash
sleep 2
```

**說明**: 等待 2 秒，確保正在執行的腳本完成

#### 1.3 刪除 iCall Handler
```bash
tmsh delete sys icall handler periodic rpz_processor_handler
```

**刪除項目**:
- Handler 名稱: `rpz_processor_handler`
- 類型: periodic handler
- 配置位置: `/config/bigip.conf`

#### 1.4 刪除 iCall Script
```bash
tmsh delete sys icall script rpz_processor_script
```

**刪除項目**:
- Script 名稱: `rpz_processor_script`
- 類型: icall script
- 配置位置: `/config/bigip.conf`

#### 1.5 儲存配置
```bash
tmsh save sys config
```

---

### 步驟 2: 刪除 DataGroups

#### 2.1 刪除 External DataGroups

```bash
# 刪除 rpztw
tmsh delete ltm data-group external rpztw

# 刪除 phishtw
tmsh delete ltm data-group external phishtw

# 刪除 rpzip (如果有)
tmsh delete ltm data-group external rpzip
```

**刪除項目**:
| DataGroup 名稱 | 類型 | 用途 |
|---------------|------|------|
| `rpztw` | external string | RPZ 主要黑名單 |
| `phishtw` | external string | Phishing 黑名單 |
| `rpzip` | external ip | IP 網段黑名單 |

#### 2.2 刪除 DataGroup Files

```bash
# 刪除 rpztw file
tmsh delete sys file data-group rpztw

# 刪除 phishtw file
tmsh delete sys file data-group phishtw

# 刪除 rpzip file
tmsh delete sys file data-group rpzip
```

**刪除項目**:
| File 名稱 | 大小 | 位置 |
|-----------|------|------|
| `rpztw` | ~2.2 MB | F5 內部儲存 |
| `phishtw` | ~31 KB | F5 內部儲存 |
| `rpzip` | ~0 KB | F5 內部儲存 |

#### 2.3 儲存配置
```bash
tmsh save sys config
```

---

### 步驟 3: 刪除專案目錄

#### 3.1 刪除主專案目錄
```bash
rm -rf /var/tmp/RPZ_Local_Processor
```

**刪除內容**:
```
/var/tmp/RPZ_Local_Processor/
├── scripts/                    # 所有執行腳本
│   ├── main.sh
│   ├── check_soa.sh
│   ├── extract_rpz.sh
│   ├── parse_rpz.sh
│   ├── generate_datagroup.sh
│   └── update_datagroup.sh
├── config/                     # 配置檔案
│   ├── icall_setup.sh
│   └── icall_setup_api.sh
├── logs/                       # 執行日誌（如有）
└── install.sh                  # 安裝腳本
```

**目錄大小**: 約 100-200 KB

---

### 步驟 4: 刪除輸出目錄

#### 4.1 刪除 DataGroup 輸出目錄
```bash
rm -rf /var/tmp/rpz_datagroups
```

**刪除內容**:
```
/var/tmp/rpz_datagroups/
├── raw/                        # dnsxdump 原始輸出
│   └── dnsxdump_*.out         # ~5 MB per file
├── parsed/                     # AWK 解析後的檔案
│   ├── rpz_*.txt              # ~2.2 MB per file
│   ├── phishtw_*.txt          # ~31 KB per file
│   └── ip_*.txt               # ~0 KB
├── final/                      # 最終 DataGroup 檔案
│   ├── rpz.txt                # ~2.2 MB
│   ├── phishtw.txt            # ~31 KB
│   └── rpzip.txt              # ~0 KB
└── .soa_cache/                 # SOA Serial 快取
    ├── rpztw.soa              # 幾個 bytes
    └── phishtw.soa            # 幾個 bytes
```

**目錄大小**: 約 10-20 MB（取決於保留的歷史檔案數量）

#### 4.2 檢查磁碟空間釋放
```bash
# 刪除前查看大小
du -sh /var/tmp/rpz_datagroups

# 刪除後驗證
ls -ld /var/tmp/rpz_datagroups  # 應該不存在
```

---

### 步驟 5: 刪除 Wrapper 相關檔案

#### 5.1 刪除 Wrapper Script
```bash
rm -f /var/tmp/rpz_wrapper.sh
```

**刪除項目**:
- 檔案路徑: `/var/tmp/rpz_wrapper.sh`
- 檔案大小: ~234 bytes
- 用途: iCall 執行的包裝腳本

**檔案內容**:
```bash
#!/bin/bash
{
    echo "=== $(date) - Wrapper Start ==="
    bash /var/tmp/RPZ_Local_Processor/scripts/main.sh
    exit_code=$?
    echo "=== $(date) - Exit Code: $exit_code ==="
    exit $exit_code
} >> /var/tmp/rpz_wrapper.log 2>&1
```

#### 5.2 刪除 Wrapper Log
```bash
rm -f /var/tmp/rpz_wrapper.log
```

**刪除項目**:
- 檔案路徑: `/var/tmp/rpz_wrapper.log`
- 檔案大小: 1-10 KB（取決於執行次數）
- 用途: 記錄 iCall 的執行歷史

**Log 內容範例**:
```
=== Wed Nov 12 22:47:38 CST 2025 - Wrapper Start ===
[INFO] 步驟 1/5: 檢查 RPZ Zone SOA Serial
[INFO] SOA Serial 未變更，無需更新
=== Wed Nov 12 22:47:39 CST 2025 - Exit Code: 0 ===
```

---

### 步驟 6: 刪除部署套件

#### 6.1 刪除 tar.gz 套件
```bash
rm -f /var/tmp/RPZ_Local_Processor.tar.gz
```

**刪除項目**:
- 檔案路徑: `/var/tmp/RPZ_Local_Processor.tar.gz`
- 檔案大小: ~50-100 KB（壓縮後）
- 用途: deploy.sh 上傳的部署套件

---

### 步驟 7: 驗證清理結果

#### 7.1 檢查 iCall 配置
```bash
# 列出所有 periodic handler
tmsh list sys icall handler periodic

# 檢查是否還有 rpz 相關的 handler
tmsh list sys icall handler periodic | grep -i rpz

# 列出所有 icall script
tmsh list sys icall script

# 檢查是否還有 rpz 相關的 script
tmsh list sys icall script | grep -i rpz
```

**預期結果**: 不應該看到任何 `rpz_processor` 相關的配置

#### 7.2 檢查 DataGroups
```bash
# 列出所有 external data-groups
tmsh list ltm data-group external

# 檢查 rpz 相關的 data-groups
tmsh list ltm data-group external | grep -E "rpztw|phishtw|rpzip"

# 列出所有 data-group files
tmsh list sys file data-group

# 檢查 rpz 相關的 files
tmsh list sys file data-group | grep -E "rpztw|phishtw|rpzip"
```

**預期結果**: 不應該看到 `rpztw`, `phishtw`, `rpzip` 相關的項目

**注意**: 可能會看到舊架構的 DataGroup（如 `rpztw_34_102_218_71`），這些是不同的專案，不需要刪除

#### 7.3 檢查檔案系統
```bash
# 檢查專案目錄
ls -ld /var/tmp/RPZ_Local_Processor

# 檢查輸出目錄
ls -ld /var/tmp/rpz_datagroups

# 檢查 wrapper 檔案
ls -l /var/tmp/rpz_wrapper.*

# 檢查部署套件
ls -l /var/tmp/RPZ_Local_Processor.tar.gz
```

**預期結果**: 所有指令應該回傳 "No such file or directory"

#### 7.4 完整驗證命令
```bash
echo "=== 驗證清理結果 ==="
echo ""
echo "iCall Handler:"
tmsh list sys icall handler periodic 2>/dev/null | grep -c "rpz_processor" || echo "✓ 已清理"
echo ""
echo "iCall Script:"
tmsh list sys icall script 2>/dev/null | grep -c "rpz_processor" || echo "✓ 已清理"
echo ""
echo "External DataGroups:"
tmsh list ltm data-group external 2>/dev/null | grep -E "rpztw|phishtw|rpzip" | wc -l
echo ""
echo "DataGroup Files:"
tmsh list sys file data-group 2>/dev/null | grep -E "rpztw|phishtw|rpzip" | wc -l
echo ""
echo "專案目錄:"
ls -ld /var/tmp/RPZ_Local_Processor 2>/dev/null || echo "✓ 已刪除"
echo ""
echo "輸出目錄:"
ls -ld /var/tmp/rpz_datagroups 2>/dev/null || echo "✓ 已刪除"
echo ""
echo "Wrapper 檔案:"
ls -l /var/tmp/rpz_wrapper.* 2>/dev/null || echo "✓ 已刪除"
echo ""
```

---

## 📊 清理檢查清單

### 配置項目清單

| 項目類型 | 項目名稱 | 刪除指令 | 狀態 |
|---------|---------|---------|------|
| **iCall Handler** | rpz_processor_handler | `tmsh delete sys icall handler periodic rpz_processor_handler` | [ ] |
| **iCall Script** | rpz_processor_script | `tmsh delete sys icall script rpz_processor_script` | [ ] |
| **External DG** | rpztw | `tmsh delete ltm data-group external rpztw` | [ ] |
| **External DG** | phishtw | `tmsh delete ltm data-group external phishtw` | [ ] |
| **External DG** | rpzip | `tmsh delete ltm data-group external rpzip` | [ ] |
| **DG File** | rpztw | `tmsh delete sys file data-group rpztw` | [ ] |
| **DG File** | phishtw | `tmsh delete sys file data-group phishtw` | [ ] |
| **DG File** | rpzip | `tmsh delete sys file data-group rpzip` | [ ] |

### 檔案系統清單

| 項目類型 | 路徑 | 大小估計 | 刪除指令 | 狀態 |
|---------|------|---------|---------|------|
| **專案目錄** | /var/tmp/RPZ_Local_Processor | ~200 KB | `rm -rf /var/tmp/RPZ_Local_Processor` | [ ] |
| **輸出目錄** | /var/tmp/rpz_datagroups | ~15 MB | `rm -rf /var/tmp/rpz_datagroups` | [ ] |
| **Wrapper Script** | /var/tmp/rpz_wrapper.sh | ~234 bytes | `rm -f /var/tmp/rpz_wrapper.sh` | [ ] |
| **Wrapper Log** | /var/tmp/rpz_wrapper.log | ~5 KB | `rm -f /var/tmp/rpz_wrapper.log` | [ ] |
| **部署套件** | /var/tmp/RPZ_Local_Processor.tar.gz | ~80 KB | `rm -f /var/tmp/RPZ_Local_Processor.tar.gz` | [ ] |

### 子目錄詳細清單

#### /var/tmp/RPZ_Local_Processor/ 內容
```
scripts/
├── main.sh                     # 主腳本
├── check_soa.sh               # SOA 檢查
├── extract_rpz.sh             # 資料提取
├── parse_rpz.sh               # 記錄解析
├── generate_datagroup.sh      # DataGroup 生成
└── update_datagroup.sh        # F5 更新

config/
├── icall_setup.sh             # tmsh 版本
└── icall_setup_api.sh         # REST API 版本

logs/                          # (可能存在)
install.sh                     # 安裝腳本
```

#### /var/tmp/rpz_datagroups/ 內容
```
raw/
├── dnsxdump_20251112_*.out    # 每個 ~5 MB

parsed/
├── rpz_20251112_*.txt         # 每個 ~2.2 MB
├── phishtw_20251112_*.txt     # 每個 ~31 KB
└── ip_20251112_*.txt          # 每個 ~0 KB

final/
├── rpz.txt                    # ~2.2 MB
├── phishtw.txt                # ~31 KB
└── rpzip.txt                  # ~0 KB

.soa_cache/
├── rpztw.soa                  # 幾 bytes
└── phishtw.soa                # 幾 bytes
```

---

## ⚠️ 注意事項

### 1. 配置備份
在清理前，建議備份 F5 配置：
```bash
tmsh save sys ucs /var/local/ucs/backup_before_cleanup.ucs
```

### 2. iRule 影響
如果有 iRule 引用這些 DataGroup，刪除後會導致 iRule 錯誤：
```tcl
# 這些 iRule 會受影響
class match $query_name ends_with rpztw     # ← rpztw 被刪除
class match $query_name ends_with phishtw   # ← phishtw 被刪除
```

**解決方案**:
- 先停用或修改相關的 iRule
- 或保留 DataGroup 但清空內容

### 3. 執行中的任務
刪除 iCall 前確保沒有任務正在執行：
```bash
# 檢查系統 CPU 使用率
top -b -n 1 | grep "main.sh"

# 檢查最近的執行
tail -5 /var/tmp/rpz_wrapper.log
```

### 4. 磁碟空間
清理後會釋放約 15-20 MB 的磁碟空間。

### 5. 舊架構 DataGroup
如果 F5 上同時存在舊架構的 DataGroup（如 `rpztw_34_102_218_71`），它們不會被此清理程序刪除。如需清理，請參考舊專案的清理指南。

---

## 🔄 重新部署

清理完成後，可以重新部署：

```bash
# 從本地執行
bash deploy.sh <F5_IP> [password]

# 或使用 SSH
ssh admin@<F5_IP>
# 上傳套件後執行 install.sh
```

---

## 📞 故障排除

### 問題 1: 無法刪除 iCall Handler
```
01070734:3: Configuration error: Cannot delete handler periodic rpz_processor_handler
```

**解決**:
```bash
# 先停用
tmsh modify sys icall handler periodic rpz_processor_handler status inactive
sleep 5
# 再刪除
tmsh delete sys icall handler periodic rpz_processor_handler
```

### 問題 2: DataGroup 正在使用中
```
01020036:3: The requested Data Group (/Common/rpztw) is referenced by a configuration object
```

**解決**:
```bash
# 找出引用的 iRule
tmsh list ltm rule all | grep -B 5 rpztw

# 停用或修改 iRule 後再刪除
```

### 問題 3: 目錄無法刪除（權限問題）
```
rm: cannot remove '/var/tmp/RPZ_Local_Processor': Permission denied
```

**解決**:
```bash
# 使用 sudo（如果有權限）
sudo rm -rf /var/tmp/RPZ_Local_Processor

# 或檢查目錄權限
ls -ld /var/tmp/RPZ_Local_Processor
```

---

## 📚 相關文檔

- **DEPLOYMENT_SOP.md** - 部署標準作業程序
- **DEPLOYMENT_GUIDE.md** - 詳細部署指南
- **cleanup.sh** - 自動化清理腳本

---

**最後更新**: 2025-11-12
**維護者**: DevOps Team
