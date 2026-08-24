# RPZ Local Processor 獨立審核報告與修正要求

**文件日期**：2026-08-21  
**審核角色**：獨立 Reviewer  
**處理對象**：Claude Code  
**目前判定**：`NO-GO` — 現有 `rpz_patch_sigpipe_v1.sh` 不可原樣推送正式機  
**審核範圍**：Shell pipeline、patch、安裝/移除、iCall、自動化測試、文件及資料生命週期  
**明確排除**：本文件不審核、不要求修改任何 iRule/TCL 程式碼

---

## 1. 給 Claude Code 的任務摘要

SIGPIPE 根因與 `find_newest_file()` 的核心修正方向已通過獨立驗證，但現有 patch 還有兩個由 patch 本身造成或暴露的錯誤，且正式原始碼與部署包仍維持舊版。

Claude Code 應依本文件執行下列工作：

1. 先完成「第一階段：SIGPIPE hotfix 必修項目」。
2. 為所有修正補上可自動判定成功/失敗的測試。
3. 將 hotfix 同步到 Git tracked source，避免日後重新打包時回歸。
4. 第二階段問題需分開處理，不要在未評估風險下全部塞進同一份緊急 patch。
5. 更新 `process.md` 與相關操作文件，修正已被獨立驗證推翻或證據強度不足的敘述。
6. 不得修改 iRule/TCL。
7. 不得自行 commit、push 或操作正式機。

---

## 2. Executive Summary

### 2.1 已確認正確的部分

以下結論已由程式碼、production PuTTY log、受控測試及 LAB BIG-IP 17.1.3.1 交叉確認：

- 三處 `ls -t <glob> | head -1` 在 `set -euo pipefail` 下確實可能讓 `ls` 收到 SIGPIPE，退出碼為 141。
- 問題位置正確：
  - `scripts/parse_rpz.sh:227`
  - `scripts/generate_datagroup.sh:65`
  - `scripts/generate_datagroup.sh:82`
- 問題與 `/config` 是否已滿無直接關係；檔案數及 `ls` 輸出 byte 數才是觸發條件。
- `find_newest_file()` 以 Bash 迴圈及 `-nt` 比較 mtime，可以消除這三處管線的 SIGPIPE。
- 現有 RPZ A record parser 對專案內 `dnsxdump_all.txt` 的輸出集合正確：
  - `rpztw`：58,599 個唯一 key/value，逐筆與來源正規化結果相同。
  - `phishtw`：819 個唯一 key/value，逐筆相同。
- `scripts/update_datagroup.sh` 的 DataGroup 失敗目前會因 `set -e` 傳出非零退出碼。不要誤判成其尾端 `exit 0` 一定會掩蓋失敗；故障注入時實際退出碼為 2。

### 2.2 現有 patch 不可上線的主因

1. 修正版在找不到 parsed 檔案時，行為由「失敗」變成「成功並 touch final」。
2. patch 的 `selftest` 即使所有測試都失敗，仍然 exit 0。
3. tracked source 未修正；重新 package/install 會重新導入缺陷。
4. rollback 的順序與寫入方式在 iCall 執行期間不安全。

### 2.3 即使 SIGPIPE 修好，仍可能造成靜默停滯的既有缺陷

- SOA 取得錯誤會被分類成 `NO_UPDATE`。
- SOA cache 在完整 pipeline 成功前就寫入，失敗後不會重試。
- SOA serial 只接受遞增，來源 serial 回退後可能長期停擺。
- 沒有 lock，iCall、手動執行、cleanup、apply/rollback 可互相重疊。
- parsed/final 沒有原子發布及資料完整性門檻，部分資料可能被載入。
- cleanup 只在成功路徑執行，且 age-only retention 對 3.2 GB `/config` 過大。

---

## 3. 審核範圍與方法

本次已檢查：

- `scripts/*.sh` 七支核心腳本
- `patches/rpz_patch_sigpipe_v1.sh`
- `tests/lab/*.sh`
- `install.sh`、`cleanup.sh`、`package.sh`
- `config/icall_setup*.sh`、`config/cron_example.txt`
- `README.md`、`INSTALL_GUIDE.txt`
- `process.md`
- `RPZ_手動清檔作業說明_20260821.md`
- 四台 production 的 PuTTY log
- 現有 deployment tarball 與 tracked source 的 MD5

執行過的驗證包括：

- 所有 Shell 檔案 `bash -n`
- 真實 dnsxdump parser 集合比對
- `tmsh` 失敗注入
- SOA 全失敗注入
- patch selftest 失敗注入
- 原版/修正版 missing parsed 行為比較
- LAB patch selftest
- LAB 完整 `main.sh --force`
- LAB DataGroup revision/checksum/size 驗證
- LAB DNS 資料面查詢

沒有修改本機 tracked source，沒有 commit，也沒有接觸四台正式機。

---

## 4. 第一階段：SIGPIPE Hotfix 上線前必修

本節所有項目皆為正式上線前的必要條件。

### CR-01 — Blocker：missing parsed 從 hard failure 變成 false success

#### 位置

- `patches/rpz_patch_sigpipe_v1.sh:898-909`
- `patches/rpz_patch_sigpipe_v1.sh:915-925`

目前 embedded `generate_datagroup.sh`：

```bash
parsed_file=$(find_newest_file "${PARSED_DATA_DIR}/${zone}_"*.txt) || parsed_file=""

if [[ -f "$parsed_file" ]]; then
    cp ...
else
    touch "${FINAL_OUTPUT_DIR}/${zone}.txt"
fi
```

#### 問題機制

原版在 glob 完全沒有 match 時：

1. `ls` 退出非零。
2. `pipefail` 讓 command substitution 非零。
3. `set -e` 直接終止 `generate_datagroup.sh`。

修正版加入 `|| parsed_file=""` 後：

1. helper 的「找不到檔案」被轉成成功控制流。
2. 進入原本幾乎不可達的 `else`。
3. `touch final/<zone>.txt`。
4. 整個 generate step exit 0。
5. 若 production final 已存在且非空，`touch` 不會清除舊內容，只會更新 mtime。
6. step 5 可能重新載入舊內容並記錄成功，造成 false success。

#### LAB 獨立實測

相同的空 `parsed/` 條件：

```text
原版：
  exit=2
  final files=0

修正版：
  exit=0
  final files=3
  rpztw.txt=0 bytes
  phishtw.txt=0 bytes
  rpzip.txt=0 bytes
```

#### 必要修正

每個 zone 完全找不到 parsed artifact 時必須 hard fail：

```bash
local parsed_file
if ! parsed_file=$(find_newest_file "${PARSED_DATA_DIR}/${zone}_"*.txt); then
    die "找不到 ${zone} 的解析檔案"
fi

[[ -f "$parsed_file" ]] || die "解析檔案不存在: $parsed_file"
```

`rpzip` 同樣必須要求 timestamp artifact 存在，但允許檔案內容為空，因為目前來源沒有 IP 類型記錄。

請勿使用 `|| parsed_file=""` 再讓 missing artifact 進入成功分支。

#### 空檔政策

第一階段至少必須做到：

- missing artifact：一定失敗。
- `rpzip` artifact 存在但 0 bytes：允許。
- FQDN zone artifact 存在但 0 bytes：需明確記錄 warning；是否允許應在第二階段由資料完整性政策決定。

#### 驗收測試

- 無任何 parsed 檔：exit 非零，final 不變。
- 只缺 `phishtw`：exit 非零，final 不得部分發布。
- `rpzip` 存在但空：可成功。
- final 預先放入非空舊資料，再讓 parsed 缺檔：final 的 checksum/mtime 都不得被修改。

---

### CR-02 — Blocker：patch selftest 永遠不因測試失敗而失敗

#### 位置

- `patches/rpz_patch_sigpipe_v1.sh:224-290`

#### 問題

`do_selftest()` 只印出 `$f3/$reps` 和 `$fail/$reps`，最後一個命令是成功的 `echo`，沒有任何 assertion 或非零 return。

#### LAB 故障注入證據

將隔離副本的 `parse_rpz.sh` 換成 `/bin/false`：

```text
raw檔數  步驟3失敗  步驟4失敗
5         1/1         0/1
100       1/1         0/1
200       1/1         0/1
400       1/1         0/1

injected_selftest_exit=0
```

這代表 deployment automation 或工程師只看 `$?` 時會得到 false green。

#### 必要修正

1. 累計所有失敗數。
2. 任一 parse/generate failure 時 `return 1`。
3. setup、mkdir、sample 建立、cleanup 任一必要操作失敗時也必須非零。
4. 使用 `mktemp -d` 建立唯一目錄，不使用固定 `/var/tmp/rpz_selftest_dirs_`。
5. 使用 `trap` 清理測試目錄。
6. selftest 開始前確認 `detect_state` 是 `new`；未知或原版狀態不得被當成 patch 驗證成功。
7. 除了 exit code，還要驗證：
   - 最新 raw 確實被選中。
   - final 內容來自最新 parsed，而非舊檔。
   - rpztw/phishtw 筆數符合 fixture。
   - missing artifact 測試必須失敗。

建議結尾：

```bash
if [ "$total_failures" -ne 0 ]; then
    c_err "selftest 失敗，共 $total_failures 項"
    return 1
fi

c_ok "selftest 全部通過"
return 0
```

#### 驗收測試

- 正常 patched scripts：exit 0。
- parse 固定 exit 42：selftest exit 非零。
- generate 固定 exit 43：selftest exit 非零。
- sample 無法建立：selftest exit 非零。
- 腳本是 unknown MD5：selftest 拒絕執行或明確 exit 非零。

---

### CR-03 — Blocker：tracked source 與 deployment package 仍是缺陷版

#### 現況

Git status 沒有任何 tracked modification。以下檔案仍含原始 `ls | head`：

- `scripts/parse_rpz.sh:227`
- `scripts/generate_datagroup.sh:65`
- `scripts/generate_datagroup.sh:82`
- `scripts/utils.sh` 沒有 `find_newest_file()`

`package.sh:40` 直接從 tracked `scripts/*.sh` 打包，所以任何重新 package/install 都會把缺陷裝回去。

現有 `dist/rpz_local_processor_v1.2_20251202_140235.tar.gz` 的三個 MD5 也都是原版：

```text
utils.sh               3cab6cbca952f3780350e9882e5f7c11
parse_rpz.sh           bbe45c6f79b56922388d4af7aa6e7583
generate_datagroup.sh  35547d33ce109945d1ca17e8eb241e0a
```

根目錄 `RPZ_Local_Processor.tar.gz` 只有 29 bytes，是空 archive，不可作為部署包。

#### 必要修正

1. 將正確 hotfix 寫入 tracked source。
2. patch embedded 內容必須從同一份 tracked source 產生或至少 byte-for-byte 對照。
3. 新增測試：patch apply 後的三個 installed scripts 必須與 tracked hotfix source 完全一致。
4. 更新 package version，例如 `1.2.1`；實際版本名稱由維護者決定。
5. 重新建立 deployment package，加入 SHA-256 manifest。
6. 清楚標示舊 dist artifact 不可部署；未經使用者同意不要直接刪除既有檔案。
7. 更新 `process.md` 中所有 MD5。

#### 驗收測試

- `rg 'ls -t.*head -1' scripts/` 不得命中三個缺陷位置。
- package 解開後的 scripts 與 tracked source checksum 相同。
- 從新 package 安裝到隔離目錄後，跑相同 selftest 必須成功。

---

### CR-04 — High：apply/rollback 不是完整 transaction，rollback 順序不安全

#### 位置

- `FILES="utils.sh parse_rpz.sh generate_datagroup.sh"`：patch line 53
- apply：patch line 173-219
- rollback：patch line 295-321

#### 問題

Apply 順序是 provider `utils.sh` 先、新 consumers 後，依賴關係尚可；但 rollback 也使用相同順序：

1. 先把 `utils.sh` 還原成沒有 `find_newest_file()` 的原版。
2. `parse_rpz.sh`、`generate_datagroup.sh` 暫時仍是 patched consumer。
3. iCall 若在窗口內啟動，patched consumer 會找不到 helper。

此外 rollback 使用直接 `cp -p` 覆寫目的檔，不是 temp + rename；讀檔程序可能看到部分內容。

Apply 也沒有做到三檔整體 transaction：第二或第三檔失敗時，會留下 partial state，且不自動 rollback。

#### 必要修正

1. 先把三個新檔全部寫到 staging，完成以下檢查後才開始替換：
   - checksum
   - `bash -n`
   - 必要 helper 存在
   - embedded 與 tracked source 一致
2. backup 使用 `mktemp -d`，避免 predictable `/var/tmp` 名稱及 symlink 問題。
3. 每一檔都使用同目錄 temp + atomic rename。
4. Apply 安裝順序：
   - `utils.sh`
   - `parse_rpz.sh`
   - `generate_datagroup.sh`
5. Rollback 順序必須反向處理 consumers，再處理 provider：
   - `parse_rpz.sh`
   - `generate_datagroup.sh`
   - `utils.sh`
6. 任一替換失敗時自動恢復到 apply 前的完整狀態。
7. Rollback 前驗證：
   - 目前狀態是預期 patched state。
   - backup 三檔 checksum 是完整原版。
   - unknown state 預設拒絕覆寫。
8. `.rpz_patch_last_backup` 也應用 temp + atomic rename 建立。

#### 維護窗口要求

目前正式程式沒有 lock，因此第一階段部署 SOP 必須要求：

1. 將 `rpz_processor_handler` 暫時設為 inactive。
2. 確認沒有執行中的 processor。
3. apply、selftest、`main.sh --force`、驗證。
4. 重新設為 active。
5. 再執行一次 `tmsh save sys config`。

注意：`main.sh --force` 內會執行 `tmsh save sys config`。若當時 handler 是 inactive，inactive 狀態會被存檔，所以最後 re-enable 後必須再 save。

---

### CR-05 — High：hotfix cleanup 參數與並行安全不足

#### 位置

- `patches/rpz_patch_sigpipe_v1.sh:323-369`

#### 問題

- `KEEP` 沒有驗證；`KEEP=0` 會刪除所有匹配的 raw/parsed。
- 沒有 lock 或 active-run 檢查。
- `cleanup-dry` 與 `cleanup` 之間檔案集合可以改變。
- 使用 `ls` 輸出當檔案清單；目前檔名受控所以可運作，但不是穩健 API。
- cleanup 成功訊息使用預先計算的 total，未核對實際刪除數。

#### 必要修正

- `KEEP` 必須為整數且大於等於 1；建議另外設定合理上限。
- cleanup 必須和 main 共用同一把 lock，或 SOP 明確要求 handler inactive。
- 僅處理：
  - `raw/dnsxdump_*.out`
  - `parsed/<configured-zone>_*.txt`
  - `parsed/rpzip_*.txt`
- 必須使用 `-maxdepth 1` 或等價限制。
- 永遠不可遍歷或刪除 `final/`。
- 刪除前後記錄實際檔數、bytes、final checksum。
- 任一刪除失敗時 exit 非零，不可一律回成功。

---

## 5. 第二階段：既有高風險流程修正

本節不建議未經拆分就併入緊急 SIGPIPE hotfix，但必須建立獨立 patch/版本及測試。

### CR-06 — Critical：SOA 取得錯誤被誤判為 NO_UPDATE

#### 位置

- `scripts/check_soa.sh:82-115`
- `scripts/check_soa.sh:121-150`
- `scripts/main.sh:115-130`

#### 現況

`check_zone_update_needed()`：

- 0：需要更新
- 1：沒有更新
- 2：SOA 取得失敗

但 `check_all_zones()` 只寫：

```bash
if check_zone_update_needed "$zone"; then
    update_needed=1
fi
```

return 1 和 return 2 都被當成相同的 false，最後可能輸出 `NO_UPDATE`。

#### LAB 獨立實測

兩個 zone 的 `DNSXDUMP_CMD=/bin/false`：

```text
[ERROR] 無法取得 rpztw 的 SOA Serial
[ERROR] 無法取得 phishtw 的 SOA Serial
[INFO] 所有 Zones 均無變更
NO_UPDATE
check_all_exit=0
```

`main.sh` 現有 grep/tail capture 也得到：

```text
captured_status=NO_UPDATE
captured_exit=0
```

#### 必要修正

逐 zone 用 `case` 區分三種狀態：

- changed
- unchanged
- error

只要任何 zone error：

- 不得輸出 `NO_UPDATE`。
- `check-all` 必須非零退出。
- main 必須記錄原始診斷訊息並 exit 非零。

`main.sh` 不可再用 pipeline 最後一段的 `$?` 當成 `check_soa.sh` 退出碼。建議：

```bash
if soa_raw=$(bash "${SCRIPT_DIR}/check_soa.sh" check-all 2>&1); then
    soa_rc=0
else
    soa_rc=$?
fi
```

接著從 `$soa_raw` 解析唯一的 machine-readable status，並把其他行保留到 log。

#### 必測情境

- 全部 unchanged。
- 一個 changed、一個 unchanged。
- 全部 error。
- 一個 error、一個 unchanged。
- 一個 error、一個 changed。
- 輸出格式異常。

---

### CR-07 — Critical：SOA cache 在完整成功前提交

#### 位置

- `scripts/check_soa.sh:98-114`
- `scripts/main.sh:138-175`

#### 問題

SOA cache 在 step 1 偵測到 changed 時立刻寫入；step 2-5 任一失敗時不回滾。

因此：

1. cache 已前進。
2. DataGroup 可能仍是舊資料或只有部分更新。
3. 下一個 iCall 判定 `NO_UPDATE`。
4. 只有下一次 SOA 再變更或人工 `--force` 才可能補回。

#### 必要設計

SOA 應採 prepare/commit：

1. step 1 只讀取 current/cached，產生 pending serial map。
2. 不修改正式 cache。
3. step 2-5 全部成功後，才原子寫入每個 cache。
4. 任一失敗時 cache 完全不變，下一輪自動重試。

Cache 檔寫入使用 temp + fsync（若可行）+ rename，至少必須 temp + rename。

`--force` 的語意也要定義：成功完成 forced run 後，應將同一次資料 snapshot 的 SOA 寫入 cache，避免 cache 與已載入資料不同步。

---

### CR-08 — High：SOA serial 比較不支援回退或 rollover

#### 位置

- `scripts/check_soa.sh:105-109`

目前：

```bash
if [[ "$current_soa" -le "$cached_soa" ]]; then
    return 1
fi
```

對本專案而言，只要 serial 與 cache 不同，就應重新建立完整 DataGroup；不需要只接受數值增加。

#### 必要修正

- 驗證 current/cached 都是合法十進位數字。
- 以 `current != cached` 判斷需要更新。
- 對 invalid cache 記錄錯誤並採安全重建策略，不可直接當健康的 NO_UPDATE。
- 補測 serial decrease、32-bit rollover、空 cache、損毀 cache。

---

### CR-09 — High：沒有全流程 lock

#### 影響

可能重疊的來源：

- iCall periodic execution
- 手動 `main.sh --force`
- 手動 cleanup
- patch apply/rollback
- 安裝程式覆寫 scripts

輸出檔名只有秒級 timestamp；同秒重疊可能寫同一檔案。兩個程序也可能交錯更新 SOA cache、raw、parsed、final 與 DataGroup。

LAB 已確認具備：

```text
/bin/flock
flock from util-linux 2.23.2
```

#### 必要修正

在 `main.sh` 最前面取得 non-blocking exclusive lock，並讓 lock 持續到整個 main 結束。

建議 lock path 使用明確固定路徑，例如：

```text
/var/run/rpz_local_processor.lock
```

重疊的 periodic run 應記錄 warning 後正常跳過；手動模式是否回傳特定非零碼需文件化。

Cleanup、install、apply、rollback 必須共用相同協調機制，或在操作前確認 handler inactive。

#### 必測情境

- 第一個程序持有 lock 時啟動第二個 main。
- manual force 與 iCall 同時啟動。
- cleanup 與 main 同時啟動。
- 程序被 SIGTERM/SIGKILL 後 lock 能由 kernel 自動釋放。

---

### CR-10 — Critical：artifact 與 final 發布缺乏 transaction/完整性保護

#### 位置

- `scripts/extract_rpz.sh:38-54`
- `scripts/parse_rpz.sh:76-192`
- `scripts/generate_datagroup.sh:62-93`
- `scripts/update_datagroup.sh:148-189`

#### 問題

- `DNSXDUMP_FILE`、`PARSED_TIMESTAMP`、`FINAL_OUTPUT_DIR` 等 export 都發生在 child shell，傳不回 `main.sh`。
- 各階段只能重新掃目錄猜最新檔，不是使用同一個 run manifest。
- parsed 與 final 直接寫正式檔名，沒有完整完成後才發布。
- final 使用 `cp` 直接覆寫，可能留下非空但截斷的檔案。
- non-empty partial data 會通過 `-s` 檢查並被 tmsh 載入。
- 各 DataGroup 獨立更新，第二個失敗時第一個可能已更新；配合過早提交 SOA cache，失敗 zone 不一定會重試。
- 空檔只被跳過，沒有清楚區分「合法空 zone」與「資料損毀」。

#### 必要設計方向

1. `main.sh` 產生唯一 `run_id`。
2. main 明確把本次 raw path、parsed timestamp、staging/final path傳給子腳本。
3. 每個 stage 只能使用同一 run 的 artifact，不再掃整個歷史目錄猜 latest。
4. dnsxdump 先寫 `.tmp`，成功且通過基本驗證後 rename。
5. parse 每個 zone 先寫 `.tmp`，全部完成並驗證後一次發布該 run 的 parsed artifacts。
6. final 先寫同目錄 temp，再 atomic rename。
7. 在 tmsh 前驗證：
   - 語法格式
   - 記錄筆數
   - landing IP 合法性
   - configured zones 都有 artifact
   - 與上次筆數的變化是否超出可接受門檻
8. 筆數下降門檻必須可配置並有 bootstrap 行為；不要把 80% 未經確認地硬編碼。
9. 全部 DataGroup 更新成功後才 commit SOA cache。
10. 記錄每次 run manifest：run_id、SOA、raw checksum、各 zone count、final checksum、tmsh 結果。

---

### CR-11 — High：cleanup 與磁碟生命週期設計不足

#### 位置

- `scripts/main.sh:75-95`
- `scripts/main.sh:175`
- `scripts/extract_rpz.sh:79-80`

#### 已確認問題

1. cleanup 只有五步驟全成功後才執行。
2. `find "$OUTPUT_DIR" -type f -mtime +7 -delete` 掃描範圍包含 `final/`。
3. `DNSXDUMP_FILE` 從 child export，父程序永遠收不到，所以當次 raw 不會被刪除。
4. age-only retention 在目前約 14 次/日的速率下，會保留約 112 輪。
5. 約略穩態空間：raw 1.2 GB 加 parsed 0.4-0.6 GB；對 3.2 GB `/config` 仍偏大。
6. 沒有磁碟 free-space preflight。
7. `OUTPUT_DIR` 可由環境變數覆寫，cleanup 前沒有防止 `/`、`/config` 等危險值的 guard。

#### 必要修正

- cleanup 只能對 raw/parsed 的明確 pattern 操作，永不包含 final。
- 使用 age + count 雙門檻；count 應依磁碟容量和 troubleshooting 需求決定。
- 評估將 raw/parsed 移到 `/shared`，只把 final 保留在 `/config`。
- 在 extract 前檢查百分比與 absolute free bytes。
- 清理必須在 failure path 也能安全執行，但不得刪除本次 run artifact。
- 對 production path 加 allowlist/拒絕危險根目錄。
- 日誌需記錄 cleanup 實際刪除數與釋放 bytes。

#### Wrapper log

`/config/snmp/rpz_wrapper.log` 沒有 rotate。Production 已超過 52 萬行。

建議優先使用 F5 既有 syslog/rotation；若保留獨立檔案，需實作可靠 rotation。操作文件目前的 `cp log backup; : > log` 會遺失 copy 與 truncate 之間寫入的內容，且可能截掉正在執行中的 wrapper 記錄。

---

### CR-12 — High：`cleanup.sh` 的保留 DataGroup 選項不安全

#### 位置

- iCall 名稱：`cleanup.sh:20-29`
- 刪除 output：`cleanup.sh:121-139`
- wrapper 清理：`cleanup.sh:142-155`
- DataGroup 選項：`cleanup.sh:158-206`

#### 問題

1. script 在詢問是否保留 DataGroup 前，已先刪除整個 output，包括 `final/` source files。
2. 使用者選「保留 DataGroups」時，DataGroup 物件雖仍在，但 source path 已消失。
3. current iCall 名稱被標成 old；雖然目前兩組都嘗試刪除，但文件與輸出會誤導。
4. current wrapper 位於 `/config/snmp/rpz_wrapper.sh` 與 `.log`，cleanup 只刪 `/var/tmp` 舊路徑。
5. 如果沒有 external DataGroup，`RPZ_DGS` 可能未初始化，在 `set -u` 下中止。
6. destructive path 沒有足夠的 canonical path 驗證。

#### 必要修正

- 一開始先詢問 DataGroup/final 的保留策略，再執行任何刪除。
- 若保留 DataGroup，必須保留有效 final source，或明確遷移到受管理位置。
- 若移除 DataGroup，先解除/刪除 DataGroup，再刪 source files。
- 修正 current/legacy iCall 名稱與 wrapper path。
- 一開始初始化所有變數。
- 對所有 recursive delete 做 exact path guard。
- 使用 stub tmsh 與隔離 filesystem 建立非破壞測試。

---

### CR-13 — Medium：RPZ IP DataGroup backend 型別不一致

#### 位置

- `scripts/parse_rpz.sh:122-140`
- `scripts/parse_rpz.sh:170-179`
- `scripts/update_datagroup.sh:64-67`

Parser 將 rpz-ip CNAME 轉成：

```text
network <ip>/<mask>,
```

但 `create_datagroup()` 對所有 DataGroup 都固定使用：

```bash
type string
```

#### 必要處理

二選一並文件化：

1. 若保留 IP DataGroup 功能：`rpzip` 應使用正確的 IP type、格式與專屬測試 fixture。
2. 若目前不支援：停用或移除這條未完成路徑，不要宣稱支援 IP RPZ。

目前真實樣本沒有 CNAME/rpz-ip，因此既有 A-record 測試沒有涵蓋此功能。

---

### CR-14 — Medium：iCall setup 的認證與更新流程不安全

#### 位置

- `config/icall_setup_api.sh:12-17`
- `config/icall_setup_api.sh:74-157`

#### 問題

- `F5_PASS` 預設為 `admin`。
- `curl -k` 關閉憑證驗證；若 `F5_HOST` 不是 localhost，存在 MITM 風險。
- 密碼放在 curl command arguments，可能出現在 process list。
- setup 先刪除既有 handler/script，再建立新物件；建立失敗時排程已消失。
- `INTERVAL` 未驗證為合法正整數。
- tracked `config/icall_setup.sh` 仍使用舊 `/var/tmp` 路徑，容易誤用。

#### 必要修正

- 未提供 password/token 時直接拒絕，不可有預設密碼。
- localhost 與 remote host 分開處理 TLS policy。
- 改成 update/upsert 或先建立驗證後切換，避免 delete-first。
- 驗證 interval。
- 將舊 setup script 明確標為 deprecated，或移除其可執行入口並更新文件。

---

### CR-15 — Medium：Zone 設定未驗證，且 export 架構存在系統性誤解

#### 位置

- `scripts/check_soa.sh:129-139`
- `scripts/parse_rpz.sh:30-47`
- `scripts/generate_datagroup.sh:28-35`
- `scripts/update_datagroup.sh:30-37`

#### 問題

- zone 內容直接成為 regex、檔名與 tmsh object name。
- 只 escape `.`，沒有完整驗證合法 zone/DataGroup 名稱。
- `grep "$zone_name"` 沒有 `--`、不是 exact owner match，且把 zone 當 regex。
- nested zones 可能同時匹配；AWK associative iteration 順序不保證，record 可能被分到錯誤 zone。
- `config/rpz_zones.conf` 使用 trailing dot，`zonelist.txt` 則要求不帶 dot，兩份設定易混淆。
- 多個 child script export 的變數無法回到 main，應改為明確 input/output contract。

#### 必要修正

- 集中實作並使用 zone validation。
- 明確禁止 path separator、whitespace、以 `-` 起始的 option-like 值及不支援字元。
- SOA owner 使用 exact field match，不用寬鬆 grep。
- nested zone 使用 longest suffix 或明確拒絕重疊設定。
- 移除或標記未使用的 `rpz_zones.conf`。
- 每個 script 文件化 stdin/stdout/exit/artifact contract，不依賴 child-to-parent export。

---

### CR-16 — High：LAB destructive test 缺少足夠防呆

#### 位置

- `tests/lab/f5_manual_cleanup_test.sh`

這支腳本會直接：

- 刪 `/config/snmp/rpz_datagroups/raw` 的檔案。
- 刪 parsed 檔案。
- 執行 production path 的 `main.sh --force`。

它沒有像 `f5_pipefail_probe.sh` 一樣的 production marker guard，也沒有 hostname/IP allowlist 或確認旗標。

#### 必要修正

- 預設拒絕執行。
- 同時要求：
  - 明確 `--lab-only`/`--i-know`。
  - hostname 或 LAB marker 符合。
  - 互動確認即將操作的 exact path。
- production marker 存在時預設拒絕；override 必須非常明確。
- 文件首頁及腳本輸出都要標示 destructive LAB only。
- 此腳本不可放進 production deployment package。

---

## 6. 文件需修正的內容

### DOC-01 — 4096 bytes 的技術描述

`RPZ_手動清檔作業說明_20260821.md` 將問題描述成「Linux pipe 緩衝區是 4096 bytes」。

較精確的說法應是：

- 本 LAB 組合下，`ls` 對 pipe 的 userspace stdio write buffer 約為 4096 bytes。
- Linux pipe capacity 並不等於 4096 bytes。
- 超過 4096 bytes 後需要多次 write，搭配 `head -1` 的提前關閉才產生 SIGPIPE 機會。
- 失敗是排程相關競態，不是每次超過門檻都必然失敗。

### DOC-02 — `final/rpzip.txt` mtime 的證據強度

`final/rpzip.txt` mtime 只能證明 `generate_datagroup.sh` 至少完成到 step 4，不能單獨證明 step 5 的 `tmsh modify` 已成功。

「最後一次完整成功」必須搭配：

- wrapper 中兩個 zone 的 tmsh success log；或
- `sys file data-group` revision/checksum；或
- 其他可證明 memory DataGroup 已重新載入的資料。

請把 `process.md` 中以 mtime 直接推定完整成功的文字降級成「最後一次完成 final 產生的時間／完整成功的上限證據」。

### DOC-03 — Production 失敗率

53%-87% 是依 LAB 同檔數情境推估，不是 production 直接量測。文件已有部分說明，但摘要與 SOP 不應寫成 production 的實測失敗率。

### DOC-04 — patch selftest 結論

在 CR-02 修正前，文件不得把 `selftest` exit 0 當成自動化驗收證據。既有人工表格結果可保留，但需說明舊 selftest 沒有 assertion。

### DOC-05 — 手動清檔與 log 操作

- `-mmin +10` 的中間檔清理方向合理。
- 若 iCall 在步驟 A-E 期間完成一次更新，final mtime 合法變化，不應一律解讀成異常。
- 建議 SOP 先停用 handler 或取得 lock，再清理。
- `cp log; : > log` 有競態，需更換成可靠 rotation 流程。

### DOC-06 — 更新規格文件

修正後至少同步：

- `process.md`
- `docs/SCRIPT_SPECIFICATIONS.md`
- `docs/TRAINING_GUIDE.md`
- `docs/archive/KNOWN_ISSUES.md`
- `README.md`
- `INSTALL_GUIDE.txt`

---

## 7. 自動化測試與驗收矩陣

Claude Code 不應只增加 happy-path 測試。以下情境必須能由退出碼自動判斷。

### 7.1 Hotfix helper 與 call-site

| 測試 | 預期 |
|---|---|
| raw 0 檔 | parse 明確錯誤、非零退出 |
| raw 1 檔 | 選中唯一檔案 |
| raw 67/68/100/400 檔 | 穩定選中真正最新檔，0 次 SIGPIPE |
| 相同 mtime 多檔 | tie-break 行為明確且測試固定 |
| glob 只有目錄/壞 symlink | 不得選為輸入 |
| parsed 全缺 | generate 非零、final 不變 |
| 只缺一個 zone | generate 非零、所有 final 不變 |
| rpzip 存在但空 | 依政策成功 |
| helper 人為 return 1 | caller 非零且有清楚 log |

### 7.2 Patch lifecycle

| 測試 | 預期 |
|---|---|
| orig -> apply | 三檔皆為 new checksum |
| 重複 apply | 冪等，不建立錯誤狀態 |
| unknown -> apply | 拒絕且不修改任何檔案 |
| 第二檔安裝故障注入 | 自動回到完整 orig |
| new -> rollback | 三檔皆完整 orig |
| rollback backup 缺檔/錯 hash | 拒絕且不修改 |
| selftest parse failure | 非零退出 |
| selftest generate failure | 非零退出 |
| embedded vs tracked source | byte-for-byte 相同 |

### 7.3 SOA state machine

| 測試 | 預期 |
|---|---|
| all unchanged | NO_UPDATE，0 |
| one changed | UPDATE_NEEDED，cache 尚未提交 |
| any lookup error | 非零，不得 NO_UPDATE |
| pipeline step 2/3/4/5 任一失敗 | cache 不變 |
| full success | cache 原子提交 |
| serial decrease | 觸發更新 |
| corrupt cache | 告警並安全重建/失敗，不可靜默略過 |

### 7.4 Artifact integrity

| 測試 | 預期 |
|---|---|
| dnsxdump 非零退出且留 partial file | partial 不發布 |
| parse 中途失敗 | 不發布任何本次 parsed/final |
| 新筆數只剩舊資料 1% | 拒絕或要求明確 override |
| final rename 前中止 | 舊 final 完整保留 |
| tmsh 第一個成功、第二個失敗 | SOA 不提交、下一輪可重試 |
| empty zone | 依明確政策處理並有告警/審計 |

### 7.5 Lock 與 cleanup

| 測試 | 預期 |
|---|---|
| 兩個 main 同時啟動 | 僅一個實際執行 |
| main 執行中 cleanup | cleanup 拒絕/等待，不刪本次檔案 |
| OUTPUT_DIR=/ 或 /config | 程式拒絕 destructive cleanup |
| 超過 age 但屬於 final | 永不刪除 |
| count 超限 | 只刪允許 pattern 的最舊檔 |

### 7.6 靜態與 packaging

- `bash -n`：所有 Shell 檔案。
- 建議加入 `shellcheck`，並對必要例外做局部註解。
- `rg 'ls -t.*head -1' scripts/` 不得命中已修正位置。
- package 解開後做 checksum/語法/selftest。
- deployment package 不得包含 `tests/lab/f5_manual_cleanup_test.sh`。

---

## 8. 建議實作順序

### Phase 1A — 修正現有 hotfix，不擴張功能

1. 修 CR-01 missing artifact false success。
2. 修 CR-02 selftest assertions。
3. 修 CR-04 apply/rollback transaction 與順序。
4. 修 CR-05 cleanup 參數、防呆與 exact scope。
5. 把 helper/call-site 寫入 tracked source。
6. 補 hotfix tests。
7. 更新 patch MD5、文件與 package version。

### Phase 1B — LAB 驗收

1. 全部自動化測試通過。
2. 在 `/var/tmp` 隔離重跑原版/修正版比較。
3. 暫停 LAB iCall 後測 apply/selftest/main/rollback/apply。
4. 完整 `main.sh --force`。
5. 驗證 final checksum、筆數、DataGroup revision。
6. 恢復 handler active 並 save。
7. 觀察至少兩個 periodic interval。

### Phase 1C — Production rollout 前置

四台逐台取得：

```bash
tmsh show sys version | head -8
md5sum /config/snmp/RPZ_Local_Processor/scripts/*.sh
tmsh list sys icall handler periodic rpz_processor_handler
df -h /config
```

任何腳本 MD5 不是明確支援版本時，停止 apply，不得強行 patch。

### Phase 2 — Reliability release

依序處理：

1. CR-06 SOA error classification
2. CR-07 transactional cache
3. CR-08 serial inequality
4. CR-09 flock
5. CR-10 run manifest、atomic artifacts、資料門檻
6. CR-11 cleanup/disk/log lifecycle
7. CR-12 uninstall safety
8. CR-13 至 CR-16

Phase 2 應有獨立版本與 rollback，不與緊急 SIGPIPE patch 混為單一不可控變更。

---

## 9. LAB 獨立驗證紀錄

### 9.1 LAB 狀態

```text
Host: cdns.ryantseng.work / 10.8.34.223
BIG-IP: 17.1.3.1 Build 0.0.6 Point Release 1
iCall interval: 300 seconds
```

Installed patched MD5：

```text
utils.sh               b15b77ba5377299e25cad3874c290165
parse_rpz.sh           cef0a74418c2ac900f6894892a1d85d2
generate_datagroup.sh  05f80d698a76e09d14c57fe58c672f34
```

### 9.2 正常 selftest

`REPS=3`：

```text
raw檔數  ls輸出   步驟3失敗  步驟4失敗
5         305B      0/3         0/3
100       6100B     0/3         0/3
200       12200B    0/3         0/3
400       24400B    0/3         0/3
```

### 9.3 selftest 故障注入

隔離副本的 parse 固定失敗：四組皆 1/1 failure，但 selftest exit 0。此結果支持 CR-02。

### 9.4 missing parsed 比較

```text
Original generate: exit 2, final files 0
Patched generate:  exit 0, final files 3
```

此結果支持 CR-01。

### 9.5 SOA failure injection

```text
rpztw lookup error
phishtw lookup error
result=NO_UPDATE
exit=0
```

此結果支持 CR-06。

### 9.6 完整 forced run

2026-08-21 13:44 執行：

```text
dnsxdump rows: 185453
rpztw rows: 58610
phishtw rows: 819
elapsed: 8 seconds
main exit: 0
rpztw revision: 6 -> 7
rpztw checksum: SHA1:2243064:c6cb61d836833feccb7759ba46c6d01b15163bb0
```

Forced run 前後 checksum/size 相同，表示重新載入的是相同完整資料。

LAB 最終狀態：

```text
raw files: 2
parsed files: 6
review temp dirs: 0
rpztw revision: 7
```

---

## 10. Production 上線驗收條件

每台必須全部滿足：

### 套用前

- BIG-IP version 已記錄。
- 七支 script MD5 已記錄並符合支援矩陣。
- `/config` 與 `/shared` free space 已記錄。
- final checksum、mtime、line count 已記錄。
- DataGroup revision/checksum 已記錄。
- iCall 已安全停用，且沒有執行中程序。
- rollback backup 已建立並在不同分割區驗證可讀。

### 套用後

- `check` 判定三檔全為 patched state。
- `bash -n` 全通過。
- selftest exit 0，且內部 failure count 全為 0。
- `main.sh --force` exit 0。
- 各 configured FQDN zone record count 合理。
- DataGroup revision 有增加。
- checksum/size 與 final 對應。
- final 三檔來自同一 run。
- iCall 已恢復 active 並再次 save config。
- 下一個 periodic run exit 0。

### Rollback 條件

以下任一發生即停止 rollout：

- unknown MD5/state
- selftest 非零或任何 failure count 非零
- missing artifact
- record count 異常下降
- tmsh update/save 失敗
- DataGroup revision/checksum 無法驗證
- DNS 資料面驗證異常

Rollback 必須在 handler inactive 狀態執行，且完成後重新驗證三檔 checksum。

---

## 11. Claude Code 交付要求

完成處理時，請提供：

1. 修改檔案清單。
2. 每個 CR 編號的處理狀態：完成／另案／不處理及理由。
3. tracked source 的實際 diff。
4. patch embedded source 與 tracked source 一致性的證據。
5. 自動化測試輸出及退出碼。
6. 新 package 名稱、SHA-256 及內容 manifest。
7. LAB 測試對環境造成的變化與復原結果。
8. 更新後的 production SOP 與 rollback SOP。

限制：

- 不修改任何 iRule/TCL。
- 不 commit、不 push。
- 不刪除使用者既有的 untracked 文件、log、壓縮檔或測試資料。
- 不在 production 執行 `tests/lab/`。
- 不把 `f5_manual_cleanup_test.sh` 放入 production package。
- 未取得四台 production version/MD5 前，不宣稱 patch 已可無條件套用。

---

## 12. 最終審核判定

### Root cause

**通過。** 三處 `ls -t | head -1` 與 SIGPIPE/pipefail 的因果關係有充分證據。

### 核心 helper

**方向通過。** `find_newest_file()` 能解除檔案數門檻，LAB 及完整 pipeline 均成功。

### 現有 patch artifact

**不通過。** CR-01、CR-02、CR-03、CR-04 修正前不得作為正式完成版 rollout。

### 專案整體可靠性

**需第二階段修正。** SOA state machine、transaction、locking、artifact validation、cleanup/disk lifecycle 仍可能造成無告警的 stale DataGroup 或不完整更新。
