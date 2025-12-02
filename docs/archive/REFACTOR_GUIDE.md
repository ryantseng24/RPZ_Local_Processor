# 程式碼重構指南

本文件說明如何將現有的 Shell Script 重構整合到此專案架構。

## 📋 重構檢查清單

### 1. 程式碼審查
- [ ] 檢查現有程式碼功能
- [ ] 識別可重用的函數
- [ ] 找出硬編碼的配置值
- [ ] 標記需要改進的部分

### 2. 模組化分割
- [ ] 提取 DNS Express 讀取邏輯 → `extract_rpz.sh`
- [ ] 提取 RPZ 解析邏輯 → `parse_rpz.sh`
- [ ] 提取 DataGroup 產生邏輯 → `generate_datagroup.sh`
- [ ] 提取共用函數 → `utils.sh`

### 3. 配置外部化
- [ ] Zone 清單 → `config/rpz_zones.conf`
- [ ] Landing IP 映射 → `config/datagroup_mapping.conf`
- [ ] 路徑配置 → 環境變數或配置檔案

### 4. 錯誤處理強化
- [ ] 加入 `set -euo pipefail`
- [ ] 使用 `die()` 函數處理致命錯誤
- [ ] 加入輸入驗證

### 5. 日誌與除錯
- [ ] 統一使用 `log_*` 函數
- [ ] 加入 DEBUG 模式
- [ ] 記錄執行時間

### 6. 測試
- [ ] 建立測試資料
- [ ] 撰寫單元測試
- [ ] 執行端到端測試

---

## 🔧 重構範例

### 原始程式碼 (假設)
```bash
#!/bin/bash
# 提取 RPZ 資料
tmsh list ltm dns zone rpztw. > /tmp/rpz_data.txt
cat /tmp/rpz_data.txt | grep "CNAME" | awk '{print $1}' > /tmp/fqdn_list.txt
```

### 重構後
```bash
#!/bin/bash
# extract_rpz.sh
set -euo pipefail

source "$(dirname "$0")/utils.sh"

extract_zone() {
    local zone_name="$1"
    local output_file="$2"

    log_info "提取 Zone: $zone_name"

    if ! tmsh list ltm dns zone "$zone_name" > "$output_file" 2>&1; then
        die "無法提取 Zone: $zone_name"
    fi

    log_debug "資料已儲存: $output_file"
}

main() {
    local zone_name="${1:-rpztw.}"
    local output_dir="${OUTPUT_DIR:-/var/tmp/rpz_datagroups/raw}"

    ensure_dir "$output_dir"
    extract_zone "$zone_name" "${output_dir}/${zone_name}.raw"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

---

## 📝 重構步驟

### 步驟 1: 提供現有程式碼
請將你的 Shell Script 內容貼上，我會進行分析。

### 步驟 2: 分析與規劃
我會識別：
- 主要功能區塊
- 可重用的函數
- 需要配置化的部分
- 潛在的問題點

### 步驟 3: 模組化重構
根據分析結果，將程式碼拆分到對應的腳本：
- `extract_rpz.sh` - DNS Express 資料提取
- `parse_rpz.sh` - RPZ 記錄解析
- `generate_datagroup.sh` - DataGroup 檔案產生

### 步驟 4: 整合測試
確保重構後的程式碼：
- 功能完整無缺失
- 執行結果一致
- 效能沒有明顯下降

### 步驟 5: 文件更新
更新 README 和相關文件。

---

## 🎯 重構目標

| 項目 | 重構前 | 重構後 |
|------|-------|--------|
| **可讀性** | 單一大檔案 | 模組化清晰 |
| **可維護性** | 硬編碼配置 | 配置外部化 |
| **錯誤處理** | 基礎或無 | 完善的錯誤處理 |
| **日誌** | echo 或無 | 統一日誌函數 |
| **測試** | 手動測試 | 自動化測試 |
| **重用性** | 低 | 高 (函數庫) |

---

## 📤 準備提交程式碼

請提供以下資訊：

1. **現有 Shell Script 內容**
   ```bash
   # 完整的程式碼
   ```

2. **主要功能描述**
   - 做什麼事情？
   - 輸入是什麼？
   - 輸出是什麼？

3. **目前的問題或限制**
   - 有什麼地方不滿意？
   - 想改進什麼？

4. **特殊需求**
   - 是否有特定的 F5 指令？
   - 是否有效能要求？

---

**準備好了嗎？請貼上你的程式碼！** 🚀