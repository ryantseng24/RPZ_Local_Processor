# RPZ Local Processor Phase 1A 第二輪獨立審核

**文件日期**：2026-08-21  
**審核依據**：`REVIEW_HANDOFF_PHASE1A.md`、實際 working tree、v1.2.1 package、隔離故障注入與 LAB 驗證  
**處理對象**：Claude Code  
**目前判定**：`NO-GO` — Phase 1A 尚不可宣告完成或直接 rollout  
**範圍排除**：不審核、不要求修改 iRule/TCL

---

## 1. 給 Claude Code 的結論

核心 SIGPIPE 修正已通過第二輪獨立驗證：

- `find_newest_file()` 能消除三處 `ls -t | head -1` 的 SIGPIPE。
- missing raw/parsed artifact 已恢復 hard failure。
- 缺少後段 zone artifact 時，不會先發布前段 zone。
- patch selftest 已有可真正失敗的 assertion。
- patch embedded source、tracked source 與目前 v1.2.1 package 的三支修正版一致。
- LAB 行為矩陣與 patch selftest 都通過。

但第二輪找到下列尚未完成的項目：

| 編號 | 嚴重度 | 結論 |
|---|---|---|
| R2-01 | Blocker | patch cleanup 可透過 zone path traversal 越出 `parsed/`，現有 `final/` guard 可被繞過 |
| R2-02 | High | rollback 任一檔失敗時會留下 orig/new 混合版本 |
| R2-03 | High | destructive LAB test 的 guard 路徑與真正操作路徑不一致 |
| R2-04 | High | 新版 installer 在 manifest 或 `sha256sum` 缺少時 fail-open |
| R2-05 | Medium | `REPS=0` 可讓 S8/S9 完全不執行但 selftest 回傳成功 |
| R2-06 | Medium | source consistency gate 沒有涵蓋全部 package inputs 與外層 checksum |
| R2-07 | Medium | installer 新增的路徑 override 沒有安全邊界 |

R2-01 至 R2-07 修正並通過本文件驗收矩陣前，請不要：

- 將 `dist/DO_NOT_DEPLOY.md` 中 v1.2.1 描述為無條件可部署。
- 對 production 執行 patch 的 `cleanup`。
- 宣告 CR-04、CR-05、CR-16 已完整結案。
- commit 或 push。

---

## 2. R2-01 — Blocker：cleanup 可越出允許目錄

### 2.1 位置

- `patches/rpz_patch_sigpipe_v2.sh:596-608`：`cleanup_specs()`
- `patches/rpz_patch_sigpipe_v2.sh:610-614`：`cleanup_victims()`
- `patches/rpz_patch_sigpipe_v2.sh:639-671`：計數與實際刪除
- `patches/rpz_patch_sigpipe_v2.sh:664-666`：`final/` 文字比對 guard

### 2.2 問題機制

`cleanup_specs()` 直接把 `zonelist.txt` 的內容放進：

```bash
printf 'parsed:%s_*.txt\n' "$z"
```

後續又把它當成未引用的 glob 使用：

```bash
ls -t "$DATA_DIR/$subdir"/$pattern
```

目前沒有拒絕：

- `/`
- `..`
- `*`、`?`、`[]`
- colon
- option-like 值
- 其他不支援的 zone/DataGroup 字元

因此 zone 可以把搜尋範圍帶出 `parsed/`。

現有 guard：

```bash
case "$victim" in
    "$DATA_DIR/final"/*) ...
esac
```

只比對原始字串，沒有 canonicalize。像這個 victim：

```text
$DATA_DIR/parsed/../final/evil_20260101_000001.txt
```

實際上位於 `final/`，但字串不是以 `$DATA_DIR/final/` 開頭，因此不會被 guard 擋住。

### 2.3 獨立重現證據

在 `/tmp` 隔離目錄中使用 zone：

```text
../final/evil
```

並在測試用 `final/` 放兩個 `evil_*.txt` 後執行 `cleanup-dry`，實際輸出：

```text
parsed   ../final/evil_*.txt  待刪 1 / 共 2
```

這證明「`final/` 永不在刪除範圍」目前不成立。測試只執行 dry-run，沒有真的刪檔。

### 2.4 必要修正

1. 在任何 cleanup 計數或展開 glob 之前驗證全部 configured zones。
2. zone 至少必須拒絕：
   - path separator
   - `.` 或 `..` path component
   - shell glob metacharacters
   - whitespace/control characters
   - colon
   - 以 `-` 起始的 option-like 值
3. 不要只依賴字串 prefix 保護；刪除前必須驗證 victim 的 canonical parent：
   - raw victim 的 parent 精確等於 `$DATA_DIR/raw`
   - parsed victim 的 parent 精確等於 `$DATA_DIR/parsed`
4. 對 `DATA_DIR` 本身做安全驗證：
   - 必須是絕對路徑
   - 不得為 `/`
   - 不得為空白或含 unresolved traversal
5. duplicate zone 不得造成 total 重複計數或第二次刪除。
6. 若 `deleted != planned`，必須明確說明原因並依政策回傳非零，不能只印數字後成功。

### 2.5 必測情境

| 輸入 | 預期 |
|---|---|
| `rpztw`、`phishtw` | 正常列出各自 parsed victims |
| `../final/evil` | 在任何檔案列舉前拒絕，exit 非零 |
| `../../outside` | 拒絕，exit 非零 |
| `*`、`?`、`[abc]` | 拒絕，exit 非零 |
| `-rf` | 拒絕，exit 非零 |
| zone 重複兩次 | 拒絕或去重；不得重複計數 |
| 合法 zone + unrelated file | unrelated file 不得列入或刪除 |
| 所有反向測試 | `final/` checksum 完全不變 |

---

## 3. R2-02 — High：rollback 仍非完整 transaction

### 3.1 位置

- `patches/rpz_patch_sigpipe_v2.sh:341-351`：`restore_from()`
- `patches/rpz_patch_sigpipe_v2.sh:390-400`：`do_rollback()`

### 3.2 問題

正常 rollback 的 consumer-first 順序正確，且單檔使用同目錄 temp + rename，這兩點已通過。

但 `do_rollback()` 在任一檔安裝失敗後直接回傳：

```bash
if ! install_file ...; then
    c_err "還原 $f 失敗"
    return 1
fi
```

它不會把前面已還原成 orig 的檔案重新切回 new。因此 rollback failure 仍會留下 mixed state。

### 3.3 獨立故障注入

起始狀態：三支皆為 new。  
注入點：第二個 rollback target `generate_datagroup.sh` 的 `mktemp` 失敗。

結果：

```text
[ OK ] parse_rpz.sh 已還原
[FAIL] 還原 generate_datagroup.sh 失敗
rollback rc=1

parse_rpz.sh             orig
generate_datagroup.sh    new
utils.sh                 new
```

此結果違反 CR-04「任一替換失敗時恢復完整狀態」的要求。

### 3.4 必要修正

1. rollback 前先準備並驗證：
   - 完整 orig staging
   - 完整 new recovery staging，或可重新從 embedded new source 產生
2. rollback 中途失敗時，將已還原的檔案重新切回完整 new state。
3. recovery 本身任一失敗需：
   - exit 非零
   - 明確列出每支檔案的實際 MD5/state
   - 不可只說「請人工檢查」而不輸出目前混合狀態
4. `restore_from()` 應彙總並傳回復原失敗，不要讓 caller 忽略結果。
5. `.rpz_patch_last_backup` 寫入或 rename 失敗不可靜默後仍回報 apply 完成。

### 3.5 必測矩陣

| 情境 | 最終允許狀態 |
|---|---|
| 正常 rollback | 全 orig，exit 0 |
| 第一檔失敗 | 全 new，exit 非零 |
| 第二檔失敗 | 全 new，exit 非零 |
| 第三檔失敗 | 全 new，exit 非零 |
| recovery 也失敗 | exit 非零，輸出每檔 MD5/state，不得宣告完成 |
| backup 缺檔或 MD5 錯誤 | 不做任何替換，保持全 new |

---

## 4. R2-03 — High：destructive LAB test 的 guard 與 target 不一致

### 4.1 位置

- `tests/lab/f5_manual_cleanup_test.sh:41-75`：顯示路徑、hostname、production marker guard
- `tests/lab/f5_manual_cleanup_test.sh:78-83`：guard 後立即執行、硬編碼 `S`/`D`
- `tests/lab/f5_manual_cleanup_test.sh:115-121`：只顯示 MD5、廣泛刪除 `raw/*.out`

### 4.2 問題

guard 使用：

```bash
DATA_DIR_CHK="${DATA_DIR:-/config/snmp/rpz_datagroups}"
${INSTALL_DIR:-/config/snmp/RPZ_Local_Processor}
```

但 guard 通過後真正操作的是：

```bash
S=/config/snmp/RPZ_Local_Processor/scripts
D=/config/snmp/rpz_datagroups
```

因此使用者若設定安全的測試 `DATA_DIR`/`INSTALL_DIR`：

- 顯示的是測試路徑。
- production marker 檢查的是測試路徑。
- 真正刪除與執行的卻仍是 `/config/snmp/...`。

其他未完成項目：

- 沒有互動式 exact-path 確認。
- `--i-know` 同時繞過 hostname 與 production marker。
- 腳本只印出「應為原版」MD5，沒有 assert 原版三支 MD5。
- 情境 A 使用 `rm -f $D/raw/*.out`，比文件宣告的 `dnsxdump_*.out` 更廣。
- 沒有驗證 handler inactive 或 processor 已停止。
- 測試結果沒有統一 assertion/非零退出政策。

### 4.3 必要修正

1. 先解析一次 `S`、`D`，guard、顯示、刪除與執行全部只能使用同一組變數。
2. 預設只允許明確 LAB hostname 加 LAB marker 雙重條件。
3. production marker 不得由單一通用旗標直接繞過；若保留 override，需更強的 exact phrase 或環境限制。
4. 執行前要求互動輸入完整 hostname 或 exact path 確認。
5. assert 三支腳本確實是此測試預期的 orig MD5；不符立即停止。
6. assert handler inactive 且 `pgrep` 無 processor。
7. 所有刪除 pattern 必須與文件宣告完全一致。
8. 任一測試 case 不符合預期時，整支腳本 exit 非零。

此檔未被放進 production package，這點已通過；但 CR-16 尚不能標記完成。

---

## 5. R2-04 — High：package integrity 驗證 fail-open

### 5.1 位置

- `install.sh:34-58`

### 5.2 問題

目前行為：

- 沒有 `VERSION`：warning，繼續。
- 有 `SHA256SUMS` 但沒有 `sha256sum`：warning，繼續。
- 沒有 `SHA256SUMS`：warning，繼續。

這使新增的完整性驗證變成 optional。

「舊 package 相容」不是充分理由：舊 package 內帶的是舊版 `install.sh`，不會執行這份新版 installer。若新版 installer 看不到 manifest，較合理的假設是 package 不完整、被修改或操作流程錯誤。

此外，`sha256sum -c` 只驗證 manifest 已列出的檔案，沒有阻止額外未列入的 `scripts/*.sh` 被 `cp` 進安裝目錄。

### 5.3 必要修正

1. 新版 installer 預設必須同時要求：
   - `VERSION`
   - `SHA256SUMS`
   - `sha256sum`
2. 任一缺少都 exit 非零，不建立目錄、不複製檔案。
3. 驗證 `VERSION` 是 installer 支援的精確版本。
4. 驗證所有即將安裝的檔案都有 manifest entry。
5. 拒絕 package 中額外、未列入 manifest 的 installable shell scripts。
6. 如需 legacy override，必須使用明確命名的高風險開關，預設關閉並在輸出中醒目標示。

### 5.4 必測情境

| 情境 | 預期 |
|---|---|
| 正常 v1.2.1 package | 驗證通過 |
| 修改任一 tracked file | 安裝前 exit 非零 |
| 刪除 `SHA256SUMS` | 安裝前 exit 非零 |
| 刪除 `VERSION` | 安裝前 exit 非零 |
| 模擬沒有 `sha256sum` | 安裝前 exit 非零 |
| 新增未列入 manifest 的 `scripts/extra.sh` | 安裝前 exit 非零 |
| `VERSION` 與 package name/預期不一致 | 安裝前 exit 非零 |

---

## 6. R2-05 — Medium：`REPS` 可繞過壓力測試

### 6.1 位置

- `patches/rpz_patch_sigpipe_v2.sh:411-418`
- `patches/rpz_patch_sigpipe_v2.sh:554-569`
- `tests/lab/f5_hotfix_test.sh:16-20`
- `tests/lab/f5_hotfix_test.sh:187-215`

### 6.2 獨立證據

執行：

```bash
REPS=0 bash patches/rpz_patch_sigpipe_v2.sh selftest
```

結果：

```text
S8 ... 300 檔 × 0 次
[PASS] ... 0/0 失敗
S9 ... 300 檔 × 0 次
[PASS] ... 0/0 失敗
PASS=16 FAIL=0
selftest rc=0
```

因此 selftest assertion 本身雖有效，但參數可讓核心壓力測試不執行。

### 6.3 必要修正

- `REPS` 必須是正整數。
- 建議限制為 `1..1000` 或更保守上限。
- `0`、負數、空白、`abc`、超大整數都必須在建立 fixture 前拒絕並 exit 非零。
- patch selftest 與 `f5_hotfix_test.sh` 使用同一政策。

---

## 7. R2-06 — Medium：package consistency gate 覆蓋不足

### 7.1 位置

- `tests/check_source_consistency.sh:110-149`

### 7.2 現況

目前 gate 會比較 package 內七支 `scripts/*.sh`，也會驗證內層 `SHA256SUMS`、確認有 `VERSION`、排除 `tests/` 與 `patches/`。

但沒有比較：

- `install.sh`
- `cleanup.sh`
- `config/zonelist.txt`
- `config/icall_setup_api.sh`
- `INSTALL_GUIDE.txt`
- `VERSION` 的精確預期值
- 外層 `.tar.gz.sha256`
- package 是否只有一個預期 root directory

因此 tracked installer/config 已改、package 尚未重建時，gate 仍可能回報綠燈。

### 7.3 第二輪獨立核對

目前 `rpz_local_processor_v1.2.1_20260821_143844.tar.gz` 額外逐檔核對結果：

```text
package_mismatches=0
```

一致的 12 個 inputs：

- `install.sh`
- `cleanup.sh`
- `INSTALL_GUIDE.txt`
- 2 個 package config files
- 7 支 `scripts/*.sh`

外層 `.sha256` 與內層 13 個 manifest entries 也都通過。因此目前 artifact 是一致的；問題是自動 gate 尚不足以防止未來回歸。

### 7.4 必要修正

1. 由 `package.sh` 的單一明確 manifest/list 定義 package inputs，測試引用同一份清單或精確鏡像。
2. 比較所有 copied inputs，而非只比較 `scripts/`。
3. assert `VERSION` 精確等於 package 預期版本。
4. 驗證外層 `.tar.gz.sha256`。
5. 驗證 package root 名稱與版本一致，且沒有額外 root entries。
6. 預先檢查 `md5sum`、`sha256sum`、`tar` 等工具；工具缺失不得因兩邊空字串而 false pass。

---

## 8. R2-07 — Medium：installer 路徑 override 沒有安全邊界

### 8.1 位置

- `install.sh:14-17`
- `install.sh:116-121`
- `install.sh:131-164`

### 8.2 問題

Phase 1A 為隔離安裝測試新增：

```bash
INSTALL_DIR="${INSTALL_DIR:-/config/snmp/RPZ_Local_Processor}"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
```

但沒有拒絕：

- `/`
- 相對路徑
- 過寬路徑，例如 `/config`
- `INSTALL_DIR == OUTPUT_DIR`
- target 與解壓縮 source 重疊
- traversal component

installer 通常由 F5 admin/root 執行；錯誤環境變數可能在非預期位置建立 `scripts/`、`config/`、`raw/`、`parsed/`、`final/`。

### 8.3 必要修正

1. 兩個路徑都必須是 canonical absolute path。
2. 拒絕 `/`、空白、相對路徑、含 traversal 的值。
3. 拒絕兩個 target 相同或互相包含。
4. 拒絕 target 與 `SCRIPT_DIR` 相同或互相包含。
5. 正式模式可考慮只允許 `/config/snmp/...`；隔離測試需明確 `RPZ_INSTALL_TEST_MODE=1` 才允許 `/var/tmp/...`。
6. 在任何 `mkdir`、`cp` 前完成全部驗證。

---

## 9. Phase 2 邊界與 handoff 用語修正

以下是已知 Phase 2 問題，不要求偷偷塞回 Phase 1A；但 handoff 與註解必須精確描述現況。

### 9.1 `prepare_final_datagroups()` 不是完整 transaction

`scripts/generate_datagroup.sh:60-91` 的第一階段會先確認所有 artifact 存在，因此已解決：

> 前段 zone 已 cp，後段 zone 才發現 missing artifact。

但 `scripts/generate_datagroup.sh:93-114` 仍逐一直接 `cp`/`touch` 正式 final files。

第二輪對第二個 `cp` 注入失敗，結果：

```text
generate rc=74
rpztw_changed=yes
phishtw_changed=no
```

因此正確說法是：

> resolve/preflight 階段發現 missing artifact 時不會部分發布。

不可寫成：

> 已不存在任何部分發布路徑。

完整 publish transaction、同目錄 temp + rename、run manifest 等仍屬 CR-10。

### 9.2 空 `rpzip` 使用 `touch` 會保留既有非空內容

目前：

```bash
if [[ -s "$ip_file" ]]; then
    cp ... final/rpzip.txt
else
    touch final/rpzip.txt
fi
```

若 `final/rpzip.txt` 先前非空，新 artifact 變成空，`touch` 只改 mtime，不會 truncate，舊內容會保留。

目前 RPZ fixture 與實際來源的 rpzip 都是空檔，因此不是此次 SIGPIPE hotfix 的 rollout blocker；但 T7 只從「舊 final 也為空」開始，沒有覆蓋 nonempty → empty transition。請將此項納入 CR-10/CR-13 測試與政策決定。

---

## 10. 已通過項目，修正時不得回歸

### 10.1 本機靜態與 package

| 驗證 | 結果 |
|---|---|
| `bash -n` 全部 shell scripts | PASS，20 支 |
| `tests/check_source_consistency.sh` | PASS=22，FAIL=0 |
| patch embedded 三支腳本 vs tracked source | byte-for-byte 一致 |
| patch expected new/orig MD5 | 全部相符 |
| v1.2.1 package 外層 SHA-256 | PASS |
| package 內層 `SHA256SUMS` | 13 entries 全部 PASS |
| package 12 個 copied inputs vs source | mismatch=0 |
| package 是否含 `tests/`/`patches/` | 否，PASS |
| `git diff --check` | PASS |

目前三支修正版 MD5：

```text
b8294149dc978305e19bcd83fcb650e6  scripts/utils.sh
cefa71b6623632dd51c60a51cdf72196  scripts/parse_rpz.sh
91621717b6b11b11142333970693eb71  scripts/generate_datagroup.sh
```

目前 patch MD5：

```text
45bac9de5ed19460330cbbb807a6fb82  patches/rpz_patch_sigpipe_v2.sh
```

### 10.2 隔離 lifecycle

以 v1.2 orig 三支腳本起始：

1. apply：成功，三支成為 new。
2. selftest `REPS=3`：PASS=16，FAIL=0。
3. rollback：成功，三支回到精確 orig MD5。

所以正常路徑可用；R2-02 是 failure path 缺陷。

### 10.3 LAB 獨立驗證

LAB：`10.8.34.223`，BIG-IP 17.1.3.1。

LAB installed 三支 MD5 與 tracked source 相同。

`f5_hotfix_test.sh fixed 10`：

```text
PASS=17
FAIL=0
```

patch selftest `REPS=10`：

```text
PASS=16
FAIL=0
selftest_rc=0
residual_rpzst_dirs=0
```

審核期間 LAB 測試全程使用隔離 `/var/tmp` fixture，沒有呼叫 tmsh 更新 DataGroup。驗證後：

```text
rpzhf_dirs=0
rpztw revision=8
rpztw size=2243064
```

---

## 11. 建議修正順序

### Step 1 — 先封住 destructive scope

1. 修 R2-01 cleanup traversal/canonical scope。
2. 修 R2-03 LAB destructive test guard/target mismatch。
3. 在完成前，不要執行實際 destructive test；先用 `/tmp` fixture 驗證 guard。

### Step 2 — 完成 rollback failure transaction

1. 修 R2-02。
2. 補第一、第二、第三檔 failure injection。
3. assert failure 後只能全 new，成功後只能全 orig。

### Step 3 — package/install fail-closed

1. 修 R2-04 manifest/tool/extra-file policy。
2. 修 R2-07 路徑限制。
3. 修 R2-06 package gate。
4. 重建 package 並更新 hash/manifest。

### Step 4 — 測試參數與文件

1. 修 R2-05。
2. 更新 `process.md`、`REVIEW_HANDOFF_PHASE1A.md`、`dist/DO_NOT_DEPLOY.md`。
3. 將「沒有部分發布」限縮為 missing-artifact preflight 的正確語意。

### Step 5 — 第三輪交接

提供新的 handoff，至少包含：

- 每個 R2 finding 的 code location 與修正摘要。
- 每個反向測試的命令、exit code、最終狀態。
- 新 patch MD5。
- 三支 tracked source MD5。
- 新 package 名稱、外層 SHA-256、內層 manifest 結果。
- LAB 是否有任何 state change 與復原結果。

---

## 12. 第三輪驗收矩陣

| ID | 驗收內容 | 必要結果 |
|---|---|---|
| A1 | 合法 zonelist cleanup-dry | 僅列出 raw/parsed 精確 scope |
| A2 | `../final/evil` | 在列舉前拒絕，非零，final 不變 |
| A3 | `../../outside`、glob、option-like zone | 全部拒絕 |
| A4 | duplicate zone | 去重或拒絕，計數一致 |
| B1 | 正常 apply | 全 new，exit 0 |
| B2 | apply 每個 replacement point 故障 | 回到全 orig，exit 非零 |
| B3 | 正常 rollback | 全 orig，exit 0 |
| B4 | rollback 每個 replacement point 故障 | 回到全 new，exit 非零 |
| C1 | selftest default REPS | PASS/FAIL assertions 正常 |
| C2 | `REPS=0/-1/abc` | fixture 前拒絕，exit 非零 |
| D1 | package 正常 manifest | install 可繼續 |
| D2 | manifest/VERSION/tool 缺失 | install 在任何 mkdir/cp 前拒絕 |
| D3 | 額外未列入 manifest script | install 拒絕 |
| D4 | unsafe `INSTALL_DIR`/`OUTPUT_DIR` | install 在任何 mkdir/cp 前拒絕 |
| E1 | package 全 inputs 比對 | 全部與 source 一致 |
| E2 | 外層與內層 checksum | 全部通過 |
| E3 | package contents | 不含 tests/patches，root/version 正確 |
| F1 | LAB fixed behavior matrix | FAIL=0 |
| F2 | LAB patch selftest | FAIL=0、exit 0、無殘留 temp |

---

## 13. 最終判定

### SIGPIPE root cause 與 helper

**通過。** 核心技術方向正確，LAB 與隔離測試均支持。

### CR-01 missing artifact

**通過限定情境。** missing artifact 在 publish 前 hard fail，且該情境不部分發布。

### CR-02 selftest assertion

**核心通過，參數驗證待補。** 實際故障能使 assertion 非零，但 `REPS=0` 仍可繞過壓力迴圈。

### CR-03 source/package consistency

**目前 artifact 通過，持續性 gate 待補。** 當前 package 已獨立確認一致，但測試未涵蓋全部 package inputs。

### CR-04 transaction

**不通過。** 正常 rollback 可用，但 rollback failure 會留下混合版本。

### CR-05 cleanup

**不通過，Blocker。** configured zone 可使 cleanup 越出 parsed scope。

### CR-16 destructive LAB test

**不通過。** guard 與真正 target 不一致，尚不符合 destructive test 防呆要求。

### Production rollout

**NO-GO。** R2-01 至 R2-07 修正、第三輪驗收完成，且取得四台 production 的版本與 MD5 前，不得宣告 v1.2.1/patch v2 已可無條件上線。

