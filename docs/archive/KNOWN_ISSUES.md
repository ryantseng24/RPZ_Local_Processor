# RPZ Local Processor - 已知問題與限制

## 📋 問題列表

### 1. Infoblox RPZ 與 F5 DataGroup 筆數差異

**發現日期**: 2025-11-12
**狀態**: ✅ 已確認為預期行為，非 Bug
**影響等級**: 低（不影響功能）

#### 問題描述

Infoblox RPZ Zone 匯出的記錄數量與 F5 DataGroup 最終筆數存在差異：

- **Infoblox rpztw zone**: 58,612 筆
- **F5 rpztw DataGroup**: 58,610 筆
- **差異**: 2 筆

#### 根本原因

這是 **BIND RPZ 與 F5 DataGroup 架構差異**導致的預期行為：

##### 1. BIND RPZ 支持多 Landing IP (Round-Robin)

Infoblox 允許同一個 domain 配置多個 Landing IP：

```dns
walmstore.com.rpztw.    IN A 182.173.0.181
walmstore.com.rpztw.    IN A 34.102.218.71
*.walmstore.com.rpztw.  IN A 182.173.0.181
*.walmstore.com.rpztw.  IN A 34.102.218.71
```

**用途**: DNS Round-Robin，可實現負載均衡或冗餘。

##### 2. F5 DataGroup 是 Key-Value 結構

F5 External DataGroup 每個 key 只能對應一個 value：

```
"walmstore.com" := "34.102.218.71"     // 只保留一個 IP
".walmstore.com" := "34.102.218.71"    // 只保留一個 IP
```

**限制**: 關聯陣列特性，相同 key 後面的值會覆蓋前面的值。

##### 3. AWK 解析行為

`scripts/parse_rpz.sh` 使用 AWK 關聯陣列：

```awk
rpz[$1] = $5  # 相同 domain 時，後面的 IP 覆蓋前面的
```

**結果**:
- Infoblox: 4 筆記錄（2 個 domain × 2 個 IP）
- F5 DataGroup: 2 筆記錄（2 個 domain × 1 個 IP）

#### 實際案例

**walmstore.com 在 Infoblox 的配置**:

| Domain | Landing IP | 狀態 |
|--------|------------|------|
| `*.walmstore.com` | 182.173.0.181 | ❌ 被覆蓋 |
| `*.walmstore.com` | 34.102.218.71 | ✅ 保留 |
| `walmstore.com` | 182.173.0.181 | ❌ 被覆蓋 |
| `walmstore.com` | 34.102.218.71 | ✅ 保留 |

**F5 DataGroup 最終結果**:

```
".walmstore.com" := "34.102.218.71"    // 保留最後一個 IP
"walmstore.com" := "34.102.218.71"     // 保留最後一個 IP
```

#### 影響分析

##### ✅ 功能不受影響

1. **黑名單攔截功能正常**：
   - 用戶訪問 `walmstore.com` 或其子域名仍會被攔截
   - 導向任一 Landing IP 的效果相同

2. **性能優勢**：
   - F5 DataGroup Key-Value 查詢比多值查詢更快
   - 簡化 iRule 邏輯

3. **實際應用場景**：
   - 多數 RPZ 場景不需要 Round-Robin
   - Landing Page 通常只需要一個 IP

##### ⚠️ 潛在考量

1. **負載均衡失效**：
   - 如果原本期望透過多 IP 實現負載均衡，F5 環境無法達成
   - 建議在 Landing Page 前端（如 Load Balancer）實現負載均衡

2. **冗餘設計失效**：
   - 如果某個 Landing IP 故障，F5 不會自動切換到備用 IP
   - 建議在基礎設施層面實現高可用性

#### 驗證方法

##### 檢查 Infoblox 中有多個 IP 的 domain

```bash
# 從 Infoblox CSV 匯出中分析
awk -F',' 'NR>1 {count[$4]++} END {
    for (d in count) {
        if (count[d] > 1) print d, count[d]
    }
}' infoblox_rpz_data.csv
```

##### 檢查 F5 DNS Express 原始資料

```bash
# 查看 dnsxdump 中是否有多個 A 記錄
grep "walmstore.com.rpztw" /var/tmp/rpz_datagroups/raw/dnsxdump_*.out
```

##### 比對最終 DataGroup

```bash
# 查看最終只保留一個 IP
grep "walmstore" /var/tmp/rpz_datagroups/final/rpz.txt
```

#### 數據對比

| 指標 | Infoblox | F5 DataGroup | 說明 |
|------|----------|--------------|------|
| 總記錄數 | 58,612 | 58,610 | 包含/不包含重複 IP |
| 唯一 Domain | 58,610 | 58,610 | 實際域名數量相同 ✅ |
| 重複 IP 記錄 | 2 | 0 | 覆蓋行為 |

**公式**: `Infoblox 記錄數 - 重複 IP 數 = F5 DataGroup 記錄數`
**驗證**: `58,612 - 2 = 58,610` ✅

#### 解決方案

##### 方案 1: 接受現狀（推薦）

**適用場景**: Landing Page 不需要負載均衡或冗餘

- ✅ 無需修改
- ✅ 性能最佳
- ✅ 邏輯最簡單

**理由**:
- F5 DataGroup 的用途是快速黑名單查詢，不是負載均衡
- 兩個 Landing IP 效果相同
- 基礎設施層面已有高可用性設計

##### 方案 2: 調整 Infoblox 配置

**適用場景**: 想要源頭與目標數據完全一致

```dns
# 移除重複的 IP，每個 domain 只保留一個 Landing IP
walmstore.com.rpztw.    IN A 34.102.218.71
*.walmstore.com.rpztw.  IN A 34.102.218.71
```

**優點**: 數據一致性更好
**缺點**: 失去 DNS Round-Robin 能力（但 F5 本來就不支持）

##### 方案 3: 修改 AWK 邏輯（不推薦）

保留所有 IP 並連接成字串：

```awk
# 將多個 IP 合併
if (rpz[$1]) {
    rpz[$1] = rpz[$1] "," $5
} else {
    rpz[$1] = $5
}
```

**問題**:
- ❌ F5 DataGroup value 格式錯誤
- ❌ iRule 需要修改以支持多 IP
- ❌ 增加複雜度但無實際效益

##### 方案 4: 在文檔中註記（已執行）

記錄此已知行為，避免未來誤判為 Bug。

#### 最佳實踐建議

##### Infoblox RPZ 配置

1. **優先使用單一 Landing IP**：
   ```dns
   *.example.com.rpztw.  IN A 34.102.218.71
   ```

2. **避免不必要的 Round-Robin**：
   - 除非有明確需求，否則每個 domain 只配置一個 IP
   - 在 Landing Page 前端實現負載均衡，而非 DNS 層

3. **定期審查配置**：
   ```bash
   # 檢查哪些 domain 有多個 IP
   # 評估是否真的需要
   ```

##### F5 環境考量

1. **Landing Page 高可用性**：
   - 在 F5 GTM/LTM 層面實現
   - 而非依賴 DNS Round-Robin

2. **監控 DataGroup 筆數**：
   - 設定基準值（如 58,610）
   - 異常變化時告警

3. **文檔化差異**：
   - 團隊成員了解此行為
   - 避免誤判為同步問題

#### 相關配置

- **解析腳本**: `scripts/parse_rpz.sh` (line 32-129)
- **AWK 邏輯**: 關聯陣列覆蓋行為
- **影響範圍**: 所有有多個 Landing IP 的 RPZ 記錄

#### 監控建議

```bash
# 在 Infoblox 匯出後檢查重複 IP 的數量
awk -F',' 'NR>1 {count[$4]++} END {
    dup=0
    for (d in count) if (count[d]>1) dup+=(count[d]-1)
    print "預期 F5 筆數:", NR-1-dup
}' infoblox_rpz_data.csv

# 對比 F5 實際筆數
wc -l /var/tmp/rpz_datagroups/final/rpz.txt
```

#### 參考文檔

- **BIND RPZ 規範**: https://www.ietf.org/archive/id/draft-vixie-dnsop-dns-rpz-00.html
- **F5 External DataGroup**: https://support.f5.com/csp/article/K13926
- **本專案解析邏輯**: `scripts/parse_rpz.sh`

---

### 2. tmsh save 時出現 Deprecated 警告訊息

**發現日期**: 2025-12-02
**狀態**: ✅ 可安全忽略
**影響等級**: 無（純資訊性警告）

#### 問題描述

執行 `tmsh save sys config` 時，LTM log 出現以下警告：

```
warning  tmsh[xxxx]  01420013  [api-status-warning] wom/server-discovery is deprecated
warning  tmsh[xxxx]  01420013  [api-status-warning] wom/endpoint-discovery is deprecated
warning  tmsh[xxxx]  01420013  [api-status-warning] wom/deduplication is deprecated
warning  tmsh[xxxx]  01420013  [api-status-warning] sys/ecm/cloud-provider is deprecated
warning  tmsh[xxxx]  01420013  [api-status-warning] sys/datastor is deprecated
```

#### 根本原因

這是 **F5 BIG-IP 系統的標準棄用通知**，與 RPZ 處理流程無關：

| 模組 | 說明 |
|------|------|
| `wom/*` | WAN Optimization Module - 已棄用的 WAN 優化功能 |
| `sys/ecm/cloud-provider` | Enterprise Cloud Manager - 已棄用的雲端整合 |
| `sys/datastor` | 資料儲存模組 - 已棄用 |

這些警告會在**任何** `tmsh save sys config` 指令執行時出現，不只是 RPZ 更新。

#### 影響分析

- ✅ **RPZ DataGroup 更新不受影響**
- ✅ **配置儲存正常完成**
- ⚠️ 這些模組在未來 BIG-IP 版本可能移除

#### 解決方案

**建議**: 保持現狀，忽略這些警告。

如果需要抑制警告（不建議，可能隱藏其他重要錯誤）：

```bash
# 在 update_datagroup.sh 中
tmsh save sys config 2>/dev/null
```

---

## 📝 更新歷史

| 日期 | 版本 | 說明 | 作者 |
|------|------|------|------|
| 2025-12-02 | 1.1 | 新增 tmsh deprecated 警告說明 | Claude Code with Ryan |
| 2025-11-12 | 1.0 | 初始記錄 Infoblox/F5 筆數差異問題 | Claude Code with Ryan |

---

## 🔗 相關文檔

- **架構簡化總結**: `docs/ARCHITECTURE_SIMPLIFICATION.md`
- **錯誤 Log 定義**: `docs/ERROR_LOG_DEFINITIONS.md`
- **部署指南**: `docs/DEPLOYMENT_GUIDE.md`

---

**文檔建立**: 2025-11-12 22:00
**最後更新**: 2025-11-12 22:00
**維護者**: DevOps Team
**狀態**: Active
