# RPZ Local Processor - 部署標準作業程序 (SOP)

## 📋 文件資訊

- **版本**: 2.0
- **最後驗證日期**: 2025-11-12
- **驗證環境**: 10.8.34.22 (Clean LAB)
- **部署方式**: 自動化 (deploy.sh)
- **維護者**: DevOps Team

---

## 🎯 部署概述

本 SOP 提供 RPZ Local Processor 的自動化部署流程，適用於新的 F5 BIG-IP 設備或乾淨的 LAB 環境。

### 核心優勢
- ✅ **全自動化**: 一行指令完成上傳、安裝、驗證
- ✅ **已驗證**: 在乾淨環境 (10.8.34.22) 完整測試通過
- ✅ **零依賴**: 只需 sshpass、ssh、scp、tar (Mac/Linux 標準工具)
- ⏱️ **快速部署**: 完整部署流程 < 5 分鐘

### 前置條件
| 項目 | 要求 | 驗證方式 |
|------|------|----------|
| F5 設備 | BIG-IP with DNS Express | `tmsh show sys version` |
| 網路連線 | SSH (port 22) 可達 | `ping <F5_IP>` |
| 本地工具 | sshpass, ssh, scp, tar | `which sshpass ssh scp tar` |
| F5 權限 | admin 帳號 | - |
| DNS Express | 已啟用並有 RPZ Zone 資料 | `tmsh show ltm dns zone` |

---

## 🚀 部署流程

### Phase 1: 部署前檢查 (5 分鐘)

#### 1.1 本地環境檢查
```bash
# 檢查必要工具
which sshpass ssh scp tar

# 如果缺少 sshpass (macOS):
brew install hudochenkov/sshpass/sshpass
```

#### 1.2 確認 F5 設備狀態
```bash
# 測試 SSH 連線
sshpass -p '<password>' ssh -o StrictHostKeyChecking=no admin@<F5_IP> "echo connected"

# 檢查 DNS Express
sshpass -p '<password>' ssh admin@<F5_IP> "tmsh show ltm dns zone"

# 檢查 dnsxdump 指令
sshpass -p '<password>' ssh admin@<F5_IP> "/usr/local/bin/dnsxdump | head -5"
```

**預期結果**:
- ✅ SSH 連線成功
- ✅ 至少有一個 RPZ Zone (例如: rpztw, phishtw)
- ✅ dnsxdump 輸出 DNS 記錄

---

### Phase 2: 自動化部署 (3 分鐘)

#### 2.1 執行部署腳本

```bash
# 基本部署 (使用預設密碼 uniforce)
cd /Users/ryan/project/RPZ_Local_Processor
bash deploy.sh <F5_IP>

# 自訂密碼
bash deploy.sh <F5_IP> <password>
```

**腳本自動執行步驟**:
1. ✅ 檢查本地環境 (sshpass, ssh, scp, tar)
2. ✅ 測試 F5 連線
3. ✅ 建立部署套件 (tar.gz)
4. ✅ 上傳到 F5 `/var/tmp/`
5. ✅ 解壓到 `/var/tmp/RPZ_Local_Processor/`
6. ✅ 執行 `install.sh` (建立目錄、設定權限)
7. ✅ 驗證腳本可執行性
8. ✅ 詢問是否設定 iCall (可選)

#### 2.2 部署過程輸出範例

```
==========================================
  RPZ Local Processor 自動部署
==========================================

[INFO] 檢查本地環境...
✓ 本地環境檢查通過
[INFO] 測試 F5 連線...
✓ F5 連線測試通過
[INFO] 建立部署套件: /var/folders/.../RPZ_Local_Processor.tar.gz
[INFO] 上傳部署套件到 F5...
✓ 上傳完成
[INFO] 在 F5 上部署...
→ 解壓部署套件
→ 執行安裝腳本
==========================================
  RPZ Local Processor 安裝程式
==========================================

[1/4] 檢查系統環境...
  ✓ bash
  ✓ awk
  ✓ sed

[2/4] 建立輸出目錄...
  ✓ /var/tmp/rpz_datagroups

[3/4] 設定執行權限...
  ✓ scripts/*.sh

[4/4] 檢查 F5 環境...
  ✓ tmsh 指令可用
  ✓ dnsxdump 指令可用

==========================================
  安裝完成！
==========================================
✓ 部署完成
[INFO] 驗證部署...
→ 檢查主腳本
→ 檢查輸出目錄
→ 測試執行主腳本...
  執行測試
✓ 測試執行成功
✓ 基本驗證通過
```

---

### Phase 3: 手動配置 (2 分鐘)

#### 3.1 建立 External DataGroups

**⚠️ 重要**: 在乾淨環境中，必須先建立 DataGroups 才能執行更新。

```bash
# SSH 登入 F5
ssh admin@<F5_IP>

# 建立 DataGroups
tmsh create ltm data-group external rpztw \
  source-path file:/var/tmp/rpz_datagroups/final/rpz.txt \
  type string

tmsh create ltm data-group external phishtw \
  source-path file:/var/tmp/rpz_datagroups/final/phishtw.txt \
  type string

# 儲存配置
tmsh save sys config

# 驗證建立成功
tmsh list ltm data-group external rpztw
tmsh list ltm data-group external phishtw
```

#### 3.2 首次執行腳本

```bash
# 強制執行 (跳過 SOA 檢查，因為是首次)
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force --verbose

# 檢查執行結果
ls -lh /var/tmp/rpz_datagroups/final/
# 預期看到:
# - rpz.txt (約 58,610 筆)
# - phishtw.txt (約 821 筆)
```

**預期輸出**:
```
[2025-11-12 14:30:15] INFO: Starting RPZ processing (FORCED mode)
[2025-11-12 14:30:15] INFO: Extracting DNS Express data for all zones
[2025-11-12 14:30:16] INFO: Parsing RPZ records
[2025-11-12 14:30:16] INFO: Processing rpztw zone
[2025-11-12 14:30:16] INFO: Parsed 58610 records for rpztw
[2025-11-12 14:30:16] INFO: Processing phishtw zone
[2025-11-12 14:30:16] INFO: Parsed 821 records for phishtw
[2025-11-12 14:30:16] INFO: Generating final DataGroup files
[2025-11-12 14:30:16] INFO: Updating F5 DataGroups
[2025-11-12 14:30:17] INFO: RPZ processing completed successfully
```

#### 3.3 設定 iCall 自動執行

**方式 A: 手動配置 (推薦 - 更可靠)**

```bash
# 步驟 1: 建立 wrapper script (用於除錯)
cat > /var/tmp/rpz_wrapper.sh << 'EOF'
#!/bin/bash
{
    echo "=== $(date) - Wrapper Start ==="
    bash /var/tmp/RPZ_Local_Processor/scripts/main.sh
    exit_code=$?
    echo "=== $(date) - Exit Code: $exit_code ==="
    exit $exit_code
} >> /var/tmp/rpz_wrapper.log 2>&1
EOF

chmod +x /var/tmp/rpz_wrapper.sh

# 步驟 2: 建立 iCall script
tmsh create sys icall script rpz_processor_script definition \{
    exec bash /var/tmp/rpz_wrapper.sh
\}

# 步驟 3: 建立 iCall handler (每 5 分鐘)
tmsh create sys icall handler periodic rpz_processor_handler \
    interval 300 \
    script rpz_processor_script

# 步驟 4: 儲存配置
tmsh save sys config

# 步驟 5: 驗證配置
tmsh list sys icall handler periodic rpz_processor_handler
tmsh list sys icall script rpz_processor_script
```

**方式 B: 使用自動化腳本 (已知限制)**

```bash
# 嘗試使用自動化腳本
bash /var/tmp/RPZ_Local_Processor/config/icall_setup.sh

# ⚠️ 注意: tmsh 遠端執行可能有 brace escaping 問題
# 如果失敗，請使用方式 A 手動配置
```

---

### Phase 4: 部署後驗證 (2 分鐘)

#### 4.1 檢查檔案結構

```bash
# 檢查專案目錄
ls -lh /var/tmp/RPZ_Local_Processor/
# 預期:
# - scripts/       (所有 .sh 腳本)
# - config/        (配置檔案)
# - install.sh

# 檢查輸出目錄
ls -lh /var/tmp/rpz_datagroups/
# 預期:
# - raw/           (dnsxdump 原始輸出)
# - parsed/        (時間戳檔名)
# - final/         (固定檔名: rpz.txt, phishtw.txt)
# - .soa_cache/    (SOA Serial 快取)
```

#### 4.2 檢查 DataGroup 狀態

```bash
# 查看 DataGroup 記錄數
tmsh list ltm data-group external rpztw | grep records
tmsh list ltm data-group external phishtw | grep records

# 查看實際內容 (前 10 筆)
head -10 /var/tmp/rpz_datagroups/final/rpz.txt
head -10 /var/tmp/rpz_datagroups/final/phishtw.txt
```

**預期格式**:
```
"malicious.com" := "34.102.218.71",
"phishing.net" := "182.173.0.181",
".evil.org" := "210.64.24.25",
```

#### 4.3 檢查 iCall 執行狀態

```bash
# 查看 iCall handler 狀態
tmsh show sys icall handler periodic rpz_processor_handler

# 查看 wrapper log (如果有設定)
tail -20 /var/tmp/rpz_wrapper.log

# 查看系統日誌
tail -50 /var/log/ltm | grep RPZ
```

#### 4.4 測試手動執行

```bash
# 正常模式 (有 SOA 檢查)
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh

# 預期輸出 (如果 SOA 未變):
# INFO: RPZ SOA not changed, skip update

# 強制模式 (跳過 SOA 檢查)
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force

# 預期輸出:
# INFO: RPZ processing completed successfully
```

---

## ✅ 部署檢查清單

### 部署前
- [ ] F5 設備可 SSH 連線
- [ ] DNS Express 已啟用並有 RPZ Zone
- [ ] dnsxdump 指令可用
- [ ] 本地有 sshpass, ssh, scp, tar 工具

### 部署中
- [ ] deploy.sh 執行成功
- [ ] 檔案上傳到 `/var/tmp/RPZ_Local_Processor/`
- [ ] install.sh 建立目錄結構
- [ ] 腳本有執行權限

### 部署後
- [ ] DataGroups 已建立 (rpztw, phishtw)
- [ ] 首次手動執行成功
- [ ] 生成 final/rpz.txt 和 final/phishtw.txt
- [ ] 記錄數正確 (rpztw: ~58,610, phishtw: ~821)
- [ ] iCall 已設定並運行
- [ ] wrapper log 有正常輸出
- [ ] tmsh 可查詢 DataGroup 內容

---

## 🐛 故障排除

### 問題 1: deploy.sh 上傳失敗

**症狀**:
```
scp: stat local "...": No such file or directory
```

**原因**: create_package() 函數 stdout/stderr 混淆

**解決**:
```bash
# 確認 deploy.sh 版本是最新的
grep ">&2" deploy.sh | grep "建立部署套件"
# 應該看到: echo "[INFO] 建立部署套件: $package" >&2
```

### 問題 2: 首次執行失敗 - DataGroup 不存在

**症狀**:
```
01020036:3: The requested value list (/Common/rpztw) was not found.
```

**原因**: 乾淨環境未建立 DataGroup

**解決**:
```bash
# 建立 DataGroup
tmsh create ltm data-group external rpztw \
  source-path file:/var/tmp/rpz_datagroups/final/rpz.txt \
  type string

tmsh create ltm data-group external phishtw \
  source-path file:/var/tmp/rpz_datagroups/final/phishtw.txt \
  type string

tmsh save sys config
```

### 問題 3: iCall 遠端設定失敗

**症狀**:
```
Syntax Error: "definition" can't parse script: missing close-brace line:0
```

**原因**: tmsh brace escaping 在遠端 SSH 不可靠

**解決**:
```bash
# 使用方式 A: 手動在 F5 上執行
ssh admin@<F5_IP>

# 手動建立 wrapper script 和 iCall
# (參考 Phase 3: 方式 A)
```

### 問題 4: dnsxdump 無輸出

**症狀**:
```
[ERROR] dnsxdump failed or empty output
```

**原因**: DNS Express 無資料或未啟用

**解決**:
```bash
# 檢查 DNS Express Zone
tmsh show ltm dns zone

# 檢查 Zone Transfer 狀態
tmsh show ltm dns zone rpztw.

# 手動觸發 Zone Transfer (如果需要)
tmsh modify ltm dns zone rpztw. transfer-source <master_dns_ip>
```

### 問題 5: SOA 檢查一直顯示「未變更」

**症狀**:
```
INFO: RPZ SOA not changed, skip update
```

**原因**: DNS Express Zone 確實沒有更新 (正常行為)

**解決**:
```bash
# 如果需要強制更新
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force

# 或檢查 SOA Serial
bash /var/tmp/RPZ_Local_Processor/scripts/check_soa.sh get rpztw.
cat /var/tmp/rpz_datagroups/.soa_cache/rpztw.soa
```

### 問題 6: 記錄數與 Infoblox 不一致

**症狀**: Infoblox 58,612 筆，F5 DataGroup 58,610 筆 (差 2 筆)

**原因**: 某些 domain 在 Infoblox 有多個 Landing IP (Round-Robin)，F5 DataGroup 只保留最後一個

**解決**: 這是預期行為，參考 `KNOWN_ISSUES.md`

---

## 📊 驗證數據 (10.8.34.22)

### 部署資訊
| 項目 | 值 |
|------|-----|
| 部署日期 | 2025-11-12 |
| F5 設備 | 10.8.34.22 (Clean LAB) |
| 部署方式 | deploy.sh (自動化) |
| 部署時間 | < 5 分鐘 |
| 狀態 | ✅ 完全成功 |

### 數據統計
| Zone | 記錄數 | 檔案大小 |
|------|--------|---------|
| rpztw | 58,610 | ~2.5MB |
| phishtw | 821 | ~35KB |
| 總計 | 59,431 | ~2.5MB |

### 目錄結構驗證
```
/var/tmp/RPZ_Local_Processor/
├── scripts/
│   ├── main.sh
│   ├── check_soa.sh
│   ├── extract_rpz.sh
│   ├── parse_rpz.sh
│   ├── generate_datagroup.sh
│   └── update_datagroup.sh
├── config/
│   └── icall_setup.sh
└── install.sh

/var/tmp/rpz_datagroups/
├── raw/
│   └── dnsxdump_20251112_143015.out
├── parsed/
│   ├── rpz_20251112_143015.txt
│   └── phishtw_20251112_143015.txt
├── final/
│   ├── rpz.txt           → 58,610 筆
│   └── phishtw.txt       → 821 筆
└── .soa_cache/
    ├── rpztw.soa
    └── phishtw.soa
```

---

## 📝 已知限制與注意事項

### 限制 1: iCall 遠端設定不可靠
- **影響**: config/icall_setup.sh 透過 SSH 執行可能失敗
- **原因**: tmsh brace escaping 在遠端 SSH session 不穩定
- **解決**: 手動在 F5 上執行 iCall 設定 (參考 Phase 3: 方式 A)

### 限制 2: 乾淨環境需手動建立 DataGroup
- **影響**: 首次部署需額外步驟
- **原因**: DataGroup 不會自動建立
- **解決**: 在首次執行前手動建立 (參考 Phase 3.1)
- **未來改進**: 考慮在 install.sh 中自動建立

### 限制 3: Infoblox 與 F5 筆數差異
- **影響**: 記錄數可能少 2-5 筆
- **原因**: F5 DataGroup 不支援 Round-Robin，多 IP 記錄只保留一個
- **解決**: 這是預期行為，不影響功能 (參考 KNOWN_ISSUES.md)

### 注意事項 1: TMOS Shell 環境
- 避免使用 `hostname` 指令 (會返回錯誤)
- 避免使用 `echo | xargs` (會觸發警告)
- 避免使用 `((count++))` (在 set -e 環境會中斷)

### 注意事項 2: SOA 檢查機制
- 預設啟用 SOA Serial 檢查，避免不必要的處理
- 首次執行建議使用 `--force` 跳過檢查
- SOA cache 位於 `/var/tmp/rpz_datagroups/.soa_cache/`

### 注意事項 3: DataGroup 格式要求
- 必須是 `"key" := "value",` 格式
- 每行結尾必須有逗號
- 萬用字元 domain 用 `.example.com` 格式

---

## 🔄 日常維護

### 監控檢查 (每日)
```bash
# 檢查 iCall 執行狀態
tail -50 /var/tmp/rpz_wrapper.log

# 檢查系統日誌
tail -100 /var/log/ltm | grep RPZ

# 檢查 DataGroup 記錄數
tmsh list ltm data-group external rpztw | grep records
```

### 定期維護 (每週)
```bash
# 檢查磁碟空間
du -sh /var/tmp/rpz_datagroups/

# 清理舊檔案 (保留最近 7 天)
find /var/tmp/rpz_datagroups/raw/ -type f -mtime +7 -delete
find /var/tmp/rpz_datagroups/parsed/ -type f -mtime +7 -delete
```

### 緊急處理
```bash
# 立即強制更新
bash /var/tmp/RPZ_Local_Processor/scripts/main.sh --force --verbose

# 停用 iCall (緊急維護)
tmsh modify sys icall handler periodic rpz_processor_handler status inactive

# 啟用 iCall (維護完成)
tmsh modify sys icall handler periodic rpz_processor_handler status active
```

---

## 📞 支援資訊

### 關鍵檔案位置
| 類型 | 路徑 |
|------|------|
| 專案目錄 | `/var/tmp/RPZ_Local_Processor/` |
| 主腳本 | `/var/tmp/RPZ_Local_Processor/scripts/main.sh` |
| 輸出目錄 | `/var/tmp/rpz_datagroups/` |
| 最終檔案 | `/var/tmp/rpz_datagroups/final/` |
| Wrapper Log | `/var/tmp/rpz_wrapper.log` |
| 系統日誌 | `/var/log/ltm` |

### 相關文檔
- `DEPLOYMENT_GUIDE.md` - 詳細部署指南
- `DEPLOYMENT_SUCCESS.md` - 原始部署記錄 (10.8.34.234)
- `KNOWN_ISSUES.md` - 已知問題與限制
- `docs/SCHEDULE_SETUP.md` - iCall 排程設定
- `README.md` - 專案概述

### 聯絡資訊
- **維護團隊**: DevOps Team
- **專案負責人**: Ryan Tseng
- **最後驗證**: 2025-11-12 on 10.8.34.22

---

## 📈 版本歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2025-09-30 | 初始版本 - 手動部署流程 (10.8.34.234) |
| 2.0 | 2025-11-12 | 自動化部署流程 (deploy.sh) + 乾淨環境驗證 (10.8.34.22) |

---

**SOP 狀態**: ✅ 已驗證並投入使用
**適用範圍**: 所有 F5 BIG-IP DNS 環境 (包含乾淨 LAB 與生產環境)
**預期部署時間**: 10-15 分鐘 (含驗證)
