# RPZ Local Processor Phase 1A 第三輪審核修訂版

**文件日期**：2026-08-21

**交付對象**：Claude Code

**審核範圍**：既有客戶 F5 BIG-IP 上的 v3 patch、4096 bytes / SIGPIPE 根因、暫存檔累積、部署與回復流程，以及與本次交付直接相關的潛在問題

**範圍排除**：不審核、不修改 iRule/TCL

**環境前提**：F5 BIG-IP 17.1.3.1、Bash 與設備既有 coreutils；不引入 Python、Perl 套件或其他 runtime

**取代關係**：本文件取代 CODE_REVIEW_PHASE1A_ROUND3_20260821.md 的整體判定、嚴重度與修正順序。舊文件的反向測試結果仍保留為技術證據。

---

## 1. 修訂後結論

### 1.1 本案真正的交付目標

本階段的成功標準不是把 shell 專案改造成通用安全框架，而是：

1. 確認客戶目前三支原版腳本符合 patch 支援的精確版本。
2. 在 handler 停止且沒有 processor 執行時，完整、可回復地套用 v3 patch。
3. 永久移除三處 ls -t 加 head -1 在 pipefail 下的 SIGPIPE 失敗路徑。
4. 在超過 4096 bytes、甚至 300 個歷史檔案時仍能正確選出最新檔案。
5. 恢復一次真實 RPZ 更新，確認 final 與 DataGroup 確實更新。
6. 清掉已累積的 raw/parsed 舊檔並恢復磁碟餘裕。
7. 留下 regression gate 與上線後監測，避免相同寫法或相同症狀無聲復發。

### 1.2 修訂後判定

| 交付項目 | 判定 | 說明 |
|---|---|---|
| 4096 / SIGPIPE 根因與核心修正 | **PASS** | 根因已由 LAB 證實；純 Bash helper 從機制上移除 early-close pipeline |
| v3 patch 對既有原版 v1.2 的 apply | **CONDITIONAL GO** | apply、備份、staging、MD5、bash -n、原子替換與失敗回復均已通過；完成第 4 節最小交付項後可上線 |
| v3 selftest 與 300 檔 regression | **PASS** | LAB selftest PASS=16 FAIL=0；fixed variant 在 raw/parsed 300 檔反覆測試為 0 失敗 |
| patch cleanup | **CONDITIONAL GO** | 正常實體目錄可用；若 raw/parsed 是 symlink，目前會拒絕候選卻回傳成功。若部署流程會使用 cleanup，先做第 4.2 節的小修正 |
| 客戶既有機器 rollout | **CONDITIONAL GO** | 採單機 canary、完整 checksum、強制執行與 handler 復原 SOP 後可進行 |
| v1.2.1 新安裝包 | **HOLD，與既有機器 patch 分開** | 舊 INSTALL_GUIDE 與 installer 路徑問題需在交付新安裝包前處理，但不阻擋既有機器套 patch |
| destructive LAB test | **禁止執行直到修正** | DATA_DIR 與 OUTPUT_DIR 不一致，可能 guard 測試目錄卻操作預設 /config；這是測試安全問題，不是 runtime patch blocker |

最重要的判定是：**核心 patch 不應再因 installer、惡意 package layout、3000-entry tar 或 macOS xattr 等旁支議題被無限期阻擋。** 這些問題仍記錄並依實際用途修正，但必須和客戶既有機器的救援 patch 分流。

---

## 2. 審核採用的現實前提

本案的實際 threat model 與操作模式如下：

- artifact 由內部工程人員產生並經受控管道交付。
- 由受信任的 F5 admin 在已知設備上執行。
- production 安裝與資料路徑是固定的：
  - /config/snmp/RPZ_Local_Processor
  - /config/snmp/rpz_datagroups
- patch 的目的不是接受任意使用者路徑、任意第三方壓縮檔或 hostile input。
- F5 上不宜增加新的語言 runtime 或相依套件。
- 最應防止的是傳輸損毀、版本套錯、執行中替換、部分套用、失敗後 handler 未恢復，以及成功訊息與實際狀態不一致。

因此，本輪採以下設計原則：

1. 使用 Bash 與設備已有的 md5sum、sha256sum、readlink、find、tmsh。
2. production 流程使用固定路徑，不為不需要的任意路徑建立大型抽象層。
3. 外部 SHA-256 解決 artifact 截斷或傳輸損毀，不要求 patch 在自身尾端建立複雜的自我驗證協定。
4. package 由受控 build 產生時，拒絕 symlink 加明確檔案清單已足夠；目前不需要設計通用 archive 安全引擎。
5. 保留失敗時 fail-closed、明確非零退出碼及可回復性，因為這些直接影響客戶操作。

---

## 3. 4096 問題與核心修正審核

### 3.1 根因已確認

原版有三處同型寫法：

    parse_rpz.sh:
      ls -t raw/dnsxdump_*.out | head -1

    generate_datagroup.sh:
      ls -t parsed/<zone>_*.txt | head -1
      ls -t parsed/rpzip_*.txt | head -1

在 pipefail 下，head 取得第一行便關閉 pipe；當 ls 輸出超過 libc 約 4096 bytes 的輸出緩衝，需要第二次 write 時，producer 可能收到 SIGPIPE 並以 141 結束。這是時序競態，不是每次必現，但檔案越多，失敗率越高。

LAB 證據：

| 檔案數 / ls 輸出 | 原版觀察 |
|---|---|
| 67 檔 / 4087 B | 0% 失敗 |
| 80 檔 / 4880 B | 開始出現失敗 |
| 141 檔 / 8601 B | 高失敗率 |
| 179 檔 / 10919 B | 約 87% 失敗 |
| 300 檔 / 18300 B | 100% 失敗 |

這也說明 /config 尚有 30% 空間不是觸發條件。真正的觸發條件是檔名 listing 長度與排程時序；磁碟使用率升高是 pipeline 停滯後 cleanup 跑不到的結果。

### 3.2 修法適合 F5 shell 環境

utils.sh 新增 find_newest_file，以 Bash 迴圈比較每個符合 glob 的 regular file mtime：

- 不建立 producer/early-close consumer pipeline。
- 不依賴新增套件或語言。
- 執行時間為線性 O(n)，目前數百個檔案的規模合理。
- 檔名由程式固定格式產生，不涉及任意換行或 hostile filename。
- 找不到任何 artifact 時回傳 1，三個 caller 都明確 die。

這不是繞過 4096 門檻，而是移除造成 SIGPIPE 的機制，所以檔案 listing 超過 4096 bytes 後不會再次出現同一缺陷。

### 3.3 三個 call site 均正確處理

- parse_rpz.sh：找不到 raw artifact 時 hard fail，不產出假的 parsed 成果。
- generate_datagroup.sh：每個 zone 找不到 parsed artifact 時 hard fail。
- generate_datagroup.sh：rpzip artifact 必須存在，但允許合法的 0-byte 內容。
- generate_datagroup.sh：先 resolve 全部來源，再進入 publish，避免因後段缺檔造成前段 zone 已更新的部分發布。

### 3.4 已有證據

- tracked source、patch embedded source 與 v1.2.1 package 中三支修正版曾比對一致。
- 全部 shell 曾通過 bash -n。
- tests/check_source_consistency.sh 曾為 PASS=25 FAIL=0。
- v3 LAB selftest REPS=3：PASS=16 FAIL=0。
- f5_hotfix_test 的 fixed variant 在 raw 與 parsed 各 300 檔的重複測試為 0 失敗。
- apply 重複執行會偵測已是 new，不再次改檔。
- apply 只接受三支皆為精確原版 MD5；unknown 或 mixed state 會拒絕。
- embedded source 先完成 staging、MD5 與 bash -n，才開始替換 production script。
- replacement 使用同目錄 temp 加 mv；任一檔失敗會嘗試恢復，並輸出每檔實際狀態。

以上足以支持核心 patch 的 CONDITIONAL GO。

---

## 4. 客戶上 patch 前的最小必要工作

### 4.1 P0：建立 patch 外部 SHA-256 與唯一 artifact 身分

目前 syntactically-valid 的截斷 shell 可能在 main 呼叫之前結束，造成 exit 0 且什麼都沒做。這不是要在 shell 內加入複雜自校驗；正確且最簡單的控制是外部 checksum。

Claude Code 必須：

1. 最終修改全部完成後，重新計算 patch SHA-256。
2. 產生同名 .sha256 sidecar，內容使用 basename，不寫本機絕對路徑。
3. process.md 與正式 SOP 明定上傳前、上傳後都驗證 SHA-256。
4. checksum 不一致時不得執行 check、apply 或 cleanup。
5. 不得沿用舊值。第三輪檢查時的值 6b019bc9454d3ac0ecf97582302b5c70556b0976fd33621c5563bdd06092e8fb 只代表當時檔案。

這項是 production rollout 的必要條件，實作成本低且直接對應傳輸損毀風險。

### 4.2 P0：若 rollout 會使用 patch cleanup，修正 false-success

實測 DATA_DIR 本身是 symlink 時可正常 canonicalize；matched file 是 symlink 時也只刪 link，不會改外部 target。問題集中在 raw 或 parsed 子目錄本身是 symlink：

- safe_victim 會拒絕候選，沒有越界刪除。
- 但拒絕只印 FAIL，沒有傳回 caller。
- dry-run 與 real cleanup 最後仍可能 exit 0 並印 cleanup 完成。

建議最小修法：

1. cleanup 開始列舉前，要求 raw、parsed、final 都是 DATA_DIR 下的實體目錄且不是 symlink。
2. 任一 unsafe victim 或列舉錯誤，整體回傳非零。
3. planning 有錯就不要開始 deletion。
4. 不需要支援任意 symlink topology；對本案固定 production layout，明確拒絕即可。

若 Claude Code 決定不在本次修改 cleanup，則 SOP 必須在呼叫 cleanup 前明確驗證三個子目錄不是 symlink，且將此限制寫入交付說明。因本案需要清除已累積檔案，優先建議做上述小修正。

### 4.3 P0：部署 SOP 必須有明確中止與恢復條件

正式流程不可只寫一串 happy-path 命令。至少要包含：

- 明確使用 production INSTALL_DIR、DATA_DIR 與 BACKUP_ROOT，不繼承未知環境變數。
- check 必須顯示三支皆為 orig；unknown/mixed 立即停止。
- 停 handler 後，以 pgrep 確認沒有 processor 正在執行。
- apply 或 selftest 非零立即停止，不執行 force run。
- apply 後核對三支 new MD5。
- 執行一次 main.sh --force，保存完整 log 與退出碼。
- 確認 final 三檔存在；rpztw、phishtw 必須合理且非空，rpzip 依現況可為空。
- 確認 DataGroup revision、size 或實際查詢結果已更新，不能只看 shell exit 0。
- 不論後續成功或中止，都要把 handler 恢復 active 並 tmsh save sys config。
- main.sh --force 內部會 save config；若當時 handler 是 inactive，最後恢復 active 後必須再 save 一次。
- 記錄 patch backup 目錄；觀察完成前不要清除，也不要把 reboot 當成 rollback 方法。

### 4.4 P0：任何改檔後重建 hash 與重跑最小 gate

只要 Claude Code 修改 patch、embedded source、tracked source 或測試，就必須在最後一次修改後重新執行：

1. 所有 shell 的 bash -n。
2. git diff --check。
3. tests/check_source_consistency.sh。
4. v3 selftest，REPS 至少 10。
5. f5_hotfix_test fixed，REPS 至少 20，raw/parsed 300 檔都必須 0 失敗。
6. 原版 fixture的 check → apply → selftest → 重複 apply → rollback → apply。
7. 重新計算 tracked、embedded、patch 與 artifact 的 MD5/SHA-256。

Handoff 內 tests/check_source_consistency.sh 的 MD5 曾記成 5c6fdf26c7314de9fd3432bd97ca2d9c，但第三輪實檔是 726c73c27c25c319c312a05c4d17fd36。這證明 hash 必須在所有修改結束後才產生，不能手動沿用舊表格。

---

## 5. 建議 rollout 次序

以下是 Claude Code 應整理成正式 runbook 的流程骨架；實際 artifact SHA 與主機資訊要用最終值，不可複製舊值。

### 5.1 上傳前

1. 在交付端驗證 patch 與 .sha256。
2. 記錄目標主機、目前 handler 狀態、三支 script MD5、/config 使用率、raw/parsed 檔數、final mtime/size、DataGroup revision/size。
3. 先選一台 LAB 或影響最低的 customer node 作 canary。

### 5.2 主機端 preflight

    cd /var/tmp
    sha256sum -c rpz_patch_sigpipe_v3.sh.sha256

    INSTALL_DIR=/config/snmp/RPZ_Local_Processor \
    DATA_DIR=/config/snmp/rpz_datagroups \
    BACKUP_ROOT=/var/tmp \
    bash ./rpz_patch_sigpipe_v3.sh check

必要判讀：

- checksum 必須 OK。
- patch check 必須辨識為三支皆 orig，或若已是 new，清楚判定不需再次 apply。
- 任何 unknown/mixed、檔案遺失、非預期 MD5 都停止並人工處理。

### 5.3 quiesce、apply 與 selftest

    tmsh modify sys icall handler periodic rpz_processor_handler status inactive
    pgrep -fa 'rpz_wrapper|RPZ_Local_Processor/scripts/main.sh'

pgrep 不得看到正在執行的 processor。之後每個命令都明確傳入相同路徑，不依賴登入環境殘留值：

    INSTALL_DIR=/config/snmp/RPZ_Local_Processor \
    DATA_DIR=/config/snmp/rpz_datagroups \
    BACKUP_ROOT=/var/tmp \
    bash ./rpz_patch_sigpipe_v3.sh apply

    INSTALL_DIR=/config/snmp/RPZ_Local_Processor \
    DATA_DIR=/config/snmp/rpz_datagroups \
    BACKUP_ROOT=/var/tmp \
    REPS=10 \
    bash ./rpz_patch_sigpipe_v3.sh selftest

任一步非零都停止；保留 log、備份路徑與每檔狀態。若 apply 已完成但後續驗收失敗，由變更負責人依實際狀態決定 rollback，不得盲目重複 cp。

### 5.4 清除累積檔案

在第 4.2 節修正完成，或已人工確認 raw/parsed/final 是正常實體目錄後：

    INSTALL_DIR=/config/snmp/RPZ_Local_Processor \
    DATA_DIR=/config/snmp/rpz_datagroups \
    BACKUP_ROOT=/var/tmp \
    KEEP=60 \
    bash ./rpz_patch_sigpipe_v3.sh cleanup-dry

    INSTALL_DIR=/config/snmp/RPZ_Local_Processor \
    DATA_DIR=/config/snmp/rpz_datagroups \
    BACKUP_ROOT=/var/tmp \
    KEEP=60 \
    bash ./rpz_patch_sigpipe_v3.sh cleanup

必須檢查：

- dry-run 列出的只有 raw/dnsxdump 與 zonelist 對應的 parsed artifacts。
- final 不在刪除範圍。
- real cleanup 的 planned、deleted、errors 一致。
- 任一 FAIL 或非零就停止，不把 cleanup 完成訊息當唯一證據。

若現場決定不先 cleanup，patch 本身仍可修正 SIGPIPE；但要確認剩餘空間足夠完成一次 dnsxdump、parse 與 final publish。

### 5.5 真實功能驗證與恢復 handler

    bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force

驗證 full run 的 exit code、完整 log、final mtime/size 與 DataGroup 狀態。成功後：

    tmsh modify sys icall handler periodic rpz_processor_handler status active
    tmsh save sys config

接著至少觀察兩個 300 秒週期，確認：

- handler 仍為 active、interval 300。
- 沒有 exit 141 或步驟 3/4 無聲中止。
- final 與 DataGroup 在有 SOA 變更時正常前進。
- /config 使用率沒有繼續異常上升。
- raw/parsed retention 符合預期。

canary 通過後才推下一台；不要四台同時變更。

---

## 6. 如何確保同一問題不再發生

### 6.1 必須保留的 code regression gate

tests/check_source_consistency.sh 應持續檢查 production scripts 不得重新出現以下結構：

    ls -t ... | head -1

但 gate 本身不應再用 ls 加 head 選 package，避免測試工具重現同型風險。可用完整讀到 EOF 的排序方式，或直接由明確 artifact 名稱/單一清單取得目標。

### 6.2 必須保留的行為測試

- raw 300 檔，listing 明顯超過 4096 bytes，fixed variant 重複至少 20 次零失敗。
- parsed 每 zone 300 檔，fixed variant 重複至少 20 次零失敗。
- 最新檔必須依 mtime 選中。
- raw 空、任一 zone parsed 缺失、rpzip artifact 缺失都必須非零。
- rpzip artifact 存在但 0-byte 必須維持合法。
- missing artifact 時 final 不得部分發布。

300 檔已遠高於客戶觸發門檻，足以驗證本次機制。3000-entry tar 的 rc141 是 release tooling 的另一個測試，不應拿來阻擋 runtime patch。

### 6.3 需要區分兩種復發

v3 patch 能永久排除本次 ls/head SIGPIPE。它不能保證所有其他錯誤都不存在，也不能保證任何失敗時都會清理暫存檔。

目前 main.sh 的 cleanup 只在五個步驟全部成功後執行。若未來因 SOA、dnsxdump、awk、tmsh 或其他原因長期失敗，raw/parsed 仍可能累積。這不代表 4096 patch 失效，而是獨立的 lifecycle 問題。

建議列入 Phase 1B，而不是擴張本次 hotfix：

1. 對 final 最後成功時間設告警，建議超過數個 handler 週期就通知。
2. 對 /config 使用率與 raw/parsed 檔案數設簡單監測。
3. 將 housekeeping 限定於 raw/parsed，與主處理成功與否解耦；絕對不要把 final 放入失敗路徑的通用 find -delete。
4. 修正 SOA cache 在完整成功前就前進、全流程 lock 與 final atomic publish 等既有可靠性債務。

這些可用 Bash/tmsh 完成，不需要安裝新 runtime；但應另立測試與變更窗口，不要塞進急救 patch 後未充分驗證就上線。

---

## 7. 第三輪 findings 重新分級

| 原編號 | 修訂分級 | 是否阻擋既有機器 patch | 實際處置 |
|---|---|---|---|
| R3-01 installer symlink path | P2 / 新安裝包 | 否 | production 可只接受固定路徑；測試覆寫用 readlink -m 後比對即可，不需通用 path framework |
| R3-02 manifest 忽略 symlink | P2 / 新安裝包 | 否 | 受控 build 下以明確 PACKAGE_INPUTS、拒絕 symlink、outer SHA 已足夠；不需先實作 hardlink/special-file 通用分析器 |
| R3-03 cleanup false-success | P0，若本次會清檔 | 是，但只阻擋 cleanup，不阻擋 apply | 做簡單 subdir 非 symlink preflight，並傳遞錯誤狀態 |
| R3-04 合法截斷 patch silent success | P0 / artifact SOP | 是 | 產生並強制驗證外部 SHA-256 sidecar；不需複雜 trailer protocol |
| R3-05 package early-close/xattr | P2 / release tooling | 否 | 移除 tooling 的早關 pipe；xattr warning 屬封裝品質，不是 runtime 功能 blocker |
| R3-06 INSTALL_GUIDE 過期 | P1 / 新安裝包 | 否 | 新包交付前更新 v1.2.1 名稱、checksum 與正確 handler；patch SOP 另寫清楚 |
| R3-07 destructive test path mismatch | P1 / 測試安全 | 否，但修好前禁止執行該測試 | 統一使用 OUTPUT_DIR，所有 child invocation 明確傳同一路徑，修正 final assertion |
| R3-08 recovery 訊息誤報 mixed | P3 | 否 | 依最終 detect_state 決定訊息；可後修 |

### 7.1 installer 與 package 的實際邊界

若本次同時要交付全新 v1.2.1 安裝包，則以下是新包的 release blocker：

1. INSTALL_GUIDE 仍寫 v1.2，artifact pattern 不匹配 v1.2.1。
2. handler 名稱仍有 rpz_update_handler 舊名。
3. guide 缺 outer SHA-256 與 inner SHA256SUMS 的正確次序。
4. installer 的路徑判斷若保留環境覆寫，應先 canonicalize；更簡單的作法是 production 僅允許兩個固定預設路徑，只有 test mode 才允許覆寫。
5. package staging 直接拒絕 symlink，copy 僅使用 PACKAGE_INPUTS，不用 scripts/*.sh 擴大集合。

這些修正仍是 Bash 範圍且不複雜，但應用於新安裝包，不應和既有客戶 patch 混成同一個 GO/NO-GO。

---

## 8. destructive LAB test 的處置

tests/lab/f5_manual_cleanup_test.sh 目前用 DATA_DIR 作 guard、fixture 與刪除目標，但被呼叫的 main.sh、parse_rpz.sh、generate_datagroup.sh 只認 OUTPUT_DIR。若 reviewer 設 DATA_DIR=/var/tmp/safe，child 仍可能操作預設 /config/snmp/rpz_datagroups。

因此：

- 修正前不要在 LAB 或 production 執行此檔。
- 它不是證明 v3 runtime patch 不安全，而是測試 harness 自身不安全。
- 最小修法是只保留 OUTPUT_DIR 一個資料路徑變數，guard、顯示、fixture、刪除及所有 child call 都使用同一值。
- 對預設 /config 放 sentinel，使用 /var/tmp fixture 跑完整測試後，預設路徑的 checksum/mtime 必須不變。
- 文件不得再說測試不碰 final；main --force 與 generate 本來就會更新 effective OUTPUT_DIR 下的 final。
- final checksum 的兩個分支不可都呼叫 PASS。

修完才能把這支測試重新加入 LAB 流程。production rollout 不需要執行它；應使用 patch 自帶的隔離 selftest 加一次受控 full run。

---

## 9. 不應在本次 hotfix 過度設計的項目

Claude Code 本輪不需要為了通過審核而加入下列設計：

- Python、Perl module、容器或額外 package manager。
- 任意使用者路徑與任意 symlink graph 的通用 sandbox。
- 完整 hostile tar parser、hardlink graph 或所有 special inode 的框架。
- 為 patch 自身設計複雜的內嵌簽章/trailer；外部 SHA-256 足夠處理 accidental corruption。
- 把 RFC 2181 所有可能 octet 都納入 zone filename；本案應依 F5 支援的 RPZ 命名 contract。
- 為了目前 17-entry package 把 3000-entry tar 壓測當成 production patch blocker。
- 把 CR-06 到 CR-15 全部塞進同一支緊急 patch。

仍要保留的工程底線是：精確版本、外部完整性、固定 production path、非零錯誤、失敗可回復、真實功能驗證與 handler 恢復。這些不是過度設計，而是本次變更的必要保護。

---

## 10. Claude Code 的執行清單

### 10.1 本次 patch release 必須完成

- [ ] 保持 find_newest_file 與三個 call site 的核心行為，不因旁支重構造成回歸。
- [ ] 修正 cleanup 子目錄 symlink 的 false-success，或在正式 SOP 加等價的硬性 preflight；建議直接小修。
- [ ] 產生最終 patch .sha256 sidecar。
- [ ] 在 process.md / patches/README.md 寫清楚 checksum、quiesce、apply、selftest、cleanup、full run、handler restore、save 與 rollback 判讀。
- [ ] 明列 production 不使用 INSTALL_DIR/DATA_DIR 的任意覆寫；命令應傳入固定值。
- [ ] 修正後重跑第 4.4 節 gate，所有結果與退出碼寫入新 handoff。
- [ ] 更新所有受影響 MD5/SHA-256，移除舊 handoff 的錯誤 hash。
- [ ] 提供 canary 前後狀態表：handler、三支 MD5、/config、raw/parsed、final、DataGroup。

### 10.2 不阻擋 patch，但要另外處理

- [ ] 修正 f5_manual_cleanup_test.sh 的 OUTPUT_DIR contract；修好前標示 DO NOT RUN。
- [ ] 若要交付 v1.2.1 新安裝包，修 installer、manifest copy 與 INSTALL_GUIDE 後重建 package。
- [ ] 清理 package.sh 與 consistency gate 的 early-close pipeline。
- [ ] macOS PAX xattr 能移除最好；若僅有 GNU tar warning 且內容/hash 正確，可列 release quality issue，不阻擋既有 patch。
- [ ] recovery 最終訊息依 detect_state 修正，避免全 new 卻聲稱 mixed。

### 10.3 新 handoff 必須回答

1. 最終 patch SHA-256 是多少，F5 上 sha256sum -c 的實際退出碼為何。
2. check 對 orig、new、unknown 三種狀態各自的退出碼為何。
3. apply 後三支實際 MD5 是否精確等於 embedded expected MD5。
4. REPS=10 selftest 的 PASS/FAIL 與退出碼。
5. fixed variant 300 檔、REPS 至少 20 的 raw/parsed 失敗數。
6. cleanup 遇 subdir symlink 是否非零，且沒有部分刪除。
7. 真實 main --force 是否成功；final 與 DataGroup 前後狀態為何。
8. handler 是否恢復 active、interval 300，並已 save config。
9. LAB 是否清除 fixture，production scripts 與資料是否處於預期最終狀態。

---

## 11. Reviewer 最終意見

本次根因、修法與 LAB 證據已足以支持 v3 patch。修訂後不再用新安裝包的通用路徑防禦、symlink package 變異、macOS xattr 或大型 tar listing 阻擋客戶既有機器的 SIGPIPE 修復。

正式判定為：

> **v3 核心修正 PASS；既有客戶機器 rollout 為 CONDITIONAL GO。完成外部 SHA-256、cleanup false-success 的最小處置、最終 regression gate 與可中止/可恢復的 SOP 後，可先在單台 canary 上部署。**

同時要清楚告知客戶與維運：v3 永久排除的是 ls/head 引發的 4096/SIGPIPE 缺陷。若要確保任何其他失敗都不再造成暫存檔長期累積，仍需後續處理 cleanup lifecycle 與監測；這是下一階段可靠性改善，不應假裝已由本 hotfix 全部解決。
