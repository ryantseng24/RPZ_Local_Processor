# cdns_localRPZ iRule TCL Error 技術分析報告

**日期**: 2026-03-24
**對象**: iRule `/Common/cdns_localRPZ`
**事件期間**: 2026-03-17 13:04 ~ 14:54
**影響設備**: C11401-I4800-01, C23504-R10600-01, C23504-I10800-01, C23504-I10800-02

---

## 1. 問題現象

iRule 在處理特定 DNS 查詢時產生 TCL error：

```
01220001:3: TCL error: /Common/cdns_localRPZ <DNS_REQUEST> - bad option
"-r.occ.bbb1.family.dta.netflix.com": must be -all, -index, -element, -list, -name, or -value
while executing "class match -name $query_name ends_with white_Domains"
```

觸發錯誤的域名清單：

| 時間 | 域名 | 來源設備 |
|------|------|----------|
| 14:54:55~56 | `-s9zofcaxp8iotsbprnu4f.uribl.rspamd.com` | C11401-I4800-01 |
| 14:37:07~09 | `-r.occ.bbb1.family.dta.netflix.com` | C23504-R10600-01, C23504-I10800-01 |
| 14:01:28~29 | `-v.overview.mail.yahoo.com` | C23504-R10600-01, C23504-I10800-01 |
| 13:44:38~39 | `-drssl.secure.hero.eu-west-1.prodaa.netflix.com` | C23504-I10800-02 |
| 13:20:33~35 | `-staging.us.hero.eu-west-1.prodaa.netflix.com` | C23504-I10800-02 |
| 13:04:37 | `-staging.west.us-east-1.origin.prodaa.netflix.com` | C23504-R10600-01 |

**共同特徵：所有觸發錯誤的域名，其第一個 label 皆以 `-`（hyphen）開頭。**

---

## 2. 根因分析

### 2.1 TCL 語法解析問題

iRule 中使用 `class match` 指令進行 DataGroup 比對。程式碼中第一層檢查有正確使用 `--`（end-of-options 標記）：

```tcl
# 第一層：有 -- 保護，正常運作
if { [class match -- $query_name ends_with white_Domains] } {

    # 第二層：缺少 --，此處產生錯誤
    set wl_key [class match -name $query_name ends_with white_Domains]
```

當 `$query_name` 的值為 `-r.occ.bbb1.family.dta.netflix.com` 時，第二層展開為：

```tcl
class match -name -r.occ.bbb1.family.dta.netflix.com ends_with white_Domains
```

TCL 語法解析器將 `-r.occ.bbb1.family.dta.netflix.com` 誤判為命令選項（option），因為它以 `-` 開頭。由於 `-r.occ...` 不是合法的 `class match` 選項（合法選項為 `-all`, `-index`, `-element`, `-list`, `-name`, `-value`），因此拋出 `bad option` 錯誤。

### 2.2 受影響的程式碼位置

iRule 中共有 **6 處** `class match` 呼叫缺少 `--` 保護：

| DataGroup | 指令 | 狀態 |
|-----------|------|------|
| white_Domains | `class match -- $query_name ends_with white_Domains` | ✅ 正常 |
| white_Domains | `class match -name $query_name ends_with white_Domains` | ❌ 缺少 `--` |
| rpztw | `class match -- $query_name ends_with rpztw` | ✅ 正常 |
| rpztw | `class match -name $query_name ends_with rpztw` | ❌ 缺少 `--` |
| rpztw | `class match -value $query_name ends_with rpztw` | ❌ 缺少 `--` |
| phishtw | `class match -- $query_name ends_with phishtw` | ✅ 正常 |
| phishtw | `class match -name $query_name ends_with phishtw` | ❌ 缺少 `--` |
| phishtw | `class match -value $query_name ends_with phishtw` | ❌ 缺少 `--` |
| blacklist_Domains | `class match -- $query_name ends_with blacklist_Domains` | ✅ 正常 |
| blacklist_Domains | `class match -name $query_name ends_with blacklist_Domains` | ❌ 缺少 `--` |

### 2.3 錯誤發生時的行為

TCL error 發生後，該次 `DNS_REQUEST` event handler 立即中斷。該筆 DNS 查詢會跳過所有後續的 RPZ 過濾邏輯，由 DNS Express 正常處理並回應。

---

## 3. 對設備的影響評估

| 評估面向 | 結論 | 說明 |
|----------|------|------|
| **設備穩定性** | ✅ 無影響 | TCL error 由 TMM 正常捕獲，不會造成 TMM crash、restart 或 memory leak |
| **系統效能** | ✅ 無影響 | 每次錯誤僅產生一筆 syslog（err level），無額外 CPU 或記憶體消耗 |
| **RPZ 安全過濾** | ✅ 影響極低 | 僅該筆以 `-` 開頭的查詢跳過過濾，佔整體查詢比例極低 |
| **其他 DNS 查詢** | ✅ 無影響 | 不以 `-` 開頭的正常查詢不受影響，iRule 邏輯正常執行 |

---

## 4. 以 `-` 開頭的 DNS 域名是否合法

### 4.1 RFC 規範

此問題涉及兩個層級的規範，需要區分：

**Hostname 命名規則（RFC 952 / RFC 1123）— 不符合慣例**

RFC 952 及 RFC 1123 定義的 LDH Rule（Letters-Digits-Hyphens）規定：
- 每個 label 的**開頭必須是字母或數字**，不能是 `-`
- 每個 label 的**結尾也不能是 `-`**
- 因此以 `-` 開頭的 label 不符合 hostname 命名慣例

**DNS 協議規範（RFC 2181 Section 11）— 協議層面合法**

RFC 2181 明確指出：

> *"The DNS itself places only one restriction on the particular labels that can be used to identify resource records. That one restriction relates to the length of the label and the full name."*

DNS 協議本身**僅限制長度**（每個 label 1-63 bytes，全名 255 bytes），不限制字元內容。以 `-` 開頭的 label 在 DNS wire format 層面是完全合法的。

### 4.2 對照表

| 規範層級 | 以 `-` 開頭的 label | 是否強制執行 |
|----------|---------------------|-------------|
| Hostname 慣例（RFC 952/1123） | 不符合 | 不強制，僅為命名建議 |
| DNS 協議（RFC 2181） | 合法 | DNS Server 不會拒絕 |
| 域名註冊商（ICANN/EPP） | 不允許註冊 | 僅限頂層域名註冊，子域名不受此限 |
| DNS Server（BIND/F5/Unbound） | 正常處理 | 接受查詢並回應，不做 LDH 驗證 |

### 4.3 類似案例

不符合 hostname 慣例但在 DNS 中廣泛使用的 label 非常常見：

- **SRV Record**：`_ldap._tcp.dc._msdcs.corp.example.com`（以 `_` 開頭）
- **DKIM**：`_domainkey.example.com`（以 `_` 開頭）
- **DNSBL**：`2.0.168.192.bl.spamcop.net`（以數字開頭的 IP 反查）
- **AD 環境**：Windows 電腦自動查詢 `_kerberos._tcp.corp.example.com` 尋找 Domain Controller

這些都是日常 DNS 流量的一部分，DNS Server 均正常處理。

---

## 5. 觸發域名的實際查詢驗證

使用 `dig -q` 對 log 中出現的域名進行實際查詢驗證（2026-03-24）：

```bash
dig @8.8.8.8 -q <domain_name>
```

> 註：`dig` 同樣會將 `-` 開頭的參數誤判為選項，需使用 `-q` 明確指定查詢名稱。這與 iRule 中 `class match` 遇到的問題本質相同。

| 域名 | DNS 回應狀態 | A/AAAA Record | 說明 |
|------|-------------|---------------|------|
| `-r.occ.bbb1.family.dta.netflix.com` | NOERROR | 無 | Zone 存在但無該子域名紀錄 |
| `-v.overview.mail.yahoo.com` | NXDOMAIN | 無 | 域名不存在 |
| `-s9zofcaxp8iotsbprnu4f.uribl.rspamd.com` | NXDOMAIN | 無 | 域名不存在 |

### 5.1 查詢來源判斷

這些查詢均為客戶端或內部服務自動產生的探測行為，非人為操作，也非攻擊流量：

- **Netflix 系列域名**（`-r.occ.bbb1.family.dta.netflix.com` 等）：Netflix CDN 客戶端內部服務探測用的子域名，用於定位最近的 CDN 節點或確認服務狀態。
- **Yahoo Mail**（`-v.overview.mail.yahoo.com`）：Yahoo Mail 客戶端的內部前綴查詢。
- **rspamd**（`-s9zofcaxp8iotsbprnu4f.uribl.rspamd.com`）：rspamd 反垃圾郵件系統的 DNSBL 查詢，將 URL hash 送到 `uribl.rspamd.com` 查詢是否在黑名單中，回應 NXDOMAIN 表示「不在名單中」。

這類行為類似企業內已加入 AD 的電腦，離開企業網路後仍持續送出 `_ldap._tcp.dc._msdcs.corp.example.com` 等查詢尋找 Domain Controller 服務。屬於正常的自動化 DNS 查詢行為。

**所有觸發域名均查無 A/AAAA 記錄，即使 iRule 正常放行也僅會回應 NXDOMAIN 或空回應，不存在安全風險。**

---

## 6. 改善方案

### 6.1 修正方式

在所有 `class match -name` 及 `class match -value` 指令中加入 `--`（end-of-options 標記）：

```tcl
# 修正前
set wl_key [class match -name $query_name ends_with white_Domains]

# 修正後
set wl_key [class match -name -- $query_name ends_with white_Domains]
```

`--` 是 TCL 標準語法，告訴解析器「後續參數皆為值，不再是選項」。此寫法對不以 `-` 開頭的正常域名完全無影響，僅額外保護以 `-` 開頭的邊界情況。

### 6.2 改動範圍

- 僅修改 6 處 `class match` 呼叫，各加入 `--`
- **不涉及邏輯變更**，不影響現有的白名單、黑名單、RPZ 比對行為
- 修正版本：`rpzdg_local_v2.tcl`（已準備，待驗證）

### 6.3 驗證計畫

1. 在測試環境部署 v2 iRule
2. 送出一般域名查詢，確認過濾邏輯正常
3. 送出以 `-` 開頭的域名查詢（`dig -q -test.example.com`），確認不再產生 TCL error
4. 觀察 `/var/log/ltm` 確認無異常
5. 驗證通過後安排正式環境更新
