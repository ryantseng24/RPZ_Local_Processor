# RPZ Local Processor — DataGroup 停止更新事件處理紀錄

**建立日期**: 2026-08-20
**最後更新**: 2026-08-21（v6，含兩輪獨立審核回應）
**狀態**: 根因已確認。patch 經兩輪獨立審核，兩輪均判定 NO-GO，兩輪的第一階段 findings 都已修正並在 LAB 重新驗收。**待第三輪審核與正式機上線**。
**審核報告**: `docs/reviews/CODE_REVIEW_20260821.md`（第一輪，回應見第 16 節）、`docs/reviews/CODE_REVIEW_PHASE1A_ROUND2_20260821.md`（第二輪，回應見第 17 節）。
**現行 patch**: `patches/rpz_patch_sigpipe_v3.sh`。v1、v2 已作廢，見 `patches/README.md`。
**影響設備**: 設備A、設備B、設備C、設備D（四台全部）
**服務對象**: 客戶 cache DNS

## 這份文件怎麼讀

| 你是 | 從哪裡開始 |
|---|---|
| 要理解問題 | 第 1、2 節 |
| 要 review 這份分析 | 第 4、5、6 節（LAB 規格、驗證方法、完整實測數據）＋ 第 11 節（分析的限制） |
| 要執行緊急處置 | 第 8 節，或直接看 `RPZ_手動清檔作業說明_20260821.md` |
| 要上 patch | 第 7、9 節 |
| 接手後續工作 | 第 10、12 節 |
| 看第一輪審核怎麼處理的 | 第 16 節 |
| 看第二輪審核怎麼處理的 | 第 17 節 |

---

## 1. 事件摘要

工程師回報 F5 上 `/config` 有大量 dnsxdump 檔案累積。追查後發現檔案累積只是症狀，真正的問題是：

**RPZ DataGroup 已經停止更新，最久的一台停了 7 天。**

根因是三行 shell 程式碼使用了 `ls -t <glob> | head -1`。這個寫法在 `set -o pipefail` 下，當 `ls` 的輸出超過 4096 bytes 時會因為 SIGPIPE 而讓腳本無聲終止。**失敗機率隨目錄內檔案數增加**，檔案越累積、失敗越頻繁，形成無法自我恢復的循環。

四台正式機在 2026-08-20 的推估失敗率是 53%~87%。

---

## 2. Root Cause

### 2.1 缺陷位置

| 檔案 | 行 | 程式碼 |
|------|-----|--------|
| `scripts/parse_rpz.sh` | 227 | `dnsxdump_file=$(ls -t "${RAW_DATA_DIR}"/dnsxdump_*.out 2>/dev/null \| head -1)` |
| `scripts/generate_datagroup.sh` | 65 | `parsed_file=$(ls -t "${PARSED_DATA_DIR}/${zone}_"*.txt 2>/dev/null \| head -1)` |
| `scripts/generate_datagroup.sh` | 82 | `ip_file=$(ls -t "${PARSED_DATA_DIR}"/rpzip_*.txt 2>/dev/null \| head -1)` |

三支腳本都有 `set -euo pipefail`（`parse_rpz.sh:11`、`generate_datagroup.sh:9`）。

### 2.2 失效機制

1. glibc 對 pipe 的 stdio buffer 是 **4096 bytes**（來自 pipe 的 `st_blksize`）。
2. `ls` 的輸出在 4096 bytes 以內時，只做**一次** `write()`，寫完就結束。
3. 輸出超過 4096 bytes 時，`ls` 需要**多次** `write()`。
4. `head -1` 讀到第一行就結束並關閉 pipe 的讀取端。
5. `ls` 後續的 `write()` 收到 **SIGPIPE**，以退出碼 **141** 結束。
6. `pipefail` 讓整個管線回傳 141。
7. `set -e` 立即終止腳本，**而且不輸出任何錯誤訊息**。

`raw/` 的每一行是 `/config/snmp/rpz_datagroups/raw/dnsxdump_YYYYmmdd_HHMMSS.out` = 60 字元 + 換行 = **61 bytes**。所以 `4096 / 61 = 67.1`，**67 個檔案是安全上限**。

### 2.3 各 glob 的行長與上限

| glob | 目錄前綴 | 檔名 | 每行 bytes | 安全上限 |
|---|---|---|---|---|
| `raw/dnsxdump_*.out` | 32 | 28 | 61 | 67 |
| `parsed/rpztw_*.txt` | 35 | 25 | 61 | 67 |
| `parsed/phishtw_*.txt` | 35 | 27 | 63 | 65 |
| `parsed/rpzip_*.txt` | 35 | 25 | 61 | 67 |

LAB 實測確認的實際 byte 數（見 6.4）：raw 61、rpztw 61、phishtw 63、rpzip 61，與計算一致。

### 2.4 `bash -x` 抓到的確切死亡位置

```
[INFO] 載入 2 個 Zones: rpztw phishtw
+ ensure_dir .../parsed
+ [[ -d .../parsed ]]
+ local dnsxdump_file
+ [[ -n '' ]]
++ head -1
++ ls -t .../raw/dnsxdump_*.out
+ dnsxdump_file=.../raw/dnsxdump_20260820_120501.out   <- 值已正確取到才被殺
```

最後一行值得注意：**變數已經正確賦值成最新的檔案**，腳本要的資訊全部拿到了，純粹因為管線的退出碼是 141 才被 `set -e` 終止。這個失敗是完全多餘的。

### 2.5 惡性循環

`cleanup()` 定義在 `main.sh:75-95`，唯一的呼叫點在 `main.sh:175`，位置在五個步驟**全部成功之後**。唯一會刪檔的是 `main.sh:84` 的 `find "$OUTPUT_DIR" -type f -mtime +7 -delete`。

1. 檔案累積超過 67 個 → 步驟 3 開始失敗
2. 步驟 3 失敗 → `main.sh:153` `exit 1` → `cleanup()` 跑不到
3. 檔案繼續累積 → 失敗率繼續上升
4. 回到第 1 步

**系統無法自行恢復。**

### 2.6 為什麼 log 裡看不出來

`parse_rpz.sh` 的退出碼是 **141**，但 `config/icall_setup_api.sh:67` 產生的 wrapper 只記錄 `main.sh` 的退出碼，也就是 **1**：

```
[INFO] 步驟 3/5: 解析 RPZ 記錄
[INFO] === 開始解析 RPZ 記錄 ===
[INFO] 載入 2 個 Zones: rpztw phishtw
[ERROR] RPZ 解析失敗
=== Exit Code: 1 ===
```

141 從來沒有進到 log。`[INFO] 使用 dnsxdump 檔案:` 這一行不見了，是唯一的線索。

**判別方法**：在 `rpz_wrapper.log` 找 `載入 N 個 Zones`。如果下一行直接是 `[ERROR] RPZ 解析失敗`，中間沒有 `[INFO] 使用 dnsxdump 檔案:`，就是這個缺陷。

---

## 3. 四台正式機的實際狀況

**資料來源**：`客戶診斷資料_20260820/` 目錄下四份 PuTTY log，工程師於 2026-08-20 15:51~16:00 擷取。Chinese 字元在 PuTTY log 中遺失，訊息內容是對照原始碼還原的。

### 3.1 磁碟與檔案累積

| 設備 | `/config` | 剩餘 | raw/ 檔數 | raw/ 大小 | parsed/ 檔數 | parsed/ 大小 | raw/ 最舊檔 |
|---|---|---|---|---|---|---|---|
| 設備A | 70% | 934M | 141 | 1.5G | 267 | 447M | 08-10 09:30 |
| **設備B** | **84%** | **514M** | **179** | **1.9G** | **285** | **469M** | 08-05 16:20 |
| 設備C | 80% | 617M | 169 | 1.8G | 282 | 467M | 08-06 14:20 |
| 設備D | 60% | 1.2G | 125 | 1.4G | 201 | 337M | 08-11 17:20 |

`df -i` 四台都是 1%，inode 沒問題。**磁碟都沒有滿**，缺陷與磁碟空間無關。

設備B 在擷取過程中跳出 F5 告警：`011d0004:3: Disk partition /config has only 16% free`。

### 3.2 DataGroup 停滯時間

`final/rpzip.txt` 是最準的標記。`parse_rpz.sh` 產生的 rpzip 檔永遠是空的（RPZ 來源沒有 IP 類型記錄），所以 `generate_datagroup.sh:91` 的 `touch` 每次都會執行。它的 mtime 就是**步驟 4 最後一次完整跑完的時間**。

| 設備 | rpztw.txt | phishtw.txt | rpzip.txt | 最後一次完整成功 | 停滯 |
|---|---|---|---|---|---|
| 設備A | 08-18 12:20 | 08-18 09:10 | 08-18 09:10 | 08-18 09:10 | **54.7 小時** |
| 設備B | 08-14 17:25 | 08-14 00:35 | 08-13 16:10 | 08-13 16:10 | **167.7 小時（7.0 天）** |
| 設備C | 08-15 19:35 | 08-15 17:05 | 08-14 13:55 | 08-14 13:55 | **146.0 小時（6.1 天）** |
| 設備D | 08-19 15:05 | 08-19 15:05 | 08-19 15:05 | 08-19 15:05 | 24.9 小時 |

三個檔案 mtime 不一致，代表步驟 4 是**跑到一半才失敗**。`generate_datagroup.sh` 的處理順序是 rpztw → phishtw → rpzip，所以 rpztw 比 phishtw 新就是死在 phishtw 那一步。這個現象與 6.3 的 LAB 重現完全吻合。

### 3.3 檔案數與停滯時間正相關

| 設備 | parsed/ 檔數 | 停滯 |
|---|---|---|
| 設備B | 285 | 7.0 天 |
| 設備C | 282 | 6.1 天 |
| 設備A | 267 | 2.3 天 |
| 設備D | 201 | 1.0 天 |

### 3.4 四台的失敗訊息完全相同

四份 log 的失敗片段都是同一個形式（Chinese 已還原）：

```
[INFO] 步驟 1/5: 檢查 RPZ Zone SOA Serial
[INFO] SOA Serial 已變更，繼續處理
[INFO] 步驟 2/5: 提取 DNS Express 資料
[INFO] dnsxdump 執行成功，匯出 434011 行資料
[INFO] 步驟 3/5: 解析 RPZ 記錄
[INFO] === 開始解析 RPZ 記錄 ===
[INFO] 載入 2 個 Zones: rpztw phishtw
[ERROR] RPZ 解析失敗
=== Exit Code: 1 ===
```

### 3.5 其他已證實的事實

- `grep -c "清理 dnsxdump 檔案完成" /config/snmp/rpz_wrapper.log` 四台都回 **0**。`main.sh:89` 的 `rm -f` 從來沒有執行過（見 12.1 缺陷 A）。
- `rpz_wrapper.log` 四台都超過 52 萬行，完全沒有 rotate。
- log 中另有 `[ERROR] DataGroup 產生失敗`（`main.sh:160`），對應步驟 4 的兩處缺陷。

### 3.6 檔案成長速率

設備A 的 raw/ 有 141 個檔案，跨 08-10 到 08-20 共 10 天，約 **14 個檔案/日**。這等於 SOA 變更的次數。

從 0 個檔案累積到 67 個上限，約需 **4~5 天**。

---

## 4. LAB 環境規格

所有驗證都在這台完成。與正式機的差異列在 11.2。

### 4.1 硬體與軟體

| 項目 | 值 |
|---|---|
| 主機 | `10.8.34.223`（hostname `cdns.ryantseng.work`） |
| 型態 | Virtual Edition |
| BIG-IP | 17.1.3.1 Build 0.0.6，Point Release 1，2026-01-20 |
| Kernel | Linux 3.10.0-862.14.4.el7.ve.x86_64 |
| bash | GNU bash 4.2.46(2)-release (x86_64-redhat-linux-gnu) |
| coreutils | ls (GNU coreutils) 8.22 |
| awk | GNU Awk 4.0.2 |
| CPU | 8 核 |
| 記憶體 | 16048 MB |
| `/proc/sys/fs/pipe-max-size` | 1048576 |
| `ARG_MAX` | 2097152 |

### 4.2 分割區

```
/dev/mapper/vg--db--vda-set.1._config  2.1G  /config
/dev/mapper/vg--db--vda-dat.share       15G  /shared   （/var/tmp 在此）
```

`/var/tmp` 與 `/config` 是不同分割區，所以所有測試輸出放 `/var/tmp` 不會影響 `/config` 空間。

### 4.3 RPZ 來源

| 項目 | 值 |
|---|---|
| Infoblox | `10.8.38.225`（只開 443，SSH 關閉） |
| DNS Express zone | `rpztw`、`phishtw`，皆 `response-policy yes`、`dns-express-server infoblox` |
| `dnsxdump` 輸出 | 185453 行 |
| SOA serial | rpztw 2372、phishtw 35 |
| 解析後筆數 | rpztw 58610、phishtw 819、rpzip 0 |

### 4.4 安裝的程式

`/config/snmp/RPZ_Local_Processor/`，7 支腳本。**測試開始前逐一比對過 md5，與 repo 完全一致**，所以測的就是正式機在跑的同一份程式碼。

| 檔案 | 原版 v1.2 md5 | 修正版 md5 |
|---|---|---|
| `check_soa.sh` | `19700e7c413d6c809dda6434292406cc` | 未修改 |
| `extract_rpz.sh` | `62aeaf053b08f3411fe530f33555c414` | 未修改 |
| `main.sh` | `0041c1d74e5b8514dea506608607b8c6` | 未修改 |
| `update_datagroup.sh` | `f8b038bc06df1c07050cd2922a91c5aa` | 未修改 |
| `utils.sh` | `3cab6cbca952f3780350e9882e5f7c11` | `b8294149dc978305e19bcd83fcb650e6` |
| `parse_rpz.sh` | `bbe45c6f79b56922388d4af7aa6e7583` | `cefa71b6623632dd51c60a51cdf72196` |
| `generate_datagroup.sh` | `35547d33ce109945d1ca17e8eb241e0a` | `91621717b6b11b11142333970693eb71` |

「修正版」欄位是 **Phase 1A（patch v2 / package v1.2.1）** 的值，也是目前
`scripts/` 內 tracked source 的值。第一版 patch（v1）的修正版 md5 為
`b15b77ba…` / `cef0a744…` / `05f80d69…`，已因審核 CR-01 作廢，不可使用。

### 4.5 iCall

```
sys icall handler periodic rpz_processor_handler {
    interval 300
    script rpz_processor_script
}
sys icall script rpz_processor_script {
    definition { exec /config/snmp/rpz_wrapper.sh }
}
```

正式機也是 300 秒。測試觀察期間曾暫時改為 60 秒加速，觀察完已改回 300 並存檔。

### 4.6 iRule 端到端測試用的物件

這些是為了驗證「DataGroup 真的能擋 DNS」而建立的，正式機不需要。

| 物件 | 內容 |
|---|---|
| `ltm virtual vs_rpz_irule_test_udp` | `10.8.38.199:53` udp，profiles `rpz_test_dns` + `udp_gtm_dns`，rule `rpzdg_local_v2` |
| `ltm virtual vs_rpz_irule_test_tcp` | 同上，tcp |
| `ltm profile dns rpz_test_dns` | 由 `dns` 繼承，`cache cdns`、`enable-cache yes` |
| `ltm rule rpzdg_local_v1` | 由 `irules/rpzdg_local_v1.tcl` 載入（控制組） |
| `ltm rule rpzdg_local_v2` | 由 `irules/rpzdg_local_v2.tcl` 載入 |
| `ltm data-group internal white_Domains` | 1 筆：`.safe.tmtkshop.com` |
| `ltm data-group internal blacklist_Domains` | 1 筆：`.localblock.invalid` |

`white_Domains` 與 `blacklist_Domains` 是 iRule 必要的相依 DataGroup，正式機本來就有，LAB 原本沒有所以建立。

### 4.7 存取方式

`admin` 已設 ed25519 public key 認證，shell 為 bash（advanced shell），`id` 顯示 `uid=0`。

---

## 5. 驗證方法與可重現步驟

所有測試腳本收錄在 `tests/lab/`。

| 腳本 | md5 | 用途 |
|---|---|---|
| `tests/lab/f5_pipefail_probe.sh` | `e93f448e6a13bfb848c441b27c831da5` | 合成測試：量測 `ls -t \| head -1` 在不同檔案數下的失敗率 |
| `tests/lab/f5_rate_probe.sh` | `efae5cbe377ed6a7ba7340d08c3b0af8` | **主要證據**：用真實 `parse_rpz.sh` 量測失敗率 |
| `tests/lab/f5_e2e_probe.sh` | `f1aacaf211daf8535a37d93ca5e235fa` | 用 `bash -x` 追出確切死亡行號 |
| `tests/lab/f5_manual_cleanup_test.sh` | `e7e6ff29982ff043291c8db8f88d10af` | 驗證手動刪檔能否在套 patch 前恢復 pipeline。**destructive，需 `--lab-only`** |
| `tests/lab/f5_hotfix_test.sh` | `47459a0d5dc8f335379c3f9575fcbc7b` | **Phase 1A 驗收矩陣 T1~T9**，可對原版或修正版執行，失敗回傳非零 |
| `tests/check_source_consistency.sh` | 見 15.1 | **CR-03 驗收 gate**：確認 tracked source、patch 內嵌內容、deployment package 三者一致。不需要 F5 |
| `patches/rpz_patch_sigpipe_v3.sh` | `685afe4c3e817abeb6a1861510a120f9` | **現行修正腳本**，含 check/apply/selftest/rollback/cleanup |
| `patches/rpz_patch_sigpipe_v1.sh` | `89fd74eb37ba512ede739df876040662` | **已作廢**，見第 16 節 CR-01。保留僅供對照 |

### 5.1 測試設計原則

**1. 路徑長度必須與 production 一致。** 決定失敗與否的是 `ls` 輸出的 byte 數，不是檔案數。所有測試目錄的路徑長度都刻意湊到與 production 相同：

- `/config/snmp/rpz_datagroups/raw/` = 32 bytes
- `/config/snmp/rpz_datagroups/parsed/` = 35 bytes
- `OUTPUT_DIR` 本身 = 27 bytes

腳本會印出實際長度供核對。

**2. 用真實程式碼，不用簡化版。** 見 10 節的教訓：自製的簡化重現曾經跑出與真實腳本矛盾的結果。

**3. 佔位檔用 0 bytes。** `ls -t` 只需要檔名與 mtime，內容不影響。這讓測試不佔磁碟空間。

### 5.2 重現主要證據（`f5_rate_probe.sh`）

```bash
# 1. 準備一份真實格式的 dnsxdump 樣本
/usr/local/bin/dnsxdump > /var/tmp/dnsxdump_sample.out

# 2. 確認腳本是原版 v1.2（若已套 patch，先 rollback）
bash /var/tmp/rpz_patch_sigpipe_v1.sh check

# 3. 執行，每個檔案數重複 30 次
bash /var/tmp/f5_rate_probe.sh 30
```

腳本做的事：在 `/var/tmp/rpz_e2e_probe_dirs`（27 bytes，與 production 同長）建立 `raw/`，填入指定數量的 0 bytes 佔位檔加一個真實樣本，然後呼叫真實的 `parse_rpz.sh`，統計非 0 退出碼的次數。

### 5.3 重現死亡行號（`f5_e2e_probe.sh`）

```bash
bash /var/tmp/f5_e2e_probe.sh /var/tmp/dnsxdump_sample.out /config/snmp/RPZ_Local_Processor/scripts
```

用 `bash -x` 執行真實的 `parse_rpz.sh` 與 `generate_datagroup.sh`，trace 保留在 `/var/tmp/rpz_e2e_trace/`。

### 5.4 重現手動刪檔的效果（`f5_manual_cleanup_test.sh`）

```bash
# 必須在原版 v1.2 的狀態下執行
REPS=20 bash /var/tmp/f5_manual_cleanup_test.sh
```

這支會直接操作 `/config/snmp/rpz_datagroups`，**只能在 LAB 執行**。

### 5.5 測試對 LAB 的影響範圍

| 動作 | 影響 |
|---|---|
| `f5_pipefail_probe.sh` | 只在 `/var/tmp`（加 `--on-config` 才會在 `/config` 建 0 bytes 假檔），測完自刪 |
| `f5_rate_probe.sh`、`f5_e2e_probe.sh` | 只在 `/var/tmp`，不呼叫 tmsh |
| `f5_manual_cleanup_test.sh` | **會直接操作 `/config/snmp/rpz_datagroups`**，包含執行 `main.sh --force` |
| `rpz_patch_sigpipe_v1.sh apply` | 覆寫三支腳本，備份到 `/var/tmp/rpz_patch_backup_<timestamp>/` |
| iRule 測試 | 新增 4.6 列的物件；`tmsh save sys config` |

---

## 6. 完整實測數據

### 6.1 主要證據：真實 `parse_rpz.sh` 的失敗率

環境見第 4 節。原版 v1.2，每組 30 次。

| raw/ 檔案數 | `ls` 輸出 | 失敗 | 失敗率 | 退出碼 |
|---|---|---|---|---|
| 5 | 305 B | 0/30 | 0% | — |
| 30 | 1830 B | 0/30 | 0% | — |
| **67** | **4087 B** | **0/30** | **0%** | — |
| **80** | **4880 B** | **5/30** | **17%** | **141** |
| 100 | 6100 B | 8/30 | 27% | 141 |
| 110 | 6710 B | 10/30 | 33% | 141 |
| 120 | 7320 B | 20/30 | 67% | 141 |
| 125 | 7625 B | 16/30 | 53% | 141 |
| 141 | 8601 B | 24/30 | 80% | 141 |
| 169 | 10309 B | 23/30 | 77% | 141 |
| 179 | 10919 B | 26/30 | 87% | 141 |
| 300 | 18300 B | 30/30 | 100% | 141 |

**分界精確落在 4096 bytes。** 67 檔（4087 B）0%，80 檔（4880 B）開始失敗。退出碼一律 141（SIGPIPE）。

125 檔（53%）低於 120 檔（67%）是取樣雜訊，各組 n=30，這個範圍的信賴區間重疊。整體趨勢單調上升。

### 6.2 修正後的同一組測試

| raw/ 檔案數 | `ls` 輸出 | 修正前 | 修正後 |
|---|---|---|---|
| 67 | 4087 B | 0% | 0% |
| 80 | 4880 B | 17% | **0%** |
| 100 | 6100 B | 27% | **0%** |
| 110 | 6710 B | 33% | **0%** |
| 120 | 7320 B | 67% | **0%** |
| 125 | 7625 B | 53% | **0%** |
| 141 | 8601 B | 80% | **0%** |
| 169 | 10309 B | 77% | **0%** |
| 179 | 10919 B | 87% | **0%** |
| 300 | 18300 B | 100% | **0%** |

### 6.3 步驟 4 的重現

`generate_datagroup.sh`，每 zone 的檔案數逐步增加，原版 v1.2：

| 每 zone 檔數 | 退出碼 | trace 顯示的死亡位置 |
|---|---|---|
| 5 | 0 | — |
| 67 | 0 | — |
| 95 | 141 | `generate_datagroup.sh:65` 的 rpztw glob |
| 141 | 141 | rpztw 已 `cp` 完成，死在 phishtw 的 glob |
| 200 | 141 | rpztw glob |
| 300 | 141 | rpztw glob |

n=141 的 trace：

```
[INFO] ✓ rpztw DataGroup: .../final/rpztw.txt (20000 筆)   <- rpztw 已 cp 完
+ count=1
+ for zone in "${zones[@]}"
+ local parsed_file
++ head -1
++ ls -t .../parsed/phishtw_*.txt                          <- 死在這裡
```

**這精確解釋了 3.2 的現象**：正式機 `final/rpztw.txt` 比 `final/phishtw.txt` 新，就是因為迴圈跑完 rpztw 才死在 phishtw。設備B 與 設備C 的 `rpzip.txt` 最舊，對應死在 `generate_datagroup.sh:82`。

### 6.4 完整 `main.sh` 的 before / after

raw/ 填到 180~181 檔（10980~11041 B），超過 設備B 的 179 檔。

**修正前**，退出碼 1：

```
[INFO] 步驟 2/5: 提取 DNS Express 資料
[INFO] dnsxdump 執行成功，匯出 185453 行資料
[INFO] 步驟 3/5: 解析 RPZ 記錄
[INFO] === 開始解析 RPZ 記錄 ===
[INFO] 載入 2 個 Zones: rpztw phishtw
[ERROR] RPZ 解析失敗
```

與 3.4 四台正式機的訊息一字不差。

**修正後**，退出碼 0，耗時 7 秒：

```
[INFO]   - rpztw: 58610 筆
[INFO]   - phishtw: 819 筆
[INFO] ✓ rpztw DataGroup: .../final/rpztw.txt (58610 筆)
[INFO] ✓ phishtw DataGroup: .../final/phishtw.txt (819 筆)
[INFO] ✓ DataGroup rpztw 建立成功
[INFO] ✓ DataGroup phishtw 建立成功
[INFO] 成功: 2 個, 失敗: 0 個, 跳過: 0 個
[INFO] 總耗時: 00:00:07
```

### 6.5 步驟 1（SOA 檢查）兩條分支

清除 SOA cache 後執行不帶 `--force` 的 `main.sh`：

| 執行 | 步驟 1 判定 | 結果 |
|---|---|---|
| 第 1 次（cache 不存在） | `SOA Serial 已變更，繼續處理` | 完整 5 步驟，退出碼 0，8 秒 |
| 第 2 次（cache 已最新） | `SOA Serial 未變更，無需更新` | 步驟 1 結束，退出碼 0 |

cache 寫入後為 `rpztw=2372 phishtw=35`，與 DNS Express 實際值一致。

### 6.6 iCall 自動執行

interval 暫時設 60 秒觀察，連續 5 輪：

| 時間 | 行為 | 退出碼 |
|---|---|---|
| 01:50:30 | 步驟 1 結束（SOA 未變更） | 0 |
| **01:51:01** | **完整 5 步驟，7 秒，DataGroup 更新成功** | **0** |
| 01:52:00 | 步驟 1 結束 | 0 |
| 01:53:00 | 步驟 1 結束 | 0 |
| 01:54:00 | 步驟 1 結束 | 0 |

當時 raw/ 有 180 個檔案（10980 B）。

### 6.7 DataGroup 實際載入

```
sys file data-group rpztw {
    checksum SHA1:2243064:c6cb61d836833feccb7759ba46c6d01b15163bb0
    revision 6
    size 2243064
    source-path file:/config/snmp/rpz_datagroups/final/rpztw.txt
```

`revision` 每次 `tmsh modify` 成功就 +1，證明 BIG-IP 確實重新讀取了檔案並記錄 checksum。

### 6.8 端到端 DNS 阻擋

測試 VS `10.8.38.199:53`，掛 `rpzdg_local_v2`（正式機現行版本）。

| 查詢 | 情境 | 回應 | DataGroup 內的值 |
|---|---|---|---|
| `tmtkshop.com` | 通配 key `.tmtkshop.com` apex | 34.102.218.71 | 34.102.218.71 |
| `abc.tmtkshop.com` | 通配 key 子網域 | 34.102.218.71 | 34.102.218.71 |
| `24hourtools.top` | 精確 key | 112.121.114.76 | 112.121.114.76 |
| `x.24hourtools.top` | 精確 key 的子網域 | 空（未擋） | 精確語意，正確 |
| `ertbob.com` | 通配 key `.ertbob.com` | 182.173.0.181 | 182.173.0.181 |
| `x.safe.tmtkshop.com` | 白名單 vs rpztw | 空（未擋） | 白名單優先，正確 |
| `test.localblock.invalid` | 本地黑名單 | 34.102.218.71 | iRule 硬編碼 |
| `www.google.com` | 無關的正常域名 | 142.251.x.x 共 8 筆 | iRule 不干擾 |
| `www.f5.com` | 無關的正常域名 | CNAME + 159.60.134.0 | iRule 不干擾 |
| `tmtkshop.com` AAAA | 被擋域名的非 A 查詢 | `SOA ns.rpz.local.` | else 分支 |
| `tmtkshop.com` TXT | 被擋域名的非 A 查詢 | `SOA ns.rpz.local.` | else 分支 |

三個不同的 landing IP 都與 `final/rpztw.txt` 的值一致，證明整條鏈通暢：

```
dnsxdump → parse_rpz.sh → final/ → tmsh modify → DataGroup → iRule → DNS 回應
```

`24hourtools.top` 是從 29574 個精確 key 中篩出「沒有同名通配版、且所有父網域也都沒有通配 key」的乾淨測試域名。

### 6.9 patch 腳本的功能驗證

| 子指令 | 驗證內容 | 結果 |
|---|---|---|
| `check` | 版本判定 | 原版→「待修正」、修正版→「已修正」，皆正確 |
| `apply` | 套用 + md5 驗證 + `bash -n` | 三支皆通過，印出 `diff -u` |
| `apply`（重複執行） | 冪等性 | 偵測到已是修正版，不動作 |
| `selftest` | raw 5/100/200/400 檔，各 20 次 | 步驟 3、步驟 4 全部 0 失敗 |
| `rollback` | 還原 | md5 精確回到原版 v1.2 |
| `apply` → `rollback` → `apply` | 來回 | 兩次 apply 的 md5 一致 |
| `cleanup-dry` | 預覽 | 正確列出 120 個待刪，`final/` 不在範圍 |
| `cleanup` | 實際刪除 122 檔 | `final/` 三個檔案的 md5 **完全沒變** |

`cleanup` 前後的 `final/` md5：

```
38b06b69d0375c0a899d30778484ca94  phishtw.txt
d41d8cd98f00b204e9800998ecf8427e  rpzip.txt
4e9e4af85539bd6e968b13b16acc00ea  rpztw.txt
```

刪除的 122 個全是 0 bytes 佔位檔，四個真實的 5 MB dnsxdump 檔（最新的）都保留。

---

## 7. 修正方案（第一階段）

### 7.1 改動內容

4 行功能變更 + 1 個新 helper。

| 檔案 | 變更 |
|---|---|
| `scripts/utils.sh` | 新增 `find_newest_file()`。加入 `export -f` 清單。補上原本缺少的結尾換行 |
| `scripts/parse_rpz.sh:227` | 改用 `find_newest_file` |
| `scripts/generate_datagroup.sh:65` | 改用 `find_newest_file`，找不到 artifact 明確 `die` |
| `scripts/generate_datagroup.sh:82` | 同上；rpzip 要求 artifact 存在但允許內容為空 |
| `scripts/generate_datagroup.sh` `prepare_final_datagroups()` | 改為 **resolve-then-publish** 兩階段：先解析所有 zone 的來源檔案並確認齊全，才開始 `cp` 到 `final/`。避免前面的 zone 已發布、後面的 zone 缺檔才失敗造成部分發布 |

```bash
find_newest_file() {
    local newest="" f
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        if [[ -z "$newest" || "$f" -nt "$newest" ]]; then
            newest="$f"
        fi
    done
    [[ -n "$newest" ]] || return 1
    printf '%s\n' "$newest"
}
```

呼叫端：

```bash
if ! dnsxdump_file=$(find_newest_file "${RAW_DATA_DIR}"/dnsxdump_*.out); then
    die "找不到 dnsxdump 輸出檔案: ${RAW_DATA_DIR}/dnsxdump_*.out"
fi
[[ -f "$dnsxdump_file" ]] || die "dnsxdump 輸出檔案不存在: $dnsxdump_file"
```

**不可以寫成 `|| dnsxdump_file=""`。** 那會把「找不到 artifact」從硬失敗轉成成功控制流，
是第一版 patch 被判 NO-GO 的主因（審核 CR-01）。詳見第 16 節。

### 7.2 不動的兩處

`check_soa.sh:33` 也有 `head -1`：

```bash
soa_serial=$($DNSXDUMP_CMD | grep "$zone_name" | grep SOA | awk '{print $7}' | head -1)
```

前面兩層 `grep` 已把輸出收斂到 1 行，遠低於 4096 bytes。實測 30 次 0 失敗，不在本次範圍。

`main.sh:118` 用的是 `tail -1`。`tail` 必須讀到 EOF 才能輸出，不會提早關閉 pipe，結構上安全。

### 7.3 patch 腳本

`patches/rpz_patch_sigpipe_v3.sh`（50 KB，單一檔案）。

```
check         檢查版本與現況（唯讀，預設）
apply         套用修正
selftest      驗證修正有效（在 /var/tmp 測，不碰 production）
rollback      還原到最近一次備份
cleanup-dry   列出建議刪除的舊檔（不刪）
cleanup       實際刪除舊檔，保留最新 KEEP 個（預設 60）
```

安全設計：

1. `apply` 前比對三支腳本的 md5，**不是原版 v1.2 就直接拒絕**。
2. 備份用 `mktemp -d`（含時間戳 + 隨機後綴），放 `/var/tmp`，與 `/config` 不同分割區。
   備份完成後驗證三檔 md5 確實是完整原版，否則中止。
3. 先把三檔全部寫到 staging 並通過 md5 + `bash -n` + `find_newest_file()` 存在檢查，
   才開始替換。
4. 每一檔用同目錄 temp file → `chmod/chown --reference` → `mv` 原子替換。
5. 安裝順序 provider 先（`utils.sh`）→ consumers 後。任一檔失敗時**依反序自動復原**
   已安裝的檔案，並驗證最終整體狀態。
6. `rollback` 反序執行（consumers 先、provider 後），避免出現「consumer 已是修正版但
   helper 已被移除」的窗口。還原前先驗證備份三檔都是完整原版，unknown 狀態預設拒絕。
7. `selftest` 有 16 項真正的 assertion，任一失敗回傳非零；隔離目錄用 `mktemp -d` +
   `trap` 清理；執行前確認版本狀態為修正版。
8. `cleanup` 的 `KEEP` 必須是 1~10000 的整數；scope 由 `zonelist.txt` 驅動；
   記錄實際刪除數與 `final/` 的 checksum 前後對照；`final/` 永遠不在刪除範圍。
9. `apply` / `rollback` / `cleanup` 會偵測執行中的 processor 並拒絕，
   除非設 `RPZ_PATCH_FORCE=1`。
10. 完整檔案內容嵌在腳本裡，不用 `sed` 猜位置。套用後印 `diff -u`。
11. 不碰 `final/`、不碰 DataGroup、不呼叫 `tmsh`、不重啟服務、不改 iCall。

**不需要重啟。** iCall 每次執行都重新讀取腳本，下一輪（最多 300 秒）自動生效。

---

## 8. 人力手動刪檔：可以做什麼、不能做什麼

給工程師的完整作業說明在 `RPZ_手動清檔作業說明_20260821.md`。本節是分析依據。

### 8.1 實測結果（全部用原版未修正的腳本）

| 情境 | raw/ | parsed/ 每 zone | 步驟 3 失敗 | 步驟 4 失敗 |
|---|---|---|---|---|
| A：raw/ 全清空，跑 `main.sh --force` | 0 | — | 5 步驟全過，58610 筆 | — |
| B：**只**清 raw/ 到 60 | 60（3660 B） | 95（5795 B） | **0/20** | **9/20（45%）** |
| C：raw/ 與 parsed/ 都清到 60 | 60（3660 B） | 60（3660 B） | **0/20** | **0/20** |
| D：完全不清（= 設備B 現況） | 179（10919 B） | 95（5795 B） | 17/20（85%） | 8/20（40%） |

### 8.2 結論

1. **`raw/` 的 dnsxdump 檔案全部刪掉沒有影響。** `main.sh` 步驟 2 每次執行都會產生一個新的。情境 A 實測確認。
2. **但只刪 `raw/` 不夠。** 步驟 4 的兩處缺陷在 `parsed/`，實測還有 45% 失敗率。
3. **`raw/` 和 `parsed/` 都清到 67 檔以下，pipeline 就完全恢復**，不需要套 patch。
4. **`parsed/` 的舊檔也可以安全刪除。** 步驟 3 每次執行都會產生新的。

### 8.3 這只能買到 4~5 天

檔案成長約 14 個/日（見 3.6）。從 0 累積到 67 個上限約 4~5 天。而且一旦執行成功，`cleanup()` 的 `find -mtime +7 -delete` 會開始運作，把檔案數維持在 8 天的量，約 **112 個檔案**，仍然遠超過 67。

**手動刪檔是爭取時間，不是修好。**

### 8.4 執行時的唯一注意事項

不要在 `main.sh` 執行到一半時刪檔。若刪掉步驟 2 產生、步驟 3 還沒讀的那個檔案，該次執行會失敗，而且因為 SOA cache 已經前進（見 12.4），那次更新要等下次 SOA 變更才會補上。

一次執行約 3~8 秒，iCall 每 300 秒觸發，窗口很小。用 `-mmin +10` 可完全避開。指令見 `RPZ_手動清檔作業說明_20260821.md` 第 5 節，該文件的所有指令已在 LAB 逐字驗證。

---

## 9. 現在該做什麼

| 順序 | 動作 | 效果 | 風險 |
|---|---|---|---|
| 1 | 四台手動刪 `raw/` + `parsed/` | 立即恢復 RPZ 更新、釋放 1.7~2.3 GB | 低，`final/` 不動 |
| 2 | 確認恢復：`final/` 三個檔案 mtime 一致 | 驗證 | 無 |
| 3 | 上 patch，從 設備D 開始 | 永久解除 67 檔上限 | 低，有 rollback |
| 4 | 觀察一輪後推其他三台 | | |

先做第 1 步的理由：不需要改任何程式碼，立刻讓黑名單恢復更新。設備B 已經停 7 天，這是安全面的優先事項。

上 patch 的步驟：

```bash
# 1. 停用 handler 並確認沒有執行中的 processor
tmsh modify sys icall handler periodic rpz_processor_handler status inactive
pgrep -fa 'rpz_wrapper|RPZ_Local_Processor/scripts/main.sh'

# 2. 套用
bash /var/tmp/rpz_patch_sigpipe_v3.sh check      # 唯讀，會拒絕版本不符的機器
bash /var/tmp/rpz_patch_sigpipe_v3.sh apply
bash /var/tmp/rpz_patch_sigpipe_v3.sh selftest   # 16 項 assertion，失敗回傳非零

# 3. 驗證
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
tmsh list sys file data-group | grep -E 'sys file data-group|revision|size'

# 4. 恢復 handler 並存檔（順序不可顛倒）
tmsh modify sys icall handler periodic rpz_processor_handler status active
tmsh save sys config

# 需要還原時
bash /var/tmp/rpz_patch_sigpipe_v3.sh rollback
```

注意：`main.sh --force` 內部會執行 `tmsh save sys config`。如果當時 handler 是
inactive，該狀態會被存進設定檔，所以第 4 步恢復 active 之後必須**再存一次**。

---

## 10. 分析過程回顧：推論 vs 事實

依 CLAUDE.md §4 的紀律，記錄推論錯誤與修正。

| 項次 | 當時的推論 | 實際情況 | 修正時機 |
|---|---|---|---|
| 1 | 磁碟滿導致 awk 寫入失敗，是步驟 3 失敗的原因 | **錯**。四台磁碟 60%~84%，都沒滿。缺陷與磁碟空間無關 | 收到四台 `df -h` 之後 |
| 2 | 磁碟滿與步驟 3 失敗形成自我強化迴圈 | 迴圈存在，但成因是**檔案數**不是磁碟空間 | 同上 |
| 3 | `check_soa.sh:33` 的 `head -1` 有 SIGPIPE 風險 | **錯**。前面兩層 grep 已收斂到 1 行，實測 30 次 0 失敗 | 實測後排除 |
| 4 | 設備A 停滯約 42 小時 | 實際 54.7 小時 | 用 `final/rpzip.txt` mtime 重算 |
| 5 | 「上線前必須先把 raw/ 清到 67 檔以下」 | **錯**。套用 patch 後檔案數與正確性無關 | 修正驗證完成後 |
| 6 | Linux 門檻約 4096 bytes、約 67 個檔案 | **正確**，實測 67 檔 4087 B → 0%，80 檔 4880 B → 17% | LAB 實測確認 |
| 7 | `x.www.sivvm.top` 依精確比對語意不該被擋 | **錯**。`.www.sivvm.top` 通配 key 確實在 DataGroup 裡，擋掉是對的。測試域名挑錯 | 查 DataGroup 內容後 |
| 8 | v2 iRule 尚未部署到 production | **錯**。正式機早已換成 v2。舊版 process.md §12 是過期資訊 | 使用者指正 |

### 10.1 測試方法上的教訓

中途用 `ssh 'bash -s' <<EOF` 的 heredoc 方式測 `ls|head`，在 125~179 檔跑出 0/200 不失敗，與原腳本的 55% 矛盾。原因是 bash 從 stdin 讀腳本會改變時序，是**測試框架造成的假象**。改用真實 `parse_rpz.sh` 測就沒有這個問題。

**教訓：測 race condition 要用真實程式碼，不要自製簡化版。** 這也是 `f5_rate_probe.sh` 直接呼叫 `parse_rpz.sh` 而非重寫管線的原因。

---

## 11. 分析的限制與未驗證項目

供 review 時判斷結論的適用範圍。

### 11.1 未直接驗證的項目

| 項目 | 狀態 | 說明 |
|---|---|---|
| 正式機上的失敗率 | **推估** | 6.1 的失敗率是 LAB 量測。正式機沒有直接執行過任何測試。四台的檔案數對應到 LAB 的 53%~87% |
| 正式機的 BIG-IP 版本 | **未知** | LAB 是 17.1.3.1。四台的版本沒有取得。若版本差異大到影響 glibc/coreutils 行為，門檻可能不同 |
| 正式機腳本的 md5 | **未驗證** | 假設與 repo 的 v1.2 一致。patch 腳本的 `check` 會在套用前比對，不符就拒絕 |
| 正式機 `parsed/` 的 per-zone 檔案數 | **推估** | 只取得總數（201~285），除以 3 個 zone 得到約 67~95。實際分布可能不均 |
| 正式機 `parsed/` 最新檔案的時間 | **未取得** | 診斷指令只做了 `ls -1 \| wc -l`，沒有 `ls -lt`。所以「步驟 3 最後一次成功的時間」無法精確判定 |

### 11.2 LAB 與正式機的差異

| 項目 | LAB | 正式機 |
|---|---|---|
| 型態 | Virtual Edition | i10800 實體機 |
| `/config` 大小 | 2.1 G | 3.2 G |
| CPU | 8 核 | 未知 |
| 負載 | 閒置 | 服務客戶 cache DNS，持續負載 |
| dnsxdump 行數 | 185453 | 434011 |
| rpztw 筆數 | 58610 | 約 141000 |

**負載差異值得注意。** SIGPIPE 是競態，`ls` 與 `head` 的相對排程會影響結果。忙碌的正式機理論上會讓 `ls` 在兩次 `write()` 之間被排程出去的機率更高，也就是**失敗率可能比 LAB 更高**，不會更低。這個方向對結論有利，但沒有實測。

### 11.3 結論的強度分級

| 結論 | 強度 |
|---|---|
| 缺陷位置是那三行 | **已證實**。`bash -x` trace 直接顯示 |
| 機制是 SIGPIPE，退出碼 141 | **已證實**。`PIPESTATUS` 顯示 `ls=141 head=0` |
| 門檻是 4096 bytes | **已證實**。67 檔 4087 B → 0/30，80 檔 4880 B → 5/30 |
| 修正有效 | **已證實**。同一組測試修正後全部 0%（patch v2 重新驗收過，見 16.3） |
| 這是四台停滯的原因 | **高度可信但非直接證實**。四台的 log 訊息與 LAB 重現一字不差、`final/` 的 mtime 落差與 6.3 的 trace 吻合、檔案數與停滯時間單調正相關。但沒有在正式機上執行測試 |
| 手動刪檔能恢復 | **已在 LAB 證實**，正式機未驗證 |

### 11.4 若 review 要進一步確認，建議補的資料

```bash
# 各台的版本
tmsh show sys version | head -8

# 各台腳本的 md5（確認與 repo v1.2 一致）
md5sum /config/snmp/RPZ_Local_Processor/scripts/*.sh

# parsed/ 的 per-zone 檔案數與最新時間
for z in rpztw phishtw rpzip; do
  echo "$z: $(ls -1 /config/snmp/rpz_datagroups/parsed/${z}_*.txt 2>/dev/null | wc -l) 檔"
  ls -lt --time-style=long-iso /config/snmp/rpz_datagroups/parsed/${z}_*.txt 2>/dev/null | head -2
done

# 各 glob 的實際 ls 輸出 bytes
for spec in "raw:dnsxdump_*.out" "parsed:rpztw_*.txt" "parsed:phishtw_*.txt" "parsed:rpzip_*.txt"; do
  d="/config/snmp/rpz_datagroups/${spec%%:*}"; p="${spec##*:}"
  echo "$spec -> $(ls -t $d/$p 2>/dev/null | wc -c) bytes"
done

# SOA cache 是否回退（見 12.5）
for z in rpztw phishtw; do echo "$z cache=$(cat /config/snmp/.${z}_soa_serial.last)"; done
/usr/local/bin/dnsxdump 2>/dev/null | grep -E '^(rpztw|phishtw)\.' | grep SOA | awk '{print $1, $7}'
```

---

## 12. 第二階段待辦（另案，需核准）

以下都不是本次上線範圍。

### 12.1 缺陷 A：每次執行後刪檔失效

`extract_rpz.sh:80` 用 `export DNSXDUMP_FILE=...` 想把路徑傳給 `main.sh`，但 `main.sh:141` 是用 `bash extract_rpz.sh` 呼叫（獨立子行程），`export` 傳不回父行程。因此 `main.sh:88` 的條件永遠是 false，`main.sh:89` 的 `rm -f` 從來沒執行過。四台 `grep -c "清理 dnsxdump 檔案完成"` 都回 0，已證實。

建議：`raw/` 改用固定檔名 `dnsxdump.out` 每次覆寫。raw/ 永遠只有 1 個檔，同時解決累積與檔案數問題。`main.sh:227` 已有 `--no-cleanup` 旗標可保留歷史檔案。

### 12.2 缺陷 B：cleanup 不在失敗路徑執行

`cleanup()` 只在 `main.sh:175` 被呼叫。`main.sh:130`、`:144`、`:153`、`:162`、`:171` 的 `exit 1` 都不會執行清理。

建議：擴充 `main.sh:253` 現有的 `trap ... ERR` 為 `EXIT`。同時在 `find -mtime +7` 之外加「只保留最新 N 個」的筆數上限。

### 12.3 缺陷 C：wrapper log 無 rotate

`config/icall_setup_api.sh:67` 產生的 wrapper 用 `>>` append，沒有任何 rotate。四台都超過 52 萬行。`config/cron_example.txt:83-85` 提到建議配合 logrotate，但 iCall 這條路徑沒有實作。

### 12.4 SOA cache 先寫入，失敗不回滾

`check_soa.sh:113` 的 `save_soa_cache` 在偵測到變更時立刻寫入新序號，才回傳 `UPDATE_NEEDED`。後續步驟失敗時 cache 已經是新的，下一次會判定 `NO_UPDATE`。**失敗的更新不會自動補跑**，必須手動 `--force` 或重置 cache。

### 12.5 SOA serial 回退會讓 pipeline 永久停擺（新發現）

`check_soa.sh:106` 的判斷是 `current_soa -le cached_soa` 就視為無變更。如果 RPZ 來源的 SOA serial 往回跳（Infoblox 重建、還原備份、zone 重新建立），cache 會永遠大於實際值，`check_soa.sh` **永遠**回 `NO_UPDATE`。log 每 5 分鐘印「SOA Serial 未變更」，看起來完全健康。只有手動刪 cache 才能恢復。

LAB 就是這個狀況：cache `rpztw 2947 / phishtw 44`，實際 `2372 / 35`。已用 `check_soa.sh reset` 清除。

四台正式機目前不是這個狀況（有在產生 dnsxdump，代表步驟 1 回 `UPDATE_NEEDED`）。確認指令見 11.4。

### 12.6 `cp` 非原子操作，且未檢查空檔（新發現）

`generate_datagroup.sh:68` 用 `cp "$parsed_file" "final/${zone}.txt"` 直接覆寫。`cp` 不是原子操作，中途中斷會留下**非空但只有一半**的檔案。`update_datagroup.sh:97` 和 `:152` 只檢查 `-s`（非空），截斷的檔案會通過檢查並被載入。

而且 `generate_datagroup.sh:67` 只檢查 `-f`（檔案存在），**沒有檢查 `-s`**。如果 `parsed/` 裡最新的檔案是 0 bytes，就會被 `cp` 到 `final/`，把來源檔案清空。

2026-08-21 在 LAB 實測撞到這個狀況：`final/rpztw.txt` 被清成 0 bytes。所幸 `update_datagroup.sh:152` 有 `-s` 檢查，空檔會被跳過，記憶體中的 DataGroup 維持 `size 2243064` 不變，**DNS 過濾沒有受影響**，下一次成功執行也會自動補回來。但磁碟上的來源檔案在那段期間是空的。

建議：
1. `cp` 到暫存檔再 `mv`（同分割區的 `mv` 是原子的）。
2. `generate_datagroup.sh:67` 的條件改為 `[[ -f "$parsed_file" && -s "$parsed_file" ]]`。
3. 加最小筆數檢查，例如新檔案筆數低於舊檔案的 80% 就拒絕載入並告警。

### 12.7 沒有 lock 機制

`scripts/` 與 `config/` 完全沒有 `flock`、lock file 或 pidfile。iCall 間隔 300 秒，步驟 1 對 2 個 zone 各跑一次完整 `dnsxdump`，步驟 2 再跑一次，共三次。若單次執行超過 300 秒會重疊，可能造成 A 寫了 SOA cache、B 讀到新序號判定 `NO_UPDATE`，該次變更被吞掉。

LAB 實測單次執行 7~8 秒，目前不會重疊，但沒有保護。

### 12.8 `soa_check_exit` 永遠是 0

`main.sh:119` 的 `$?` 取的是 command substitution 裡管線最後一段（`tail -1`）的退出碼，不是 `check_soa.sh` 的。所以 `main.sh:128` 的錯誤訊息永遠印「退出碼: 0」，會誤導診斷。

### 12.9 文件更新

- `docs/SCRIPT_SPECIFICATIONS.md` — `main.sh` 的後置條件與環境變數段落
- `docs/TRAINING_GUIDE.md` — 問題排查章節新增本案例
- `docs/archive/KNOWN_ISSUES.md` — 新增條目
- `README.md:149` 與 `INSTALL_GUIDE.txt:109` 寫的 iCall handler 名稱是舊的 `rpz_update_handler`，實際是 `rpz_processor_handler`（`config/icall_setup_api.sh:136`）

---

## 13. 禁止事項

- **不要刪除 `/config/snmp/rpz_datagroups/final/` 的檔案。** External DataGroup 的 `source-path` 指向那裡（`scripts/update_datagroup.sh:112`）。刪掉會讓 DataGroup 失效，DNS 過濾直接停止。
- **不要刪除 `/config/snmp/.{zone}_soa_serial.last`**，除非是刻意要強制重跑。
- **不要在 `main.sh` 執行中刪 `raw/` 或 `parsed/` 的檔案。** 用 `-mmin +10` 避開。
- **不要在正式機執行 `tests/lab/` 底下的任何腳本。** 特別是 `f5_manual_cleanup_test.sh`，它會直接操作 `/config/snmp/rpz_datagroups` 並執行 `main.sh --force`。
- **不要 `git push`。** 需明確要求。

---

## 14. 環境與路徑速查

### 14.1 正式機

| 項目 | 值 |
|---|---|
| 設備 | 設備A、設備B、設備C、設備D |
| 服務對象 | 客戶 cache DNS |
| 存取方式 | 透過經銷商工程師，無直接 SSH |
| iRule | 已是 `rpzdg_local_v2.tcl`（`docs/TCL_Error_Analysis_20260324.md` 的問題已解決） |

### 14.2 F5 上的路徑

```
/config/snmp/RPZ_Local_Processor/       程式安裝目錄
├── scripts/                            7 支 shell script
└── config/zonelist.txt                 zone 清單（rpztw、phishtw）

/config/snmp/rpz_datagroups/
├── raw/dnsxdump_YYYYmmdd_HHMMSS.out    dnsxdump 原始輸出，約 11.5 MB/檔
├── parsed/{zone}_YYYYmmdd_HHMMSS.txt   AWK 解析結果
└── final/{zone}.txt                    DataGroup source，不可刪

/config/snmp/.rpztw_soa_serial.last     SOA cache
/config/snmp/.phishtw_soa_serial.last   SOA cache
/config/snmp/rpz_wrapper.sh             iCall 呼叫的 wrapper
/config/snmp/rpz_wrapper.log            wrapper 輸出，無 rotate
```

### 14.3 iCall

| 項目 | 值 |
|---|---|
| Handler | `rpz_processor_handler`（`config/icall_setup_api.sh:136`） |
| Script | `rpz_processor_script` |
| 間隔 | 300 秒 |
| 注意 | `README.md:149` 與 `INSTALL_GUIDE.txt:109` 寫的 `rpz_update_handler` 是舊名稱 |

### 14.4 執行流程

```
iCall (300s)
  └─ rpz_wrapper.sh
       └─ main.sh
            ├─ 步驟 1  check_soa.sh          比對 SOA，未變更就 exit 0
            ├─ 步驟 2  extract_rpz.sh        dnsxdump → raw/
            ├─ 步驟 3  parse_rpz.sh          AWK 解析 → parsed/     <- 缺陷 :227
            ├─ 步驟 4  generate_datagroup.sh cp → final/            <- 缺陷 :65 :82
            ├─ 步驟 5  update_datagroup.sh   tmsh modify data-group
            └─ cleanup()                     只有全部成功才會跑到
```

---

## 15. 相關檔案

### 15.1 本次事件產出

| 檔案 | md5 | 說明 |
|---|---|---|
| `process.md` | — | 本文件 |
| `docs/reviews/CODE_REVIEW_20260821.md` | — | 獨立審核報告，見第 16 節 |
| `RPZ_手動清檔作業說明_20260821.md` | — | 給經銷商工程師的緊急處置作業說明（v2），指令已在 LAB 逐字驗證 |
| `patches/rpz_patch_sigpipe_v3.sh` | `685afe4c3e817abeb6a1861510a120f9` | **現行**上線用的 patch 腳本 |
| ~~`patches/rpz_patch_sigpipe_v1.sh`~~ | `89fd74eb37ba512ede739df876040662` | **已作廢並移除**（第一輪 CR-01），紀錄見 `patches/README.md` |
| ~~`patches/rpz_patch_sigpipe_v2.sh`~~ | `45bac9de5ed19460330cbbb807a6fb82` | **已作廢並移除**（第二輪 R2-01/02/05），紀錄見 `patches/README.md` |
| `tests/lab/f5_hotfix_test.sh` | `47459a0d5dc8f335379c3f9575fcbc7b` | Phase 1A 驗收矩陣 T1~T9 |
| `tests/check_source_consistency.sh` | `92b42e8966c2c4d297dff86fab5aad2b` | CR-03 驗收 gate，不需要 F5 |
| `dist/DO_NOT_DEPLOY.md` | — | 標示哪些 deployment artifact 不可部署 |
| `tests/lab/f5_rate_probe.sh` | `efae5cbe377ed6a7ba7340d08c3b0af8` | 主要證據的測試腳本 |
| `tests/lab/f5_e2e_probe.sh` | `f1aacaf211daf8535a37d93ca5e235fa` | `bash -x` 追行號 |
| `tests/lab/f5_pipefail_probe.sh` | `e93f448e6a13bfb848c441b27c831da5` | 合成測試 |
| `tests/lab/f5_manual_cleanup_test.sh` | `e7e6ff29982ff043291c8db8f88d10af` | 手動刪檔效果驗證。**destructive，需 `--lab-only`** |

### 15.2 原始證據

| 檔案 | 說明 |
|---|---|
| `IMG_5023.JPG` | 工程師 2026-08-20 回傳的 `find /config` 擷圖，最初的線索 |
| `客戶診斷資料_20260820/` | 四台的完整診斷輸出（PuTTY log，Chinese 字元遺失） |

### 15.3 既有文件

| 檔案 | 說明 |
|---|---|
| `docs/SCRIPT_SPECIFICATIONS.md` | 7 支腳本的規格、exit code、環境變數 |
| `docs/TRAINING_GUIDE.md` | 教育訓練手冊，含問題排查章節 |
| `docs/TCL_Error_Analysis_20260324.md` | iRule `class match` 缺 `--` 的分析。**已解決**，正式機已是 v2。§6.3 的驗證計畫已於 2026-08-21 在 LAB 補跑完成（結果見 6.8） |
| `irules/rpzdg_local_v1.tcl` | 舊版，LAB 當控制組用 |
| `irules/rpzdg_local_v2.tcl` | 正式機現行版本 |

---

## 16. 獨立審核回應與 Phase 1A 修正

2026-08-21 由獨立 review 產出 `docs/reviews/CODE_REVIEW_20260821.md`，對第一版 patch
（`patches/rpz_patch_sigpipe_v1.sh`）判定 **NO-GO**。本節記錄回應與修正。

審核確認 root cause 與 `find_newest_file()` 的方向正確，NO-GO 的原因全部在
patch artifact 本身，不在 root cause 分析。

### 16.1 我自己重新驗證審核指控的結果

沒有直接照收，全部在 LAB 用隔離副本重跑。

| 編號 | 指控 | 我的驗證方式 | 結果 |
|---|---|---|---|
| CR-01 | missing parsed 從 hard failure 變成 false success | 同一組空 `parsed/`，原版 vs v1 修正版，`final/` 預先放非空舊資料 | **成立**。原版 `exit=2`、final 2 檔；v1 修正版 `exit=0`、final 3 檔 |
| CR-02 | selftest 永遠不因測試失敗而失敗 | 把 `parse_rpz.sh` 換成 `exit 42` 跑 v1 selftest | **成立**。四組全部失敗，selftest 仍回傳 0 |
| CR-04 | rollback 順序不安全、非原子 | 讀 `FILES` 與 rollback 迴圈 | **成立**。`utils.sh` 先被還原成沒有 helper 的版本；且用 `cp -p` 非原子 |
| CR-05 | `KEEP` 未驗證 | `KEEP=0` → `tail -n +1` | **成立**。5 個檔全部列出，含最新的 |
| CR-06 | SOA 取得錯誤被誤判為 `NO_UPDATE` | 把 `dnsxdump` 換成 `exit 1` | **成立**。兩個 zone 都 `[ERROR] 無法取得 SOA Serial`，但輸出 `NO_UPDATE`、`exit 0` |

### 16.2 CR-01 的檢討

第一版的寫法是：

```bash
parsed_file=$(find_newest_file "${PARSED_DATA_DIR}/${zone}_"*.txt) || parsed_file=""
if [[ -f "$parsed_file" ]]; then cp ... ; else touch "final/${zone}.txt"; fi
```

原版靠 `ls` 的非零退出碼 + `pipefail` 達到「找不到 artifact 就硬失敗」。加上
`|| parsed_file=""` 之後，那個 `else` 分支（原本幾乎不可達的死碼）變成可達，
結果是 `touch final/` 然後整個 step 回報成功。

**這和本次要修的缺陷是同一類：把失敗變成靜默的成功。**

而且它污染了本文件自己的診斷依據。第 3.2 節用 `final/rpzip.txt` 的 mtime
當「step 4 最後一次完成」的標記，但一個什麼都沒做的執行也會 touch 它。

當時只想著「不要讓 `set -e` 誤殺」，沒有回頭問「原本的失敗語意是什麼、
我是否改變了它」。這是設計層面的疏漏，不是筆誤。

### 16.3 Phase 1A 的修正與驗收證據

#### CR-01 — missing artifact 恢復硬失敗，且不部分發布

`prepare_final_datagroups()` 改為 resolve-then-publish 兩階段。找不到 artifact
明確 `die`；`rpzip` 要求 artifact 存在但允許內容為空（維持原版行為，也保住
`final/rpzip.txt` 作為 step 4 完成標記的意義）；FQDN zone 的 artifact 為 0 bytes
時記 warning 但仍複製（維持原版行為，資料完整性政策留給第二階段的 CR-10）。

驗收用 `tests/lab/f5_hotfix_test.sh`，T1~T9 對原版與修正版各跑一次：

| 測試 | 內容 | 原版 v1.2 | Phase 1A 修正版 |
|---|---|---|---|
| T1 | 正常 parse：3 個 parsed、rpztw 400 / phishtw 150 / rpzip 0 筆 | PASS | PASS |
| T2 | 取 mtime 最新的 raw | PASS | PASS |
| T3 | raw 空 → parse 非零、不產出 parsed | PASS (exit 2) | PASS (exit 1) |
| T4 | 正常 generate：final 來自最新 parsed | PASS | PASS |
| T5 | parsed 全空 → 非零、final 不變 | PASS | PASS |
| T6 | 只缺 phishtw → 非零、**不得部分發布** | 非零但**發生部分發布**（原版既有缺陷） | **PASS，final 完全未變動** |
| T7 | rpzip 存在但 0 bytes → 成功 | PASS | PASS |
| T8 | raw 300 檔（18361 B）× 20 次 | **19/20 失敗** | **0/20 失敗** |
| T9 | parsed 每 zone 300 檔 × 20 次 | **20/20 失敗** | **0/20 失敗** |
| 合計 | | PASS=16 FAIL=0 | PASS=17 FAIL=0 |

T8/T9 原版的高失敗率同時證明測試環境確實會觸發缺陷，所以修正版的 0 失敗有意義。

#### CR-02 — selftest 加入真正的 assertion

`do_selftest` 改為在 subshell 執行、`mktemp -d` 建隔離目錄、`trap` 清理、
執行前確認版本狀態為修正版，並包含 16 項 assertion（S1~S9），
任一失敗回傳非零。

反向測試（證明 assertion 本身會擋，不只是靠 md5 狀態檢查）：

| 反向測試 | 手法 | 退出碼 | 結果 |
|---|---|---|---|
| md5 unknown | 隔離 INSTALL_DIR 放壞掉的 `parse_rpz.sh` | 1 | 拒絕執行 |
| parse 固定 exit 42 | 把 patch 的 md5 表改成接受壞檔，讓狀態檢查通過 | 1 | PASS=10 **FAIL=3** |
| generate 固定 exit 43 | 同上 | 1 | PASS=12 **FAIL=3** |
| `BACKUP_ROOT` 不存在 | `BACKUP_ROOT=/nonexistent/xyz` | 1 | `[FAIL] 無法建立測試目錄` |

另外修了一個自己引入的 bug：`BASE` 原本宣告為 `local`，但 EXIT trap 在函數返回
後才執行，屆時變數已出範圍，配合 `set -u` 造成清理失敗、temp 目錄外洩。
改為不使用 `local`（整個函數在 subshell 內，不會外洩到父 shell）並用 `${BASE:-}`。

（附帶記錄一個測試設計錯誤：原本想用 `chmod 555` 讓 `mktemp` 失敗，但 BIG-IP 的
`admin` 是 uid 0，root 會忽略目錄權限，所以那個測試無效。改用不存在的路徑才有效。）

#### CR-04 — apply/rollback 改為 transaction

驗收：

| 測試 | 結果 |
|---|---|
| 正常 rollback 的順序 | `parse_rpz.sh` → `generate_datagroup.sh` → `utils.sh`，consumers 先、provider 後 |
| 備份被破壞 → 必須拒絕 | `[FAIL] 備份的 utils.sh 不是完整原版，中止（不做任何變更）`，安裝目錄 md5 未變 |
| unknown 狀態 → rollback 拒絕 | `[FAIL] 目前是未知版本。若確定要強制還原，請設 RPZ_PATCH_FORCE=1` |
| 第三檔安裝失敗 → 自動復原 | 用 `chattr +i` 讓 `generate_datagroup.sh` 無法替換。`[FAIL] 安裝 generate_datagroup.sh 失敗，開始復原` → `[WARN] 已復原 parse_rpz.sh` → `[WARN] 已復原 utils.sh`，三檔 md5 全部回到原版 |

#### CR-05 — cleanup 參數與 scope

| 測試 | 結果 |
|---|---|
| `KEEP=0` | `[FAIL] KEEP 必須 >= 1（目前 0）。KEEP=0 會刪掉最新的檔案。` |
| `KEEP=-1` / `KEEP=abc` | `[FAIL] KEEP 必須是非負整數` |
| `KEEP=99999` | `[FAIL] KEEP 上限 10000` |
| scope 由 `zonelist.txt` 驅動 | 目錄裡刻意放的 `unrelated_file.txt` 未被列入、未被刪除 |
| 實際刪除數核對 | `預計刪除 360 個，實際刪除 360 個，錯誤 0 個` |
| `final/` checksum 前後對照 | `[ OK ] final/ checksum 未變動` |
| 執行中的 processor 偵測 | 造假 process 後 `[FAIL] 偵測到執行中的 processor (PID: …)` |

#### CR-16 — destructive LAB 測試加防呆

`tests/lab/f5_manual_cleanup_test.sh` 現在：預設拒絕執行（需 `--lab-only`）、
檢查 production marker（`final/rpztw.txt` 非空即拒絕）、檢查 hostname、
執行前印出會被操作的確切路徑、開頭有 DESTRUCTIVE LAB ONLY 標示。

驗收：無參數 exit 2；只帶 `--lab-only` 但 hostname 不符 exit 2；
在 LAB 上 hostname 相符但 `final/` 非空仍 exit 2。

#### Phase 1B — LAB 完整驗收

```
腳本狀態      三支皆 Phase 1A 修正版
raw/          200 檔，ls 輸出 12200 bytes（遠超 4096）
main.sh --force  退出碼 0，耗時 7 秒
              rpztw 58610 筆、phishtw 819 筆
DataGroup     revision 7 -> 8，size 2243064 / 30862
final/        三個檔案 mtime 一致
handler       已恢復 active 並 tmsh save sys config
```

apply → selftest → rollback → apply 的來回也驗過，md5 每次都精確。

### 16.4 文件修正（DOC-01 ~ DOC-05）

`RPZ_手動清檔作業說明_20260821.md` 已更新為 v2：

| 項目 | 修正 |
|---|---|
| DOC-01 | 4096 改述為「`ls` 在 C 函式庫層的輸出緩衝區，**不是** Linux 管線容量」，並明說是時序競態、不是必然失敗 |
| DOC-02 | 成功判準改為**兩個條件**：`final/` 三個 mtime 一致 **且** `sys file data-group` 的 `revision` 增加。並說明只看 mtime 不足以證明 step 5 已成功 |
| DOC-03 | 失敗率標明為「依 LAB 同檔案數推估，四台上沒有直接量測過」 |
| DOC-05 | **新增步驟 0（停用 handler + `pgrep` 確認）與步驟 F（恢復 + `save sys config`）**；log rotation 改為同目錄 `mv` → `touch` → 再移到 `/var/tmp`；`find` 全部加 `-maxdepth 1`；步驟 A/E 都要記錄 `md5sum final/*` |
| CR-06 | 新增「等很久都沒更新的兩種可能」，第二種是 SOA 取不到，附判斷指令 |

本文件（`process.md`）的 3.2 節依 DOC-02 保留 mtime 表格，但已在該節與 11.3 節
說明那是「step 4 完成時間」，是完整成功的**上限證據**，不是 step 5 已成功的證明。

### 16.5 尚未處理的項目

Phase 1A 只處理第一階段的 blocker 與 High。以下留給後續，對應第 12 節：

| 審核編號 | 內容 | 本文件對應 |
|---|---|---|
| CR-03 | tracked source 與 deployment package 仍是缺陷版 | **已完成**，見 16.6 |
| CR-06 | SOA 取得錯誤被誤判為 `NO_UPDATE` | 12.5 的延伸。已在 LAB 重現 |
| CR-07 | SOA cache 在完整成功前提交 | 12.4 |
| CR-08 | SOA serial 不支援回退或 rollover | 12.5 |
| CR-09 | 沒有全流程 lock | 12.7 |
| CR-10 | artifact 與 final 發布缺乏 transaction / 完整性門檻 | 12.6 |
| CR-11 | cleanup 與磁碟生命週期設計不足 | 12.2、12.3 |
| CR-12 | `cleanup.sh` 的保留 DataGroup 選項不安全 | 新增，本文件原本未涵蓋 |
| CR-13 | RPZ IP DataGroup backend 型別不一致 | 新增 |
| CR-14 | iCall setup 的認證與更新流程不安全 | 新增 |
| CR-15 | Zone 設定未驗證，export 架構誤解 | 12.1 的延伸 |
| DOC-06 | 同步 `docs/SCRIPT_SPECIFICATIONS.md` 等規格文件 | 12.9 |

### 16.6 CR-03 — 已完成

`scripts/` 的三支腳本已更新為修正版，deployment package 已重建。

| 檔案 | 原版 v1.2 | 現行（v1.2.1） |
|---|---|---|
| `scripts/utils.sh` | `3cab6cbca952f3780350e9882e5f7c11` | `b8294149dc978305e19bcd83fcb650e6` |
| `scripts/parse_rpz.sh` | `bbe45c6f79b56922388d4af7aa6e7583` | `cefa71b6623632dd51c60a51cdf72196` |
| `scripts/generate_datagroup.sh` | `35547d33ce109945d1ca17e8eb241e0a` | `9599755a54db53652c070cd70ae92652` |

其餘四支（`check_soa.sh`、`extract_rpz.sh`、`main.sh`、`update_datagroup.sh`）未修改。

`staging/` 目錄已移除。留著會形成第二個 source of truth，正是 CR-03 要避免的問題。
audit trail 由 git history 保留。

#### package 的變更

| 項目 | 內容 |
|---|---|
| `package.sh` | `VERSION` 由 `1.2` 升到 `1.2.1`；新增 `SHA256SUMS` manifest 產生與自我驗證；新增 `VERSION` 檔案；輸出整包的 `.sha256` |
| `install.sh` | 新增步驟 1「驗證部署包完整性」：讀 `VERSION`、`sha256sum -c SHA256SUMS`，不通過就拒絕安裝。舊版包（無 manifest）只警告不阻擋，維持向後相容。`INSTALL_DIR` / `OUTPUT_DIR` 改為可用環境變數覆寫，供隔離安裝測試 |
| `dist/DO_NOT_DEPLOY.md` | 明確標示 `rpz_local_processor_v1.2_20251202_140235.tar.gz` 與根目錄 29 bytes 的 `RPZ_Local_Processor.tar.gz` 不可部署。兩者**刻意保留未刪除** |
| `.gitignore` | 由 `dist/` 改為 `dist/*` + `!dist/DO_NOT_DEPLOY.md`，讓狀態說明能進版控，tarball 仍排除 |

`package.sh` 只複製 `scripts/`、`config/zonelist.txt`、`config/icall_setup_api.sh`、
`install.sh`、`cleanup.sh`、`INSTALL_GUIDE.txt`。`tests/` 與 `patches/` **不在打包範圍**
（也是 CR-16 的要求）。

#### CR-03 驗收證據

`tests/check_source_consistency.sh`，本機執行，**PASS=22 FAIL=0**：

| 檢查 | 結果 |
|---|---|
| `scripts/` 無殘留 `ls -t \| head -1`（排除註解） | PASS |
| 20 支 shell script 語法檢查 | PASS |
| patch 內嵌內容與 `scripts/` byte-for-byte 一致 | PASS ×3 |
| patch 的 `MD5_NEW` 與 `scripts/` 相符 | PASS ×3 |
| patch 的 `MD5_ORIG` 是原版 v1.2 的值 | PASS ×3 |
| package 的 7 支 script 與 tracked source 一致 | PASS ×7 |
| package 的 `SHA256SUMS` 驗證通過 | PASS |
| package 有 `VERSION`（1.2.1） | PASS |
| package 未包含 `tests/` 與 `patches/` | PASS |

LAB 上的 package 驗收：

| 測試 | 結果 |
|---|---|
| 整包 `sha256sum -c *.sha256` | OK |
| 解開後 `sha256sum -c SHA256SUMS`（13 個檔案） | 退出碼 0 |
| **篡改偵測**：在 `scripts/parse_rpz.sh` 加一行後跑 `install.sh` | `✗ SHA256SUMS 驗證失敗，部署包可能損毀或被修改`，**退出碼 1** |
| 還原後 manifest | 通過 |
| 從新 package 安裝到隔離目錄 `/var/tmp/isolated/` | 7 個步驟全過，版本顯示 1.2.1 |
| 安裝結果的 7 支 script md5 | 與 tracked source 完全相同 |
| 對隔離安裝跑 `f5_hotfix_test.sh fixed` | **PASS=17 FAIL=0** |

#### 尚未做的

`docs/SCRIPT_SPECIFICATIONS.md`、`docs/TRAINING_GUIDE.md`、
`docs/archive/KNOWN_ISSUES.md`、`README.md`、`INSTALL_GUIDE.txt` 尚未同步
（審核 DOC-06、本文件 12.9）。`README.md:149` 與 `INSTALL_GUIDE.txt:109` 的
iCall handler 舊名稱也還沒改。

---

## 17. 第二輪獨立審核回應

2026-08-21 第二輪審核產出 `docs/reviews/CODE_REVIEW_PHASE1A_ROUND2_20260821.md`，對
Phase 1A（patch v2）判定 **NO-GO**，提出 R2-01 ~ R2-07。

審核確認核心 SIGPIPE 修正、CR-01 的 missing artifact 硬失敗、CR-02 的 assertion
有效性、patch 與 tracked source 與 package 的一致性都通過。NO-GO 的原因全部在
周邊的安全邊界與 failure path。

### 17.1 我自己重新驗證的結果

| 編號 | 嚴重度 | 指控 | 我的驗證 | 結果 |
|---|---|---|---|---|
| R2-01 | Blocker | cleanup 可經 zone path traversal 越出 `parsed/` | zonelist 放 `../final/evil`，觀察 `cleanup_specs` 與 glob 展開 | **成立**。glob 展開到 `final/` 的檔案，字串前綴 guard 沒擋住，`readlink -f` 確認 canonical 在 `final/` |
| R2-02 | High | rollback 任一檔失敗留下混合版本 | `chattr +i` 鎖第二個 rollback target | **成立**。結果 `utils=new parse=orig generate=new` |
| R2-03 | High | destructive LAB test 的 guard 與 target 不一致 | 讀 code：guard 用 `DATA_DIR_CHK`，主體用硬編碼 `D` | **成立** |
| R2-04 | High | installer 在 manifest 或工具缺少時 fail-open | 讀 code：三種缺失都只 warning | **成立** |
| R2-05 | Medium | `REPS=0` 可繞過壓力測試 | `REPS=0` 跑 selftest | **成立**。S8/S9 各 0 次，`PASS=16`，退出碼 0 |
| R2-06 | Medium | consistency gate 覆蓋不足 | 讀 code：只比對 `scripts/` | **成立** |
| R2-07 | Medium | installer 路徑 override 無安全邊界 | 讀 code：無任何驗證 | **成立** |

### 17.2 我自己錯誤的共同模式

三個 finding 是同一個失敗模式：**加了檢查，但沒有驗證檢查真的綁到它要保護的東西。**

| 案例 | 檢查看起來在保護 | 實際上 |
|---|---|---|
| 第一輪 CR-02 | selftest 驗證修正有效 | 沒有 assertion，永遠回傳 0 |
| 第二輪 R2-03 | guard 保護 destructive 操作 | guard 檢查的路徑與實際操作的路徑不同 |
| 第二輪 R2-01 | `final/` 永不在刪除範圍 | 字串前綴比對可被 `../` 繞過 |

前一輪我寫「這和本次要修的缺陷是同一類：把失敗變成靜默的成功」，但沒有把那個
教訓推廣成「每個新增的檢查都要用反向測試證明它會擋」。這一輪的所有修正都補了
反向測試。

### 17.3 R2-01 — cleanup scope

**修正**（`patches/rpz_patch_sigpipe_v3.sh`）：

| 新增 | 作用 |
|---|---|
| `validate_zone()` | 拒絕空值、`-` 開頭、`.`/`..`、路徑分隔符、`..`、`:`、glob 字元 `* ? [ ]`，以及 `A-Za-z0-9._-` 以外的任何字元 |
| `get_validated_zones()` | 讀 zonelist，任一 zone 不合法或**重複**就整體失敗，不做部分處理 |
| `validate_data_dir()` | `DATA_DIR` 必須是絕對路徑、不可為 `/`、不可含 `..`、canonical 不可為 `/` |
| `safe_victim()` | 刪除前用 `cd … && pwd -P` 取 canonical parent，必須**精確等於**允許的目錄。不依賴字串前綴 |
| `build_cleanup_specs()` | scope 在任何檔案列舉之前就決定並驗證完畢 |

`cleanup` 與 `cleanup-dry` 都會先驗證，驗證失敗直接回傳非零且**不列舉任何檔案**。
`deleted != planned` 時回傳非零並說明原因。

**驗收**（LAB，`PASS=36 FAIL=0`）：

| 測試 | zone 值 | 結果 |
|---|---|---|
| A1 | `rpztw` `phishtw` | scope 只有 raw 與各 zone 的 parsed，未含 `../final` |
| A2 | `../final/evil` | 拒絕，退出碼 1，未列舉任何檔案，`final/` 完全未變（含刻意放的 `evil_*.txt`） |
| A3a | `../../outside` | 拒絕 |
| A3b~d | `*`、`?`、`[abc]` | 拒絕 |
| A3e | `-rf` | 拒絕 |
| A3f | `zone with space` | 拒絕 |
| A4 | `rpztw` 出現兩次 | 拒絕 |
| A2-real | `../final/evil` 跑實際 `cleanup` | 拒絕，`final/` 完全未變 |

### 17.4 R2-02 — rollback failure transaction

**修正**：`do_rollback()` 在開始還原之前先產生 **recovery staging**（從 embedded
new source 產生並驗 md5 與語法）。任一檔還原失敗或還原後 md5 不是原版時，
呼叫 `recover_to_new()` 把三支全部切回修正版，然後 `report_file_states()`
印出每支檔案的實際 md5 與分類，回傳非零。

`restore_from()` 改為彙總失敗並回傳非零，`do_apply()` 的呼叫端會檢查。
`.rpz_patch_last_backup` 寫入失敗不再靜默，會回傳非零並告知用
`BACKUP_DIR=` 明確指定。

**驗收**：

| 情境 | 最終狀態 | 退出碼 |
|---|---|---|
| B3 正常 rollback | `orig orig orig` | 0 |
| B4 鎖 `parse_rpz.sh` | `new new new` | 非零 |
| B4 鎖 `generate_datagroup.sh` | `new new new` | 非零 |
| B4 鎖 `utils.sh` | `new new new` | 非零 |

三個 replacement point 都注入過，全部符合「失敗後只能全 new」。

### 17.5 R2-03 — destructive LAB test

`tests/lab/f5_manual_cleanup_test.sh` 重寫。路徑只在開頭解析一次
（`INSTALL_DIR` / `DATA_DIR` / `SCRIPTS_DIR`），guard、顯示、刪除、執行
全部只用這組變數。七道 guard：

1. 必須明確 `--lab-only`
2. hostname 必須精確等於 `LAB_HOSTNAME`，**沒有任何旗標可以繞過**
3. `DATA_DIR` 與 `SCRIPTS_DIR` 必須存在
4. production marker（`final/rpztw.txt` 非空）只能用專屬旗標
   `--allow-production-marker` 放寬，不再共用 `--i-know`
5. 互動輸入完整 hostname，或非互動時 `RPZ_LAB_CONFIRM` 必須精確相符
6. iCall periodic handler 必須全部 inactive，且 `pgrep` 無執行中的 processor
7. 三支腳本必須是本測試預期的原版 v1.2 md5

刪除 pattern 改用 `find -maxdepth 1 -name 'dnsxdump_*.out'` 等精確樣式，
與文件宣告一致，不再有 `rm -f $D/raw/*.out` 這種比宣告更廣的操作。
所有情境改為有明確預期值的 assertion，任一不符整支退出非零。

**驗收**：無參數 exit 2；hostname 不符 exit 2；hostname 不符時
`--allow-production-marker` 也無法繞過；`final/` 非空未加專屬旗標 exit 2；
無 `RPZ_LAB_CONFIRM` exit 2；handler active exit 2。

### 17.6 R2-04 / R2-07 — installer fail-closed 與路徑邊界

`install.sh` 的步驟 1 重寫，所有檢查都在任何 `mkdir` / `cp` 之前完成。

**完整性（R2-04）**：`VERSION`、`SHA256SUMS`、`sha256sum` 三者缺一律拒絕。
`VERSION` 必須在 `SUPPORTED_VERSIONS`（目前 `1.2.1`）之內。所有可安裝檔案
（`*.sh`、`zonelist.txt`）都必須有 manifest entry，多出來的一律拒絕。
legacy 需要用具名高風險開關
`RPZ_ALLOW_UNVERIFIED_PACKAGE=yes-i-accept-an-unverified-package`，
預設關閉且輸出醒目警告。

**路徑（R2-07）**：`validate_abs_path()` 拒絕空值、`/`、相對路徑、結尾斜線、
連續斜線、`.` 與 `..` 路徑元素。另外拒絕兩個 target 相同或互相包含、
與部署包來源目錄相同或互相包含。正式模式只允許 `/config/snmp/` 底下；
`RPZ_INSTALL_TEST_MODE=1` 才允許 `/var/tmp` 或 `/shared/tmp` 底下。

**驗收**（LAB，`PASS=21 FAIL=0`）：

| 情境 | 結果 |
|---|---|
| 正常 package（測試模式） | 安裝成功，manifest 涵蓋檢查通過 |
| 缺 `SHA256SUMS` / `VERSION` / `sha256sum` | 三者都退出碼 1，且**未建立任何目錄** |
| 額外 `scripts/extra.sh` | 拒絕，未建立任何目錄 |
| 篡改既有檔案 | 拒絕，未建立任何目錄 |
| `INSTALL_DIR=/` | 拒絕 |
| 相對路徑 | 拒絕 |
| 含 `..` | 拒絕 |
| 兩個 target 相同 | 拒絕 |
| 兩個 target 互相包含 | 拒絕 |
| 非測試模式指向 `/var/tmp` | 拒絕 |
| legacy override | 可安裝且有醒目警告 |

### 17.7 R2-05 — REPS 驗證

`patches/rpz_patch_sigpipe_v3.sh` 的 `validate_reps()` 與
`tests/lab/f5_hotfix_test.sh` 使用同一政策：必須是 1~1000 的整數，
在建立 fixture 之前驗證。`0`、負數、`abc`、超大值全部拒絕並退出非零。

### 17.8 R2-06 — consistency gate

`package.sh` 新增 `PACKAGE_INPUTS` 單一清單（以
`# PACKAGE_INPUTS_BEGIN` / `# PACKAGE_INPUTS_END` 標記），複製步驟改為
迭代這份清單。`tests/check_source_consistency.sh` 解析**同一份清單**逐檔比對。

新增的檢查：必要工具存在（`md5sum`、`sha256sum`、`tar`、`find`、`sort`）、
package 只有一個 root entry、root 名稱含預期版本、12 個 inputs 全部比對、
package 沒有清單外的檔案、`VERSION` 精確值、內層 manifest、外層
`.tar.gz.sha256`、無作業系統中繼資料檔案、`patches/` 只有一個現行 patch。

**回歸偵測驗證**：改 `install.sh` 但不重建 package →
`[FAIL] package 的 install.sh 與 tracked source 不一致`；
改 `scripts/utils.sh` 但不重建 → 三項 FAIL（嵌入內容、MD5_NEW、package）。
還原後回到 `PASS=25 FAIL=0`。

### 17.9 順手修掉的一個真問題

R2-04 的「manifest 未涵蓋的檔案一律拒絕」這個新檢查，第一次跑就抓到
`package.sh` 在 macOS 上打包會帶進 `._*` AppleDouble 檔案。那些檔案會被解到
F5 上而且不在 manifest 內。

修正：`package.sh` 在產生 manifest 前先 `find … -name '._*' -o -name '.DS_Store'
-delete`，`tar` 時設 `COPYFILE_DISABLE=1`，打包後再回頭確認壓縮檔內沒有
中繼資料檔案，有就直接失敗。

### 17.10 用語修正（審核第 9 節）

`scripts/generate_datagroup.sh` 的發布階段加了註解，明確說明**這裡不是完整的
publish transaction**：第一階段確保「缺 artifact 時不會部分發布」，但發布階段
仍是逐一 `cp`/`touch`，若某次 `cp` 中途失敗，前面已寫入的 final 檔案不會回復。
完整的原子發布屬於 CR-10，尚未實作。

本文件先前寫的「已不存在任何部分發布路徑」是不精確的，正確說法是
**「resolve/preflight 階段發現 missing artifact 時不會部分發布」**。

另外記錄一個 T7 未覆蓋的情境：`final/rpzip.txt` 先前非空、新 artifact 變成空時，
`touch` 不會 truncate，舊內容會保留。目前來源的 rpzip 一直是空檔，所以不是本次
的 rollout blocker，但屬於 CR-10 / CR-13 的政策決定範圍。

### 17.11 現行交付物

| 檔案 | md5 |
|---|---|
| `scripts/utils.sh` | `b8294149dc978305e19bcd83fcb650e6` |
| `scripts/parse_rpz.sh` | `cefa71b6623632dd51c60a51cdf72196` |
| `scripts/generate_datagroup.sh` | `9599755a54db53652c070cd70ae92652` |
| `patches/rpz_patch_sigpipe_v3.sh` | `685afe4c3e817abeb6a1861510a120f9` |
| `install.sh` | `f9fd0e2f106caee52aa36f597a3d2361` |
| `package.sh` | `3d28445f3d0212663955c3ab70efad0d` |
| `tests/check_source_consistency.sh` | `5c6fdf26c7314de9fd3432bd97ca2d9c` |
| `tests/lab/f5_hotfix_test.sh` | `4124f45adfd1869d2a221ba9567fe519` |
| `tests/lab/f5_manual_cleanup_test.sh` | `2dc11a0a2e2e6b32fbb6a33195dce5a3` |

### 17.12 LAB 最終狀態

```
安裝的三支      b8294149 / cefa71b6 / 9599755a（與 tracked source 相同）
patch check     三支腳本都已是修正版 (v3)
F1 行為矩陣     PASS=17 FAIL=0
F2 selftest     PASS=16 FAIL=0，無殘留 temp
main.sh --force raw 201 檔（12261 B），退出碼 0，8 秒
DataGroup       revision 8 -> 9，rpztw 58610 筆、phishtw 819 筆
final/          三個檔案 mtime 一致
handler         interval 300 active，已 tmsh save sys config
```

LAB 期間所有測試 fixture 都在 `/var/tmp` 隔離目錄，已清除。

### 17.13 仍未處理

第二階段的 CR-06 ~ CR-15 與 DOC-06，對照表見 16.5 節。第二輪審核第 9 節列出的
兩項（publish transaction、rpzip nonempty→empty）也屬 CR-10 / CR-13。

**上線前置條件未滿足**：依第二輪審核第 13 節，需要第三輪審核通過，以及取得
四台正式機的 `tmsh show sys version` 與 `md5sum scripts/*.sh`。

---

## 18. 第三輪修訂版審核回應

2026-08-21 第三輪修訂版審核 `docs/reviews/CODE_REVIEW_PHASE1A_ROUND3_REV2_20260821.md`
（SHA-256 `1d7e9412d00cdabfa9d944825803deadfb0c3836e2689a98e012b13e648342c6`，已核對相符）
判定：

| 交付項目 | 判定 |
|---|---|
| 4096 / SIGPIPE 根因與核心修正 | **PASS** |
| v3 patch 對既有原版的 apply | **CONDITIONAL GO** |
| v3 selftest 與 300 檔 regression | **PASS** |
| patch cleanup | **CONDITIONAL GO** |
| 客戶既有機器 rollout | **CONDITIONAL GO**，單機 canary |
| v1.2.1 新安裝包 | **HOLD**，與既有機器 patch 分開 |
| destructive LAB test | 修正前禁止執行 |

審核明確把 installer、package symlink、macOS xattr、大型 tar listing 等旁支
議題與「客戶既有機器的 SIGPIPE 救援」分流，不再讓前者無限期阻擋後者。

### 18.1 四項 P0 的完成狀態

| P0 | 內容 | 狀態 |
|---|---|---|
| 4.1 | patch 外部 SHA-256 sidecar | 完成。`patches/rpz_patch_sigpipe_v3.sh.sha256`，內容只有 basename。F5 上 `sha256sum -c` 退出碼 0 |
| 4.2 | cleanup false-success | 完成，選擇直接小修。新增 `validate_data_subdirs()` 與 `CLEANUP_UNSAFE_LOG`，symlink 子目錄一律拒絕且不部分刪除 |
| 4.3 | 中止與恢復 SOP | 完成。10 步驟 SOP 在 `patches/README.md`，含退出碼判讀表與中止/回復對照表 |
| 4.4 | 改檔後重建 hash 與重跑 gate | 完成。所有 hash 在最後一次修改後才計算，詳見 `docs/reviews/REVIEW_HANDOFF_PHASE1A.md` 第 4、6 節 |

### 18.2 額外修掉的項目

| 編號 | 內容 | 狀態 |
|---|---|---|
| R3-07 | destructive LAB test 的 `OUTPUT_DIR` contract | 已修。統一使用 `OUTPUT_DIR`，每次子腳本呼叫都明確傳入，final assertion 改為明確不變量 |
| R3-05 | 工具的 early-close pipeline | 已修。`package.sh`、`tests/check_source_consistency.sh`、`tests/lab/f5_rate_probe.sh` 都移除。`f5_pipefail_probe.sh` 刻意保留（缺陷示範） |
| R3-08 | recovery 訊息誤報 mixed | 已修。訊息依 `detect_state` 判定 |
| 審核 6.1 | gate 本身不應用 `ls|head` 挑 package | 已修。改用與 production 同型的純 bash mtime 迴圈 |

自己額外發現：`check` 對 unknown 也回傳 0，SOP 的「unknown 立即停止」無法用
退出碼判斷。已改為 unknown 回傳 **2** 並列出每支檔案的實際狀態。

### 18.3 仍為 HOLD

| 項目 | 原因 |
|---|---|
| v1.2.1 新安裝包 | installer 路徑處理（R3-01）、manifest symlink（R3-02）、`INSTALL_GUIDE.txt` 過期（R3-06）未處理。**不阻擋既有機器套 patch** |
| `tests/lab/f5_manual_cleanup_test.sh` 完整執行 | contract 已修、guard 行為已驗證，但情境 A~D 尚未在 LAB 實跑（需先把三支腳本還原成原版） |
| `cleanup.sh` 第 230 行的 `tmsh list \| grep -qE` | 同型 early-close，但 tmsh 輸出僅數行，遠低於 4096。屬 CR-12 的 Phase 2 範圍 |

### 18.4 必須說清楚的界線（審核第 6.3 節）

**v3 永久排除的是 `ls`/`head` 引發的 4096/SIGPIPE 缺陷。**

**它不保證其他失敗不會造成暫存檔累積。** `main.sh` 的 `cleanup()` 仍只在五個
步驟全部成功後執行（12.2 的缺陷 B）。若未來因 SOA、dnsxdump、awk、tmsh 或
其他原因長期失敗，`raw/`、`parsed/` 仍會累積。這是獨立的 lifecycle 問題。

**不可以把「檔案又累積了」直接當成 4096 修正失效。** 判別方式：
看 `rpz_wrapper.log` 是否出現「載入 N 個 Zones」後直接
「`[ERROR] RPZ 解析失敗`」的模式。有那個模式才是 SIGPIPE 型失敗。

#### Phase 1B（另立變更窗口，不塞進本次 hotfix）

1. `final/` 最後成功時間的告警，超過數個 handler 週期就通知。
2. `/config` 使用率與 raw/parsed 檔案數的簡單監測。
3. housekeeping 限定 `raw/`、`parsed/`，與主處理成功與否解耦。
   **絕對不要把 `final/` 放進失敗路徑的通用 `find -delete`。**
4. SOA cache 在完整成功前就前進（12.4）、全流程 lock（12.7）、
   final atomic publish（12.6）。

### 18.5 rollout 前置條件

依審核第 13 節，除本節的 P0 之外還需要：

1. 取得四台正式機的 `tmsh show sys version` 與 `md5sum scripts/*.sh`，
   確認三支腳本是 patch 支援的原版 v1.2。
2. 單機 canary 先行，通過後才推下一台。**不要四台同時變更。**

第 9 節的上 patch 步驟已被 `patches/README.md` 的完整 SOP 取代，以該文件為準。

---

## 19. v4 精簡重構（2026-08-22）

### 19.1 動機與決定

使用者檢視 v3 後的判斷：為求謹慎而導入的外部審核迭代，讓 patch 越寫越複雜。
量化：v3 共 1596 行，工具邏輯 987 行，實際功能變更約 30 行，比例 33:1。
過度設計的成因見第 18 節後的檢討：每輪審核指出既有功能的缺陷，修正時
沒有退一步問功能本身的必要性。

使用者指示：**用最簡單但正確的方式重新構築**。先在 LAB 恢復原版腳本，
再做完整驗證。

### 19.2 v4 設計

單一自足檔案 `patches/rpz_patch_sigpipe_v4.sh`，836 行 = 內嵌三檔 608 行
+ 工具邏輯 228 行。子指令只有 `check` / `apply` / `rollback <備份目錄>`。

自 v3 移除的部分與理由：

| 移除 | v3 行數 | 理由 |
|---|---|---|
| cleanup 子指令 | 275 | 與 4096 修正無關。為 per-zone KEEP 解析 `zonelist.txt` 引入 path traversal 面，需五層防護。暫存檔清理由手動作業文件與 Phase 1B 承接 |
| do_selftest | 178 | LAB 與正式機同平台，`f5_hotfix_test.sh` 已實測同樣的事。SOP 的 `main.sh --force` 用真實資料驗證，比合成 fixture 有效 |
| recovery staging（R2-02） | 約 60 | 以**安裝順序**取代：utils.sh 是純新增函數，最先安裝；任何中斷點留下的組合都能運作（新 utils + 舊其他 = 相容）。rollback 反向。一行註解取代 60 行機制 |
| exit-code 精細分類、md5 表間接層等 | 其餘 | 合併為 0 / 1 / 2 三碼與直接的 `declare -A` 常數 |

保留的安全機制（全部在 228 行內）：

1. 三檔 md5 前置核對。任一非已知版本，整批拒絕（RC=2），不改任何檔案。
2. `pgrep` guard：RPZ 程序執行中拒絕操作，列出比對到的程序。
3. 套用前備份到 `/var/tmp/rpz_patch_backup_<時間>/`，附 `md5sums.txt`。
4. 同目錄 `mktemp` + `mv` 原子取代；抽出的內嵌檔先驗 md5 才放置。
5. `chmod/chown --reference` 沿用目標既有權限與擁有者。
6. 安裝後逐檔再驗證。
7. rollback 前先 `md5sum -c` 驗備份完整性；還原後印出狀態。
8. `check` 印出 md5 欄位，兼作四台正式機資料收集工具。
9. EXIT trap 清暫存檔（記取 v3 selftest 的 `local` 教訓，用全域變數 + `${TMPF:-}`）。

### 19.3 建置方式

`patches/build_patch_v4.sh` 從 tracked source 產生 patch，內嵌檔案不經手抄：

1. 六個 md5 斷言（HEAD 原版三個 + working tree 修正版三個），防 source 漂移。
2. heredoc delimiter（`__RPZ_EMBED__`）不得出現在內嵌檔案內。
3. 產出後 `bash -n`、round-trip 抽出三檔比對 md5、佔位符殘留檢查。
4. 產生 `.sha256` sidecar。
5. 建置 deterministic：重建產物 SHA-256 不變（已驗證）。

產物 SHA-256：`35a4cba8a8e72970020f769d4a355ed320e37d5241fa4dd486c213b39a28173b`

### 19.4 LAB 驗證（2026-08-22，10.8.34.223）

**恢復原版**：以 `/var/tmp/origsrc/scripts/`（七支全部 md5 核對通過）還原
三支腳本，並把 owner 從 501:wheel（先前 tarball 解壓殘留）修正為
root:webusers 755，與其他四支一致。

**原版失敗曲線重現**（真實 `parse_rpz.sh`，每組 10 次）：n≤67 全過，
n=80 起出現 exit 141（2/10），n=141 7/10，n=179 8/10，n=300 9/10。
與第 6 節的 30 次曲線一致，證實恢復有效。

**v4 測試矩陣**：T1 sha256 傳輸、T2 check 原版、T3 版本不明整批拒絕
（無備份、不動其他檔）、T5 main.sh 執行中拒絕（列出 main.sh 與
update_datagroup.sh 子程序）、T6 apply（備份、md5、權限保留、無殘留
暫存檔）、T7 check 已套用、T8 重複 apply 冪等、T9 部分套用只補缺檔、
T10 修正版全部 n 失敗率 0/10（含 300 檔 18300 B）、T11 e2e RC=0 且
「使用 dnsxdump 檔案」診斷行出現、T12 rollback 無參數列出備份、
T13 rollback 反向還原至原版、T14 再 apply、T15/T16 混合狀態功能實測
（中斷點 1：新 utils + 舊 parse + 舊 generate；中斷點 2：新 utils +
新 parse + 舊 generate；`main.sh --force` 皆 RC=0 且「處理完成」出現）。
**16 項全部 PASS。** T15/T16 直接證實 19.2 的安裝順序宣稱。

**測試環境備註**：T6 第一次執行時 guard 誤觸發，原因是我把 `md5sum
/config/.../scripts/*.sh` 驗證指令與 apply 放在同一個 ssh 呼叫，路徑
字串出現在 `bash -c` 的 cmdline 被 pgrep 命中。這是測試指令組法問題，
不是 patch 缺陷；工程師單獨執行 `bash .../rpz_patch_sigpipe_v4.sh apply`
不含這些字串。此行為已寫入 `patches/README.md` 操作注意第 2 點。

### 19.5 v3 處置與審核狀態

1. `patches/rpz_patch_sigpipe_v3.sh` 保留於 repo，作為三輪審核的對應紀錄。
2. v3 的 CONDITIONAL GO **不轉移**到 v4。v4 是新 artifact，是否送外部審核
   由使用者決定；若送審，建議範圍是 228 行工具邏輯（內嵌三檔 md5 與 v3
   相同，其功能已由三輪審核與 LAB 驗證覆蓋）。
3. LAB `/var/tmp` 已清除 v1/v2/v3 patch 檔、舊備份目錄、`newsrc/`、
   舊 tarball 與測試 log。保留：`origsrc/`、五支 probe/test 腳本、
   dnsxdump 樣本、v4 兩檔、最終 apply 的備份目錄。

### 19.6 LAB 最終狀態

三支腳本 = 修正版 md5（b8294149 / cefa71b6 / 9599755a）、owner root:webusers、
iCall handler active（300 秒）、`main.sh --force` e2e 兩次 RC=0、
`final/` 三檔正常更新、`/config` 4%。
備份目錄：`/var/tmp/rpz_patch_backup_20260822_223152`（純原版內容）。

---

## 20. v4 第一輪審核回應（2026-08-22）

審核文件：`docs/reviews/CODE_REVIEW_V4_STE100_20260822.md`
（SHA-256 `9cd9d60664e6fbd7ffa3bcd072641907109c3ad5058111fce58fb82905e993d8`，已核對）。
判定 **CONDITIONAL GO**：runtime 設計可接受，V4-01～V4-04 為上線前必要修正，
V4-05 同步修文檔。審核明確要求維持最小化設計，不恢復 v3 的 transaction、
recovery staging、cleanup、內嵌 selftest。本輪全部遵守。

### 20.1 findings 核實與修正

五項 findings 逐項獨立核實，全部成立。

| 編號 | 內容 | 核實 | 修正 |
|---|---|---|---|
| V4-01（High） | SOP 的 `main.sh --force` 可與 iCall 併發；被動驗證「300 秒上限」錯誤（SOA 未變時 iCall 不做更新） | `main.sh` 無 lock（CR-09 已知）；SOA 短路行為屬實 | README SOP 步驟 7 改為受控序列：停 handler → 等靜止 → 測試 → 驗收 → 恢復 handler → `save sys config` → 確認。被動驗證改為「等真實更新事件」，明確標注 300 秒不是上限 |
| V4-02（Medium） | 狀態模型缺 provider 依賴：舊 utils + 新 consumer 不可運作（缺 `find_newest_file`），check 卻回報正常；rollback 會接受混合備份並回報成功 | 讀碼核實：`state_of` 逐檔獨立；rollback 只驗 `md5sums.txt` 自身一致 | patch 新增 `dep_violation()`：check 遇不可運作組合回 RC=2；apply 警告並修復；rollback 加純原版 gate（任一檔非原版 md5 即 RC=2，發生在改檔之前）；還原後逐檔驗證 |
| V4-03（Medium） | builder 從 `git show HEAD:` 讀原版 md5，release commit 之後 HEAD 變新版，builder 失效 | 讀碼核實 | 原版 md5 改為審核核定常數，移除 git 依賴。驗收：乾淨 commit 的暫存 repo 重建，RC=0 且 SHA-256 與 release 值一致 |
| V4-04（Medium） | project gate 仍驗 v3；v3+v4 並存使 gate FAIL=1、RC=1 | 執行核實（審核者已跑出 PASS=24 FAIL=1） | gate 改驗 v4（單一 `__RPZ_EMBED__` delimiter 依序抽出、`ORIG[f]=`/`NEW[f]=` 表格式）；v3 與 sidecar 移到 `patches/archive/`；新增 5c 檢查 patch sidecar。重跑 **PASS=26 FAIL=0，RC=0** |
| V4-05（Low） | sidecar 只含 basename，從 repo 根目錄 `shasum -c patches/….sha256` 會 FAIL | 自己先前也踩到過 | README 步驟 1 與 handoff 改為 `cd patches` 後驗證，標注「patch 與 sidecar 必須在同一目錄」。sidecar 保持 basename 格式（設備端正確） |

### 20.2 重建與重驗

1. 重建：`patches/rpz_patch_sigpipe_v4.sh` **866 行**（內嵌 608 + 邏輯 258，
   V4-02 增加 30 行）。SHA-256
   `d058b2cfa57bd374632021af52e5fbf6c536d4351f7bbf8d14c42e7f2fa66578`。
   sidecar 由 builder 重新產生。
2. V4-03 驗收：暫存 repo 只放三支新版 source + builder，commit 後從乾淨
   checkout 重建，SHA-256 與 release 值**逐位一致**。
3. project gate：PASS=26 FAIL=0，RC=0，驗證對象是 v4。
4. 迴歸測試：新增 `tests/lab/f5_patch_v4_test.sh`（審核第 7 節要求的獨立
   測試檔）。fixture 全在 `/var/tmp`，production patch 以 sed 副本改指
   fixture 路徑，原檔不動。涵蓋 12 個審核案例加修復路徑案例，
   在 LAB 實機 **66 項斷言全 PASS**。含 chattr +i 故障注入（每個檔案的
   apply/rollback 失敗與續跑）、八種 o/n 組合、混合備份拒絕、
   純原版備份還原、暫存檔清理。
5. 真實目錄週期：新 patch `check`（已套用）→ `rollback`（純原版 gate 通過）
   → `apply`，全部 RC=0。
6. 受控 e2e（release condition 10-13）：handler inactive → `main.sh --force`
   RC=0、「使用 dnsxdump 檔案」出現、`final/` 三檔更新、DataGroup revision
   **15 → 16** → handler active → `tmsh save sys config` → 確認 active/300。

### 20.3 測試環境教訓（harness 自我比對，第二次發生）

受控 e2e 的「等靜止」步驟逾時 122 秒，原因與第 19.4 節 T6 相同：整段
指令塞進一個 `bash -c`，其中 `main.sh` 的路徑字串出現在自身 cmdline，
pgrep 比對到自己的父 shell。工程師互動式逐條輸入不會發生（shell cmdline
是 `-bash`）。README SOP 因此寫成逐條輸入的形式。當時 handler 已停用且
已等超過一輪執行時間，該次 e2e 的結果仍有效。

### 20.4 v3 處置更新

`patches/rpz_patch_sigpipe_v3.sh` 與 sidecar 移到 `patches/archive/`
（V4-04 要求現行 patch 唯一）。第 19.5 節「保留於 repo」的敘述仍成立，
路徑更新為 archive。

### 20.5 審核建議中未採納的部分

無。五項 findings 全部修正，release conditions 1-13 全部完成，
condition 14（更新 handoff）與本節同步完成。

---

## 21. v4 第二輪審核回應（2026-08-22）

審核文件：`docs/reviews/CODE_REVIEW_V4_ROUND2_STE100_20260822.md`
（SHA-256 `7577ca0446e53b5911610f574a6ad94c34989c44adf50c79e0b147c14cf9c8ae`，已核對）。
判定 **CONDITIONAL GO**。第一輪五項中 V4-02（新條件）、V4-03、V4-04、V4-05
關閉，V4-01 的 runtime 部分關閉。審核者獨立重跑 gate（PASS=26）、
迴歸測試（PASS=66）、deterministic rebuild、受控 e2e（revision 16 -> 17，
無 harness 自我比對問題），並確認 122 秒逾時是測試工具缺陷、非 patch 缺陷。

### 21.1 findings 核實與修正

| 編號 | 內容 | 核實 | 修正 |
|---|---|---|---|
| R2-V4-01（Medium） | SOP 沒有記錄測試前數值、`main.sh` 的 `$?`、DataGroup size 與完整 before/after 證據 | 讀 README 步驟 7 屬實：互動 shell 不顯示 `$?`，下一條指令會蓋掉 | SOP 步驟 7 改為：before 記錄（final/ mtime、revision、size、last-update-time）→ `main.sh --force` → 下一條立刻 `MAIN_RC=$?; echo` → after 記錄同組數值 → 五項驗收條件（含 size 同量級）。標注保留終端機完整輸出作為證據 |
| R2-V4-02（Medium） | rollback 驗備份卻不驗目前 target：版本不明的檔案會被無警告覆寫；缺檔會造成部分還原 | 讀碼屬實：`do_rollback` 只有備份 gate；`place_file` 不驗 target md5；審核者隔離實測 CHECK_RC=2 但 ROLLBACK_RC=0 | `do_rollback` 加目前檔案預檢（7 行 + 註解）：逐檔 `state_of`，非 orig/new 即 RC=2，發生在改任何檔案之前。依賴違規組合（各檔皆已知版本）可通過，由純原版還原修復 |
| R2-V4-03（Low） | builder 註解宣稱原版 md5「來源: 四台正式機擷取」，但四台擷取資料沒有腳本 md5 | 本地核實：`客戶診斷資料_20260820/` 內無此三個 md5 值；constants 實際等於 GitHub baseline commit `27415940`（= origin/main）的三檔 | 註解改為「審核核定的 GitHub baseline（commit 27415940…）」，明載這不是四台實測證據、每台 apply 前必須先 check |

### 21.2 重建與重驗（依審核第 8 節的範圍）

1. 重建：**876 行**（內嵌 608 + 邏輯 268，預檢 +10 行）。SHA-256
   `e407d6e7d0d12d1c6ca445d737208ab139437fd8504fe47d9b318754c1d37626`。
   sidecar 重新產生，`cd patches && shasum -a 256 -c` RC=0。
2. deterministic 複驗：乾淨 commit tree 重建，SHA-256 逐位一致。
3. project gate：PASS=26 FAIL=0，RC=0。
4. 迴歸測試新增案例 14（target 版本不明 + 純備份 → RC=2 且三檔全未動）、
   15（target 缺檔 → RC=2 且無部分還原）、16（依賴違規 onn + 純備份 →
   RC=0 修復為全原版）。LAB 實機 **PASS=78 FAIL=0，RC=0**。
5. 依審核第 8 節：payload 未變（三檔 md5 同前），不需重跑 4096 failure
   curve；rollback-only 變更不需重跑受控 e2e。真實目錄 `check` RC=0。
6. 未恢復 v3 的 transaction、recovery staging、cleanup、embedded selftest；
   未改 payload；未改 iRule。

### 21.3 canary 前置規則（審核第 9 節，抄錄為部署紀律）

1. 不得用第二輪審核當下的 SHA-256（`d058b2cf…`）上 canary；用關閉
   findings 後的新建置（`e407d6e7…`，若第三輪審核通過或使用者核准）。
2. 每台正式機 apply 前先跑 `check`，三檔必須全為原版 v1.2 md5。
   出現版本不明或依賴違規就停止。
3. 不假設四台都等於 GitHub baseline；四台各自跑 check。
4. 不同時部署四台。

---

## 22. Phase 1B 實作與 LAB 驗證（2026-08-23）

設計文件 `docs/PHASE1B_DESIGN_20260823.md`（決定 3 = B1、決定 4 = KEEP 24，
四個確認點使用者已核可）。

### 22.1 變更內容

1. `scripts/main.sh`（`0041c1d7…` -> `5a04c25f…`，256 -> 323 行）：
   - cleanup 的 find 縮小到 `raw/` 與 `parsed/`（`-maxdepth 1`）
   - 新增 `prune_by_count()` 與 `prune_parsed_families()`：純 bash、
     零管線；家族前綴由檔名推導，不讀 zonelist
   - `RPZ_KEEP_COUNT`（預設 24）+ 非法值回退
   - `trap on_exit EXIT`：先存 `$?`、清理、原碼退出；
     `run_cleanup_once` 防止成功路徑重複執行
   - cleanup 靜默化：無刪除時零輸出
   - 缺陷 A 死碼保留原樣，只加註解（Phase 2）
   - 補結尾 newline（與 v1.2 utils.sh 同型問題，builder heredoc 需要）
2. `patches/rpz_patch_phase1b_v1.sh`：561 行（內嵌 327 + 邏輯 234），
   SHA-256 `fd85d67df1dc3d73ff69f8eb08eb62cdcf645445105dffb706e9ef466c3b0608`。
   與 v4 同款安全機制；備份前綴 `rpz_patch1b_backup_`。
   builder deterministic（乾淨 commit tree 重建 SHA-256 一致）。
3. gate 第 9 節：驗 1B patch（嵌入一致、md5 表、sidecar、唯一性）。
   全 gate **PASS=31 FAIL=0**。
4. package VERSION 1.2.1 -> 1.2.2 並重建（CR-03 一致性；dist 維持 HOLD）。

### 22.2 LAB 驗證（歷史數字：66/5 是審核輪 1 前的結果，最新見第 24 節）

1. 迴歸 `tests/lab/f5_patch_1b_test.sh`：**PASS=66 FAIL=0**。
   M1-M10（機制含 chattr 注入、版本不明/缺檔/混合備份拒絕）、
   F1-F7（保留最新 24、天數上限、零輸出、外來檔、KEEP 參數、--no-cleanup）、
   T1-T2（失敗路徑 trap 清理、--no-cleanup 不清理）。
2. 受控 e2e `tests/lab/f5_e2e_1b_controlled.sh`：**PASS=5 FAIL=0**。
   四家族各「刪除 21 個，保留 24 個」、final/ 2,243,094 bytes、
   revision 20 -> 21、handler active/300、config saved。
3. 真實目錄 rollback -> 再 apply 全 RC=0；v4 三支不受影響。

### 22.3 測試事故：e2e 第一版把 LAB 的 final/ 覆寫為 0 bytes

**經過**：第一版 e2e 的 apply 撞上正在跑的 iCall，guard 正確拒絕（RC=2），
但腳本沒有 abort gate，繼續以**原版 main.sh** 執行後續步驟。播種的假檔
用了「舊檔名 + 新 mtime」，與真實 dnsxdump 同秒落地，被
`find_newest_file()`（mtime 比較）選中。0-byte 假 dump 進入 pipeline：
parse 產出 0-byte、generate 只 WARN 照樣發布，`final/` 三檔被覆寫為
0 bytes。`update_datagroup` 對 0 筆記錄跳過，**TMOS 內 DataGroup 未受
影響**（revision/size 不變），線上查詢正常。

**修復**：等靜止後跑一次真實 `main.sh --force`，final/ 重新產生
（rpztw 58,611 筆、2,243,094 bytes，revision 20），與 TMOS 一致。

**兩個 harness 錯誤**：(1) e2e 步驟間沒有 abort gate；(2) 假檔用新 mtime。
第二版修正：handler 先停、apply/check gate、假檔 mtime 3 天前、
trap 兼負責清假檔與恢復 handler。設計文件 6.4 節已補修訂註記。

**附帶發現（重要）**：這是 CR-10 的活體證據——generate_datagroup 對
0-byte 解析檔只 WARN 就發布到 final/。若當時 zone 有任何一筆记录變更
觸發 update，空名單就上線。**建議把 CR-10（final 發布的資料完整性門檻）
在 Phase 2 提到最高優先。** 本次事故若發生在正式機，後果是 final/ 空檔
+ DataGroup 跳過更新（服務仍用舊名單），與 LAB 相同可恢復，但這依賴
「0 筆 -> 跳過」的巧合行為，不是設計保證。

### 22.4 LAB 最終狀態

main.sh = 1B 修正版（`5a04c25f…`）、v4 三支 = 修正版、
handler active/300、config saved、final/ 正常（revision 21）。
備份：`rpz_patch1b_backup_20260823_004329`（純原版 main.sh）、
`rpz_patch_backup_20260822_232957`（v4 純原版三支）。

---

## 23. Phase 1B 第一輪審核回應（2026-08-23）

審核文件：`docs/reviews/CODE_REVIEW_PHASE1B_STE100_20260823.md`
（SHA-256 `7329d2c8f394f49d407aebf6f416037defe0c7f8fad901881f5e21abd2c98e3f`，已核對）。
判定分列：production patch **CONDITIONAL GO**、e2e 驅動器 **NO-GO**、
v1.2.2 安裝包 **NO-GO**、CR-10 升 **Phase 2 P0**。
審核者獨立重跑 66 斷言迴歸、gate、deterministic 重建、NO_UPDATE 測試皆通過。

### 23.1 findings 核實與修正

| 編號 | 核實 | 修正 |
|---|---|---|
| P1B-01（High）e2e 驅動器非 fail-closed | 屬實：無 hostname/--lab-only/確認 gate；revision/handler/save 只印不斷言 | 驅動器全面重寫：四道硬性防護（`--lab-only`、主機名 = `cdns.ryantseng.work`、`E2E_CONFIRM` 完整確認字串、handler 初始 active/300）、合成檔 manifest（只刪自己建的）、before/after 全數值斷言、EXIT trap 恢復 + save。五個拒絕案例實測全 RC=2 |
| P1B-02（Medium）KEEP 溢位 | 屬實：`^[1-9][0-9]*$` 接受 36 位數，bash 算術溢位 -> 全刪 + 陣列越界 RC=1（審核者實測） | 範圍限制 `^[1-9][0-9]{0,4}$`（1-99999），範圍外回退 24 並警告 |
| P1B-03（Medium）glob 前綴跨家族刪除 | 屬實：`*` 前綴檔名使 `*_*.txt` glob 掃全家族（審核者實測 alpha=0） | 前綴只接受 `A-Za-z0-9._-`；不安全前綴跳過數量上限並 WARN，天數上限仍管 |
| P1B-04（Medium）刪除失敗被隱藏 | 屬實：`rm -f \|\| true` 吞錯，log 謊稱刪 6 保留 24（實際 25） | 逐檔計數成功/失敗；失敗時 WARN 據實回報，不宣稱保留數；天數上限 find 失敗也 WARN。cleanup 仍不影響主流程退出碼 |
| P1B-05（Medium）installer 只收 1.2.1 | 屬實 | **不修**：安裝包維持 HOLD（審核 10.4 允許），記錄於 `dist/DO_NOT_DEPLOY.md`。不影響 patch-only rollout |
| P1B-06（Low）macOS xattr | 同上 HOLD | 同上 |
| P1B-07（Low）測試與記錄不全 | 屬實 | NO_UPDATE 永久測試（T3/T4，stub check_soa）；T1-T4 的 `LOG_FILE` 指向 fixture（不再寫真實 /var/log/ltm）；LAB README 補三支測試與破壞性等級；設計文件狀態與 403 MB 措辭改為容量估計；package.sh changelog 補 1.2.2 行 |

### 23.2 重建與重驗

1. 重建：585 行（內嵌 351 + 邏輯 234）。SHA-256
   `bd42e9b35e34f3fd5012aa139bf963e8273bf848e2f0642a68305d94ae433aa6`。
   deterministic 複驗一致；sidecar RC=0；gate PASS=31 FAIL=0。
2. 迴歸：**PASS=104 FAIL=0**（+38 斷言）。過程中發現一個測試期望過時
   （F6 斷言字串未跟上新警告文字），修正斷言後全過。
3. fail-closed e2e：拒絕案例 5 項全 RC=2（含在 macOS 本機驗「錯誤主機名」）；
   正式執行 **PASS=20 FAIL=0**（revision 21->22、四家族 24、manifest 全清、
   handler active/300、save 成功）。

### 23.3 兩個環境發現

1. **F5 非互動 shell 的 `hostname` 是 wrapper**：stdout 為空、印 TMOS
   提示。主機名 gate 改用 `uname -n`（`main.sh` 本來就用它）。
2. **harness 自我比對第三次發生**：restore 指令的 cmdline 含
   `…/scripts/main.sh` 字面路徑，被等待迴圈的 pgrep 比對到。以變數拆路徑
   （`$D/scripts/main.sh`）避開。教訓已一般化：凡與 pgrep 等待同時存在的
   ssh 指令，cmdline 不得含 `RPZ_Local_Processor/scripts/` 相鄰字面。

### 23.4 canary 前置（**已被第 24 節取代**：輪 2 發現 P1B-08，以輪 2 修正後建置與短確認輪為準）

P1B-01～04 已關閉，patch-only canary 解鎖。順序照審核：每台先 v4 check/apply
再 1B check/apply，受控真實資料測試（**不播種合成檔**），before/after 記錄，
恢復 handler + save，之後至少觀察一個排程 tick 確認數量有界且無 WARN。
安裝包（v1.2.2）維持 HOLD，與 patch rollout 無關。

### 23.5 LAB 最終狀態

main.sh = 1B 修正版（`0835f71b`）、v4 三支 = 修正版、handler active/300、
config saved、revision 22。備份：`rpz_patch1b_backup_20260823_015040`
（純原版 main.sh）、`rpz_patch_backup_20260822_232957`（v4 純原版三支）。

---

## 24. Phase 1B 第二輪審核回應（2026-08-23）

審核文件：`docs/reviews/CODE_REVIEW_PHASE1B_ROUND2_STE100_20260823.md`
（SHA-256 `f72f0298…`，已核對）。判定 CONDITIONAL GO：P1B-02/03/04 關閉、
P1B-01 降 Medium 部分關閉、P1B-07 維持、新增 **P1B-08**（Medium）。
審核者獨立重跑迴歸 104、gate 31、deterministic 重建、並確認 LAB 收尾正常。

### 24.1 findings 核實與修正

| 編號 | 核實 | 修正 |
|---|---|---|
| P1B-08 合法前綴重疊 | 屬實。`alpha_*.txt` glob 會選中 `alpha_beta` 家族。本輪先在 LAB 以舊建置重現：alpha=0、alpha_beta=24、log 謊稱「刪 36 保留 24」 | 家族選擇器改精確形狀：`prune_family()` 以前綴**字面**（引號展開）+ `TS_GLOB`（8 位日期 _ 6 位時間）選取成員；raw 選擇器同步收緊。log 標籤改為家族名 |
| P1B-01 殘餘 | 屬實：播種無逐檔 gate（touch 失敗會留下新 mtime 的 0-byte 檔——與第一次事故同型）、count ≤24 接受 0、manifest 清除不驗證、trap 不回報恢復失敗 | 13 項全數落實：`seed_one()`（拒絕覆蓋既存、建立/touch 驗證、先記 manifest）、120 檔存在 + mtime < now−2 天驗證、check RC/文字分開、家族數精確 =24、manifest 逐檔驗證且殘留不清空、trap 回報恢復/存檔失敗 |
| P1B-07 | 屬實 | handoff 數字全面更新；設計文件程式碼樣本同步為最終實作、§8 改確認記錄；README「硬上限」改「估計」；STATUS §11 改已完成；迴歸標頭 F1-F12/T1-T4；§22.2 標註歷史數字；§23.4 標註被本節取代 |

### 24.2 重建與重驗（審核第 10 節範圍）

1. 重建：**591 行**（內嵌 357 + 邏輯 234）。SHA-256
   `aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785`。
   deterministic 複驗一致；sidecar RC=0；gate PASS=31 FAIL=0；
   package 重打維持 HOLD。
2. F12（前綴重疊）驗收：**舊建置（`bd42e9b3…`）LAB 實測 FAIL
   （alpha=0），新建置 PASS（alpha=24、alpha_beta=24、最新保留、
   最舊刪除、final/ 不動）**——符合「must fail against reviewed SHA」。
3. 迴歸：**PASS=112 FAIL=0**。
4. e2e 拒絕案例 5 項全 RC=2，且逐案驗證狀態零變更（main.sh md5、
   revision、合成檔數）。
5. 注入案例（預置衝突合成檔路徑）：驅動器 RC=1 於播種第一檔即中止、
   trap 恢復 handler active/300 並存檔、revision 不變、無殘留。
6. 正式受控 e2e：**PASS=20 FAIL=0**。apply/check RC=0、120 合成檔
   驗證通過、main RC=0、四家族精確 =24、revision 22 -> 23、
   size 2,243,094、mtime 更新、manifest 全清、handler active/300、
   save 成功。

### 24.3 本輪環境備註

1. LAB SSH 曾短暫逾時一次，重試即恢復，無資料影響。
2. 又踩一次已記錄的 F5 locale 陷阱：inline 指令中 `$b` 後接全形括號
   使 bash 解析成 `b（` 變數名。規則不變：與 CJK/全形字元相鄰一律
   `${var}`。

### 24.4 canary 狀態

依審核輪 2 第 11 節：`bd42e9b3…` 不得上 canary。本輪修正後建置為
`aa97950e…`，需經**短確認輪**後才進單機 canary。canary 程序仍依
輪 1 第 12 節（每台先 check、先 v4 後 1B、正式機不播種合成檔、
觀察至少一個排程 tick）。

### 24.5 LAB 最終狀態

main.sh = `d1e1f688`（輪 2 修正後）、v4 三支 = 修正版、
handler active/300、revision 23、config saved。
備份：`rpz_patch1b_backup_20260823_071714`（純原版 main.sh，本輪注入
案例的 apply 所建）、`rpz_patch_backup_20260822_232957`（v4）。

---

## 25. Phase 1B 第三輪短確認回應（2026-08-23）

審核文件：`docs/reviews/CODE_REVIEW_PHASE1B_ROUND3_STE100_20260823.md`
（SHA-256 `09bd82b4…`，已核對）。判定：**production patch runtime GO**、
P1B-01 與 P1B-08 關閉、e2e 驅動器 GO（僅限指定 LAB）、
**canary 於文件修正後 GO**、v1.2.2 package 維持 HOLD、CR-10 維持 Phase 2 P0。
審核者獨立重驗：迴歸 112、F12 八項、gate 31、sidecar/內嵌/deterministic、
三個拒絕案例（md5/revision/handler 不變）、LAB 最終狀態。

### 25.1 P1B-07 殘餘（純文件，本輪關閉）

依審核 6.1~6.5 逐項修正：handoff 的 `prune_by_count` 名稱、F1-F7/T1-T2
敘述、舊 revision 值；設計文件狀態行（改三輪完成、指向 §22~25）、
兩處 403 MB 措辭、`prune_by_count` 名稱殘留、測試計畫更新為
F1-F12/T1-T4 與精確 =24；patches/README 的硬上限措辭、F1-F11、
revision 21->22、章節指向；STATUS 決定 4 的「待確認後實作」矛盾文字、
403 MB 措辭。`dist/DO_NOT_DEPLOY.md` 改為逐 tarball 記錄
（最新 `…_071238.tar.gz` SHA-256 `0db3e50f…`；本機未見 xattr 字串但
P1B-06 不因此關閉，需 F5 GNU tar 實測；P1B-05 的
`SUPPORTED_VERSIONS="1.2.1"` 仍成立）。

**production source、patch、測試檔一律未動**（審核明定不需重建、
不需重跑 destructive e2e）。hash 不變：patch `aa97950e…`、
main.sh `d1e1f688…`。

### 25.2 canary 狀態

Phase 1B 與 v4 都已獲審核 GO。canary 程序照輪 1 第 12 節 + 輪 2 補充：
每台先 check（三支 v4 檔與 main.sh 必須是原版 v1.2 md5，版本不明即停）、
先 v4 後 1B、受控真實資料測試、不播種合成檔、恢復 handler + save、
觀察至少一個排程 tick 確認家族數有界且無 cleanup WARN、
四台不同時上。

---

## 26. 真實來源 soak e2e（2026-08-23，使用者授權）

使用者授權以 API 對 LAB Infoblox（10.8.38.225）新增 rpztw 記錄，
模擬真實黑名單變更節奏，觀察 patched 腳本在**不停 handler** 的
真實排程下運作。方法：每 6 分鐘經 WAPI 新增一筆
`record:rpz:a`（`e2eNN.soak20260823.claude.test` -> `10.99.88.NN`，
唯一 IP 供精確斷言），共 10 筆；每筆輪詢 F5 的 final/、DataGroup
revision，並從測試 VS（10.8.38.199）dig 驗證回應值。

### 26.1 結果：10/10 全鏈路 PASS

| 圈 | pickup | revision | raw/parsed | dig |
|---|---|---|---|---|
| 1~5 | 280/233/187/96/47 秒 | 24→28 | 18→22 / 54→66 | 全部命中唯一 IP |
| 6~10 | 279/233/187/94/46 秒 | 29→33 | **24 封頂**（穩態） | 全部命中唯一 IP |

1. 每筆都在**一個 iCall 週期內**被拾取（46~280 秒，取決於新增
   時間與 tick 相位）。
2. 名單筆數逐筆 +1（58,611 -> 58,621），dig 回應值與寫入值
   逐筆一致——Infoblox -> zone transfer -> dnsxdump -> parse ->
   DataGroup -> iRule 全鏈路驗證。
3. **Phase 1B 穩態實測**：raw 於第 7 圈到達 24 後封頂，之後每輪
   刪最舊補最新（第 9 圈快照 25 是輪詢趕在該輪 cleanup 之前的
   量測時序，下一圈即回 24）。
4. 全程 wrapper log 新增 ERROR/WARN = **0**。

### 26.2 還原

WAPI 刪除全部 10 筆（10/10 OK，Infoblox 查詢為空）。下一個 tick
F5 自動跟上：final 無測試域名、筆數回到 58,611、revision 34、
raw=24/parsed=72、dig 已無回應。LAB 回到乾淨狀態。

這是兩個 patch 上 canary 前的最後一項驗證：真實來源、真實排程、
真實查詢面，含刪除方向的同步。

---

## 27. 補錄：cleanup 刪除範圍實測（測試 A~E）

本節內容是對話壓縮前（2026-08-22 之前）完成的實測，先前只記錄於
`STATUS_20260822.md` 第 9 節，未寫入本檔。payload 註解與部分文件
以「第 15 節」引用此內容，實際應指本節（見 `patches/README.md` 的
勘誤說明）。

背景：原版 `main.sh:84` 的 `find "$OUTPUT_DIR" -type f -mtime +7 -delete`
是遞迴掃描，範圍涵蓋 `final/`（DataGroup 的 source-path）。

| 測試 | 條件 | 結果 |
|---|---|---|
| A | 原版成功執行，`final/` 檔案 mtime 為 30 天前 | `final/` 保留 3 個（步驟 4 先寫入，mtime 變新才逃過刪除） |
| B | zone 已從 zonelist 移除（該 zone 的 final 檔不再被重寫） | `final/oldzone.txt` **被刪除** |
| D | **在原版加 `trap EXIT` 而不縮小 find 範圍，步驟 3 失敗** | **`final/` 由 3 個變 0 個** |
| E | find 範圍縮小到 `raw/` 與 `parsed/`（`-maxdepth 1`），同 D 條件 | `final/` 保留 3 個，`raw/` 舊檔仍正常清除 |

結論：

1. `final/` 檔案存活依賴「每次成功執行都重寫使 mtime 變新」，
   不是被排除在刪除範圍外。任何讓 mtime 停止更新的情境
   （zone 移除、更新長期停滯 + 失敗路徑清理）都會讓 `final/` 被刪。
2. **Phase 1B 的順序因此固定：先縮小 find 範圍，才能加 `trap EXIT`。**
   順序顛倒會在停滯設備上刪光 DataGroup 來源（測試 D）。
3. 測試 E 即 Phase 1B 實際採用的修法。

---

## 28. Phase 1C：系統事件 log 改走 syslog（2026-09-04）

### 28.1 需求與診斷

客戶 TAC 需求（09-03 經經銷商轉達，.eml 存於本地）：腳本事件 log
（含 `RPZ parsing failed`）在 Splunk（remote syslog）看不到。診斷：
三支腳本共 **17 處**以 `echo >> /var/log/ltm` 檔案直寫（main.sh 8、
extract_rpz.sh 4、update_datagroup.sh 5），繞過 syslog-ng，因此
remote 轉送不到。本次事件期間 Splunk 上完全看不到失敗——此需求
直接補上監控盲點。

LAB 實測（17.1.3.1）：`logger -t RPZLocal -p local0.notice|err|info`
三個等級都落入 `/var/log/ltm`，格式為 F5 原生
（`Sep 4 12:02:28 主機 notice RPZLocal[pid]: 訊息`）。remote 轉送段
LAB 無 Splunk 可驗，客戶已以 `logger -p local0.notice "TEST--2"` 自證。

### 28.2 變更內容

1. 17 處直寫改為 `logger -t RPZLocal -p local0.err|notice "訊息" || true`。
   訊息文字不變；移除自帶的時間戳與主機名（syslog 會加原生格式）。
   severity：失敗類 `err`（11 處）、事件類 `notice`（6 處）。
2. 移除三支腳本中失效的 `LOG_FILE` 變數（3 處）與只為直寫服務的
   `local timestamp` 宣告（4 處；update 內兩個函式各一）；main.sh 的
   usage 同步。
3. 一併修正 main.sh 兩處註解章節號勘誤（第 13 節 -> 第 2 節、
   第 15 節 -> 第 27 節；`patches/README.md` 勘誤節等的就是這次）。
4. `extract_rpz.sh` 補結尾 newline（v1.2 同型問題第三例，builder
   heredoc 需要）。

新 md5：main.sh `9d8538a6…`（350 行）、extract_rpz.sh `fea7c2e2…`
（85 行）、update_datagroup.sh `67227cb3…`（200 行）。

### 28.3 patch 與 payload 鏈

`patches/rpz_patch_phase1c_v1.sh`：890 行（內嵌 647 + 邏輯 243），
SHA-256 `9e0eca91b481ff20ab822deb5c741696581ce508a184de6b896d19a4168390bd`，
deterministic。**部署前版本 = 1B 版 main.sh（`d1e1f688`）+ v1.2 版
extract/update**——check 以此強制部署順序 v4 -> 1B -> 1C，未套 1B 的
設備會回報版本不明。工具邏輯與 v4/1B 同款（含純部署前版本 rollback
gate 與目前檔案預檢）。

gate 改為 **payload 鏈模型**：1B patch 的內嵌對「1B 凍結版」驗證，
鏈尾（1C 的三檔、v4 的三檔）對 tracked source。新增第 10 節驗 1C。
gate **PASS=42 FAIL=0**。package 升 1.2.3 重打（維持 HOLD）。

### 28.4 LAB 驗證（license 到期前完成）

1. 迴歸 `tests/lab/f5_patch_1c_test.sh`：**PASS=29 FAIL=0**。
   M1-M8 機制（check/apply/冪等/版本不明/rollback/混合備份拒絕/
   缺檔拒絕/chattr 注入與續跑）；F1-F3 功能（NO_UPDATE 的 notice
   事件、失敗路徑的兩個 err 事件、無重複前綴、零直寫殘留）——
   以 ltm 行數基準比對新增行。
2. 受控 e2e `tests/lab/f5_e2e_1c_controlled.sh`（同款四道身分防護，
   3 拒絕案例全 RC=2 + 本機錯誤主機名 RC=2）：**PASS=15 FAIL=0**。
   apply/check gate、真實資料 `--force`、ltm 出現 extract/update/
   completed 三類 notice 事件（原生格式、無重複前綴）、
   revision 34 -> 35、raw 保留策略仍有效、handler 恢復 active/300、
   save 成功。
3. rollback e2e：還原至部署前版本（1B main + v1.2 其餘）-> 再 apply，
   全 RC=0；v4 與 1C 兩條 check 鏈同時 RC=0。

### 28.5 狀態與後續

Phase 1C **待送 Codex 審核**（`docs/reviews/REVIEW_HANDOFF_PHASE1C.md`）。
審核通過後：更新客戶 SOP（部署順序 v4 -> 1B -> 1C）與回覆經銷商。
LAB license 經 09-05 查詢實際到期日為 2026/10/06（先前「隔日到期」為口頭資訊，以查詢為準）。


---

## 29. Phase 1C 第一輪審核回應（2026-09-05）

審核文件：`docs/reviews/CODE_REVIEW_PHASE1C_STE100_20260905.md`
（SHA-256 `e1f0d694…`）。判定：日誌修正本身 **GO**、canary CONDITIONAL GO、
e2e 驅動器修正前 NO-GO。審核者獨立重驗 gate 42、迴歸 29、
補充隔離檢查 46 項全過，並確認 payload 三檔 hash 與 LAB 安裝一致。

### 29.1 findings 核實與修正

| 編號 | 核實 | 修正 |
|---|---|---|
| P1C-01（Medium）SOP 未涵蓋跨 patch 版本關係 | 屬實：1C check 只驗自己三檔，不讀 v4；已裝 1C 後 1B check 回 RC=2（舊工具不認得新 main，屬保護）；舊還原順序寫法不適用已裝 1C 的設備 | `patches/README.md` 新增 4.6 節（Patch 3 部署：v4+1C 交叉確認、部署後 1B check RC=2 屬預期、Splunk 唯一識別碼驗證法）；第 5 節還原改寫（情境 A 只回復 1C；情境 B 全還原 1C -> 1B -> v4 不得跳過）；builder/patch 註解改為準確描述 check 範圍 |
| P1C-02（Medium）e2e 四種錯誤條件仍回報 PASS | 屬實（審核者以本機 mock 證實） | 驅動器四項修正：tmsh 查詢保存 RC、status/interval 改 awk 精確欄位比對（3000 不再過 300）、pgrep rc 語意（1=無程序、>=2=查詢失敗即中止）、成功且核對後 `trap - EXIT`（不再有未驗證的第二次 save）。以審核者的 mock 重跑五模式：normal RC=0；interval3000 與 read_error RC=2、pgrep_error RC=1 全部中止；trap_save_error 下 save 僅執行 1 次 |
| P1C-03（Low）文字與檔案不一致 | 屬實 | err 11/notice 6、timestamp ×4、builder 316 行、e2e 132 行（修正後值）、license 以 09-05 查詢的 2026/10/06 為準、1B builder 歷史重建需 checkout `f560b80`、patch 註解 Splunk 措辭改「本機已驗證，遠端待現場確認」、dist HOLD 補 v1.2.3 |

### 29.2 重驗與產出

1. patch 因註解修正重建：SHA-256
   `a0ca535f84f744cb50dfbdbe84e9dec7362d398968dd53bd33ee9d2de04610ec`
   （892 行；payload 三檔 md5 不變：`9d8538a6/fea7c2e2/67227cb3`）。
   deterministic、sidecar、gate PASS=42 全過。
2. 迴歸新增 F4（parsing 失敗事件）與 F5（logger 失敗不影響主流程）
   永久保護：LAB **PASS=33 FAIL=0**。
3. 依審核 6.6：未重跑 destructive e2e 與 soak；mock 反向測試已重跑。
4. `.gitignore` 新增 `*.eml`（客戶郵件不入 repo，審核 6.8）。

### 29.3 尚待現場（canary）

Splunk 收件驗證（README 4.6 節第 4 步，唯一識別碼比對）。
完成前不宣稱需求端對端結案。

---

## 30. Phase 1C 第二輪短確認回應（2026-09-05）

審核文件：`docs/reviews/CODE_REVIEW_PHASE1C_ROUND2_STE100_20260905.md`。
判定：production GO 維持；**P1C-02 關閉**（審核者以第一輪 mock 重驗
五模式：normal 通過、三種錯誤模式中止、trap_save_error 正常通過且
save 僅執行一次）；e2e driver GO（限指定 LAB）；P1C-01/03 殘項列明。

### 30.1 殘項修正（純文件，執行檔 hash 不變）

| 項目 | 修正 |
|---|---|
| P1C-01 傳檔 | README 第 3 節改 6 檔 scp + 三個 sidecar 驗證（三行 OK 才繼續） |
| P1C-01 排程 | 4.6 節加「停止排程 -> 等待靜止 -> 套用 -> 恢復並存檔（成敗都做）」；第 5 節還原前後同樣操作 |
| P1C-01 預期輸出 | 刪除 4.6 的矛盾句（前置確認時 Patch 3 應為「部署前版本」）；第 5 節改正「回到原版 v1.2」——情境 A 後 main 是 1B 修正版，只有情境 B 走完三步才全回 v1.2 |
| P1C-01 Splunk err | 4.6 改為同一 TESTID 分送 notice 與 err 各一筆、先知會監控人員、兩邊比對；記錄表加 Patch 3 備份路徑與 TESTID 欄位 |
| P1C-03 | handoff 與 builder 註解改「1C 只驗自己三檔；v4 由 SOP 確認」；mock 結果措辭改「三種錯誤中止、trap_save_error 正常通過（save 僅一次）」；行數 892/245、regression 205、LAB README 33；主手冊補 1B builder 需以 `f560b80` 歷史版本重建 |

驗證：patch 重建後 SHA-256 不變（builder 註解在產生模板之外）
`a0ca535f…`；e2e `43599109…`、regression `9dfb7290…` 未動；
gate PASS=42 FAIL=0。

### 30.2 canary 條件狀態

文件條件已依本輪清單完成；審核核對後只剩 README 第 5 節一句
（全還原後 Patch 3 check 顯示「版本不明」屬預期）需更正，已於
09-05 修正——**canary 文件條件解除**。
Splunk 現場收件條件保留至 canary（README 4.6 第 6 步，
同一 TESTID 的 notice + err 兩筆比對）。

---

## 31. patches/ 目錄重整（2026-09-08）

使用者要求：patches/ 下分三個資料夾整理三個 patch，各自有 README，
patches/ 根目錄放總表。

### 31.1 新結構

| 位置 | 內容 |
|---|---|
| `patches/README.md` | 總表：patch 清單、共同規則、傳檔、跨 patch 還原、記錄表、退出碼、常見狀況、背景 |
| `patches/patch1_sigpipe/` | Patch 1 本體 + sidecar + `build_patch_v4.sh` + `README.md` |
| `patches/patch2_retention/` | Patch 2 本體 + sidecar + `build_patch_phase1b.sh` + `README.md` |
| `patches/patch3_syslog/` | Patch 3 本體 + sidecar + `build_patch_phase1c.sh` + `README.md` |
| `patches/archive/` | 不變（v3 封存） |

原單一 README（441 行）拆成 4 份。總表保留共同規則與跨 patch 事項；
各 patch 的部署、驗證、還原步驟移入各自資料夾的 README。
內容沿用審核通過的措辭，操作步驟本身沒有變更。

### 31.2 隨路徑修改的檔案

| 檔案 | 變更 |
|---|---|
| `tests/check_source_consistency.sh` | PATCH/P1B/P1C 常數、語法檢查 glob 改 `patches/*/*.sh`、5b/9/10 的唯一性檢查 glob |
| 三個 `build_patch_*.sh` | REPO 解析改 `../..`、OUT 改新資料夾 |
| `.gitignore` | `!patches/*.sha256` 改 `!patches/**/*.sha256` |
| `STATUS_20260822.md` | 路徑與文件表 |
| `dist/DO_NOT_DEPLOY.md` | 升級指引改為三個 patch 的新路徑 |
| `docs/PHASE1B_DESIGN_20260823.md` | 交付物表的兩個路徑 |

三個 patch 本體與 sidecar 只搬移，內容不變，SHA-256 不變。
客戶 SOP 與 LAB 測試不受影響：SOP 只用檔名（basename），
測試只用 `/var/tmp/` 路徑。歷史紀錄（本文件既有章節、`docs/reviews/`）
內的舊路徑不回改。

### 31.3 驗證（全部實際執行）

| 項目 | 結果 |
|---|---|
| `bash -n`（gate 與三個 builder） | 通過 |
| project gate | PASS=42 FAIL=0 RC=0 |
| sidecar 驗證（三個新位置） | 三個 OK |
| 隔離重建 v4 / 1C，與交付檔比對 | SHA-256 完全一致（`e407d6e7…` / `a0ca535f…`） |
| 1B builder | 未重建。維持既有規則：須在 `f560b80` 的 checkout 重建 |
| gitignore | 三個新 sidecar 路徑未被排除 |
| 舊路徑殘留掃描 | 除歷史紀錄外無殘留 |
