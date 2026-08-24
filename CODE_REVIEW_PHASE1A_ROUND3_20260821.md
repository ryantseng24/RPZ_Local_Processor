# RPZ Local Processor Phase 1A 第三輪獨立審核

> **狀態：部署判定已被修訂版取代。** 本文件保留第三輪反向測試與技術證據，
> 但其中的整體 NO-GO、嚴重度與修正優先順序，不再是目前的執行依據。
> Claude Code 應以 [CODE_REVIEW_PHASE1A_ROUND3_REV2_20260821.md](CODE_REVIEW_PHASE1A_ROUND3_REV2_20260821.md)
> 為準。修訂原因是重新依本案實際目標與環境校準：受控管理員在 F5 BIG-IP 上，
> 正確套用既有機器的 v3 shell patch，永久排除 4096 bytes / SIGPIPE 問題。

**文件日期**：2026-08-21

**審核角色**：獨立 reviewer

**交付對象**：Claude Code

**審核依據**：`REVIEW_HANDOFF_PHASE1A.md`、目前 working tree、v3 patch、v1.2.1 package、本機反向測試與 BIG-IP LAB 隔離測試

**範圍排除**：不審核、不要求修改 iRule/TCL

**本輪未做事項**：未修改任何 production source、未 commit、未 push

---

## 1. 最終判定

### 1.1 結論：NO-GO

目前仍不可把 Phase 1A 或 `rpz_local_processor_v1.2.1_20260821_152107.tar.gz`
宣告為無條件可部署。

本輪確認核心 SIGPIPE 修正是有效的：

- tracked source、patch embedded source 與目前 package 內容一致。
- `find_newest_file()` 的三個 call site 沒有回歸。
- missing artifact 仍是 hard failure。
- v3 LAB selftest：`PASS=16 FAIL=0`、exit 0。
- rollback 前建立並驗證完整 recovery staging 的方向正確。
- embedded source 被改壞時，rollback 會在任何 target 被替換前拒絕執行。

但 installer 的兩個 High finding 會讓「路徑安全邊界」與「manifest fail-closed」
被 symlink 繞過；這兩項與交接文件及 `dist/DO_NOT_DEPLOY.md` 的完成宣告直接矛盾。
另外 destructive LAB test 的 `DATA_DIR`/`OUTPUT_DIR` contract mismatch 證明 R2-03
尚未真正結案，列為第三個 High finding。

### 1.2 分項判定

| 項目 | 判定 | 說明 |
|---|---|---|
| SIGPIPE 核心修正 | PASS | tracked / embedded / package 一致，LAB selftest 通過 |
| v3 recovery staging | PASS with note | altered embedded payload 會在變更前失敗；另有截斷 artifact 與錯誤訊息問題 |
| v3 cleanup | NO-GO | 子目錄為 symlink 時拒絕是安全的，但錯誤被吞掉並回報成功 |
| v1.2.1 installer path boundary | NO-GO | lexical path 可被 symlink 繞過，canonical target 可相同或越出 allowed root |
| v1.2.1 manifest/inventory | NO-GO | 未列入 manifest 的 symlink `*.sh` 會被安裝 |
| package/release gate | NO-GO | 未覆蓋 symlink、PAX xattr；另重新引入 early-close pipeline |
| destructive LAB test | NO-GO | `DATA_DIR` guard 與子腳本實際使用的 `OUTPUT_DIR` 不同；另有 final 誤宣告與無效 assertion |
| 既有 Phase 2 findings | OPEN | CR-06～CR-15 與 DOC-06 沒有因本輪而結案 |

---

## 2. Finding 摘要

| 編號 | 嚴重度 | 結論 |
|---|---|---|
| R3-01 | High | `install.sh` 只比字串路徑；symlink 可繞過 allowed root、source overlap 與 target overlap |
| R3-02 | High | manifest inventory 忽略 symlink；未列入 manifest 的 `extra.sh` 可通過驗證並被安裝 |
| R3-03 | Medium | `raw/` 或 `parsed/` 為 symlink 時 cleanup 拒絕候選，卻 exit 0 並宣告完成 |
| R3-04 | Medium | patch embedded corruption 有防護，但合法截斷可無輸出、exit 0；patch 缺外部 SHA-256 gate |
| R3-05 | Medium | package/gate 又使用 early-closing pipeline、tar 仍帶 macOS provenance xattr，handoff 的 gate MD5 也已失真 |
| R3-06 | Medium | package 內的 `INSTALL_GUIDE.txt` 仍是 v1.2，指令無法匹配 v1.2.1 artifact，handler 名稱也錯 |
| R3-07 | High | destructive LAB test guard 使用 `DATA_DIR`，子腳本卻使用未傳入的 `OUTPUT_DIR`；safe override 後仍可能操作預設 `/config` |
| R3-08 | Low | recovery 最終已是全 new 時，仍可能誤報「系統處於混合狀態」 |

---

## 3. R3-01 — High：installer 的 symlink 可繞過所有 lexical path boundary

### 3.1 位置

- `install.sh:58-80`：`validate_abs_path()`、`is_within()`
- `install.sh:82-120`：target/source overlap 與 allowed-root 判斷
- `install.sh:238-275`：通過檢查後的 `mkdir`、`cp`

### 3.2 問題機制

`SCRIPT_DIR` 已用 `pwd -P` 轉成實體路徑，但 `INSTALL_DIR` 與 `OUTPUT_DIR` 沒有
canonicalize。`is_within()` 只比較輸入字串：

```bash
is_within() {
    case "$1" in
        "$2"|"$2"/*) return 0 ;;
    esac
    return 1
}
```

所以兩個看起來不同且都位於 `/var/tmp` 的字串，可以解析到完全相同的實體目錄；
同理，位於 `/config/snmp` 或 `/var/tmp` 下的 symlink parent 可以指到 allowed root 外、
production target 或 package source。

`validate_abs_path()` 排除 `.`、`..` 與重複斜線，不能解決 symlink alias。

### 3.3 LAB 獨立重現

測試全程在一次性的 `/var/tmp/rpzinst-review.*`，沒有讀寫 `/config`：

```bash
REAL=/var/tmp/<fixture>/real_target
LINK=/var/tmp/<fixture>/install_link
mkdir -p "$REAL"
ln -s "$REAL" "$LINK"

RPZ_INSTALL_TEST_MODE=1 \
INSTALL_DIR="$LINK" \
OUTPUT_DIR="$REAL" \
bash <package>/install.sh
```

實際結果：

```text
installer_rc=0
install_physical=/shared/tmp/<fixture>/real_target
output_physical=/shared/tmp/<fixture>/real_target
✓ 兩個路徑不相同也不互相包含
安裝完成！
co_located_dirs=.soa_cache config scripts parsed raw final
```

也就是 installer 明確宣告兩路徑不重疊，但程式與資料實際安裝在同一目錄。

### 3.4 影響

1. `INSTALL_DIR` 與 `OUTPUT_DIR` 可實際相同或互相包含。
2. test mode 的 `/var/tmp/.../link` 可指到 `/config/...`，繞過「測試不碰 production」。
3. production mode 的 `/config/snmp/.../link` 可指到 allowed root 外。
4. target 可經 symlink 與 package source 重疊，安裝過程可能覆寫或污染來源。
5. installer 通常以 root/admin 執行，因此這不是單純顯示問題。

### 3.5 必要修正

1. 在任何 `mkdir`/`cp` 前，對三個路徑取得 canonical/planned canonical path：
   - `SCRIPT_DIR`；
   - `INSTALL_DIR`；
   - `OUTPUT_DIR`。
2. LAB 已確認 BIG-IP 17.1.3.1 的 GNU coreutils 8.22 支援：

   ```bash
   readlink -m -- "$path"
   ```

   它可以解析既有 symlink，並處理尚未建立的尾端 component。
3. allowed-root、source overlap、target overlap 必須全部用 canonical path 比較。
4. 建立目錄後再 canonicalize 一次，確認沒有在 preflight 與 mutation 之間改變。
5. 建議直接拒絕 target path 中既有的 symlink component；如果決定允許，就必須把
   canonical result 當成唯一 target 並清楚印出。
6. `is_within()` 可以保留，但只能接收已 canonicalize 的值。

### 3.6 必測矩陣

| 情境 | 預期 |
|---|---|
| 兩個普通且不重疊的 target | 成功 |
| `INSTALL_DIR` symlink → `OUTPUT_DIR` | 任何 mkdir/cp 前拒絕 |
| `OUTPUT_DIR` symlink → `INSTALL_DIR` | 任何 mkdir/cp 前拒絕 |
| target 的中間 component 是 symlink | 依政策拒絕，或 canonical 後重新做全部 boundary check |
| allowed-root 內 symlink → allowed-root 外 | 拒絕 |
| target symlink → package source | 拒絕 |
| 建立後 canonical path 與 preflight 不同 | 拒絕，不複製任何檔案 |

---

## 4. R3-02 — High：manifest 未涵蓋 symlink，額外腳本可被安裝

### 4.1 位置

- `install.sh:157-179`：SHA256 驗證與 manifest coverage
- `install.sh:168-174`：只用 `find ... -type f`
- `install.sh:253-275`：用 `scripts/*.sh` 與 config 固定/通配複製
- `tests/check_source_consistency.sh:180-188`：package extra-file gate 也只看 `-type f`

### 4.2 問題機制

目前 coverage 只列舉 regular file：

```bash
find "$SCRIPT_DIR" -type f \( -name '*.sh' -o -name 'zonelist.txt' \)
```

`find` 預設不 follow symlink，因此未列入 `SHA256SUMS` 的 `scripts/extra.sh` symlink
不會被檢查。後續：

```bash
cp -f "${SCRIPT_DIR}/scripts"/*.sh "$INSTALL_DIR/scripts/"
```

卻會展開這個 symlink，並由 `cp` dereference 後安裝成 regular executable file。

這比交接文件第 6.3 點所說的「未來 `.conf` 要同步」更嚴重：它現在就能繞過。

### 4.3 LAB 獨立重現

在已通過內層 SHA256 的 package fixture 中加入：

```bash
ln -s utils.sh <package>/scripts/extra.sh
```

不修改 `SHA256SUMS`，執行 installer，實際結果：

```text
installer_rc=0
extra_source_type=symlink
✓ SHA256SUMS 驗證通過（13 個檔案）
✓ 所有可安裝檔案都在 manifest 內，沒有額外檔案
安裝完成！
extra_installed=yes
extra_content=dereferenced_utils
```

因此目前的「所有可安裝檔案」訊息不成立。

### 4.4 必要修正

1. package root 內只允許預期目錄與 regular file；明確拒絕：
   - symlink；
   - FIFO/socket/device；
   - 非預期 hard-link/layout。
2. 不要用副檔名推測「可安裝檔案」。除 `SHA256SUMS` 本身外，package 內每個
   regular file 都必須在 manifest 中，而且 manifest 不得多列不存在的檔案。
3. manifest path 要做 exact line/path 比對；目前 `grep -qF "  $rel"` 是 prefix/substring
   比對，不是完整欄位比對。
4. installer 的 copy source 應使用明確 inventory，不要用 `scripts/*.sh` 擴大到未列入
   release contract 的檔案。
5. `package.sh`、`install.sh`、consistency gate 必須共用同一份 inventory contract，
   或由 build 產生一份被 checksum 保護的 inventory。
6. 外層 tar 的 SHA-256 必須在解壓縮前驗證；inner manifest 無法防止 tar 本身的
   path/symlink layout 問題。

### 4.5 必測矩陣

| package 變異 | 預期 |
|---|---|
| 正常 package | 成功 |
| 額外 regular `scripts/extra.sh` | 拒絕 |
| 額外 symlink `scripts/extra.sh -> utils.sh` | 拒絕 |
| `scripts/` 本身是 symlink | 拒絕 |
| 額外 `.conf`、無副檔名檔案 | 拒絕，除非已加入正式 inventory 與 manifest |
| FIFO/socket/device | 拒絕且不可 hang |
| manifest 有 prefix collision，例如 `foo.sh` vs `foo.sh.extra` | 必須 exact match，前者不可被後者冒充 |

---

## 5. R3-03 — Medium：cleanup 對 symlink 子目錄 fail-safe，但 false-success

### 5.1 位置

- `patches/rpz_patch_sigpipe_v3.sh:733-746`：`validate_data_dir()`
- `patches/rpz_patch_sigpipe_v3.sh:751-757`：`safe_victim()`
- `patches/rpz_patch_sigpipe_v3.sh:797-812`：`cleanup_victims()`
- `patches/rpz_patch_sigpipe_v3.sh:844-904`：planning、delete 與最終 exit status

### 5.2 實際行為

本輪分三種 symlink 測試：

| 情境 | 結果 |
|---|---|
| `DATA_DIR` 本身是 symlink | 正常；`DATA_DIR_CANON` 與 victim parent 一致，dry-run 正確列出 4 個 |
| `parsed/` 是 symlink | 候選全部被 `safe_victim()` 拒絕，沒有越界刪除；但 dry/real 都 exit 0 |
| matched file 是 symlink → 外部 regular file | cleanup 只刪 symlink 本身，外部 target checksum 不變 |

`DATA_DIR` symlink 的結果符合設計。真正問題是子目錄 symlink 的 status propagation。

### 5.3 獨立重現結果

fixture：`DATA_DIR/parsed -> DATA_DIR/parsed_store`，每個 parsed pattern 兩個檔，
`KEEP=1`：

```text
dry_rc=0
real_rc=0
parsed_remaining=6
raw_remaining=1
final_unchanged=yes

[FAIL] 拒絕越界的檔案: .../parsed/rpztw_new.txt
[FAIL] 拒絕越界的檔案: .../parsed/rpztw_old.txt
...
預計刪除 1 個，實際刪除 1 個，錯誤 0 個
[ OK ] cleanup 完成
```

`safe_victim()` 的 canonical parent 是 `.../parsed_store`，expected 卻是 lexical
`$DATA_DIR_CANON/parsed`，所以拒絕是安全的。但 `cleanup_victims()` 只把訊息寫到
stderr 並 `continue`，caller 只計算 stdout 行數，錯誤沒有進入 `errors`。

這會讓真正的磁碟清理未完成，卻讓自動化或操作人員看到 exit 0。

### 5.4 必要修正

1. 明確決定 policy，建議：
   - `raw/`、`parsed/`、`final/` 必須是 DATA_DIR 下的真實目錄；
   - 任一是 symlink 就在列舉前整體拒絕，exit 非零。
2. 如果業務上必須允許 subdir symlink，則要分別 canonicalize allowed subdir，並確認
   它仍位於核准的 data boundary；不可只把 lexical `$DATA_DIR_CANON/$sub` 當 expected。
3. unsafe victim、`ls`/sort 失敗、enumeration 失敗都必須傳回 caller，不能只印 stderr。
4. planning 階段只要有任何錯誤，建議完全不要開始 deletion，避免 partial cleanup。
5. 不要讓 command substitution + pipeline 把 function 的非零 status 吃掉；可先建立
   明確的 plan file/array，驗證完整後再執行。

### 5.5 必測矩陣

- `DATA_DIR` 是 symlink，正常子目錄。
- `raw/` symlink 到 DATA_DIR 內另一目錄。
- `parsed/` symlink 到 DATA_DIR 內另一目錄。
- `raw/`、`parsed/` symlink 到 DATA_DIR 外。
- matched file 是 symlink 到外部檔案；只能刪 link，不得改 target。
- 任一 unsafe candidate 必須讓 dry-run 與 real cleanup 都 exit 非零。
- real cleanup 不可同時印 `[FAIL]` 與 `[ OK ] cleanup 完成`。

---

## 6. R3-04 — Medium：patch payload corruption 有擋，但合法截斷會 silent success

### 6.1 位置

- `patches/rpz_patch_sigpipe_v3.sh:449-465`：rollback recovery staging preflight
- `patches/rpz_patch_sigpipe_v3.sh:909-923`：patch 的 `main()`
- `patches/rpz_patch_sigpipe_v3.sh:1536`：唯一的 `main "$@"` 呼叫位於檔尾
- `patches/README.md`、`process.md:670-692`：部署流程沒有 patch sidecar SHA-256 gate

### 6.2 已確認正確的部分

把 embedded `utils.sh` 改一個字元，但保留有效 shell syntax 後執行 rollback：

```text
CORRUPT_EMBED_ROLLBACK rc=1
[FAIL] recovery staging/utils.sh md5 不符，拒絕開始還原
installed state = new / new / new
```

這證明 recovery staging 確實在第一個 target replacement 前完成，embedded payload
意外損毀不會先留下 mixed state。`recover_to_new()` 的資料來源設計本身通過。

### 6.3 尚未被處理的情境

把 patch 合法截斷在 `main()` 定義之後、embedded functions 與最後一行
`main "$@"` 之前：

```text
truncated_syntax=ok
TRUNCATED_BEFORE_EMBED rc=0
output_bytes=0
installed state = new / new / new
```

對 `check`、`apply` 或 `rollback` 而言，這是一個「什麼都沒做但 exit 0」的 artifact。
腳本內部的 MD5_NEW 無法保護根本沒有被呼叫的 main。

### 6.4 必要修正

1. 對 patch 產生獨立 `.sha256` sidecar，納入 release artifact 與 consistency gate。
2. `process.md` 的正式步驟必須在第一次執行 patch 前要求：

   ```bash
   sha256sum -c rpz_patch_sigpipe_v3.sh.sha256
   ```

3. 上傳前後都比對 SHA-256；不要只在 handoff 表格提供 MD5。
4. 可再加 trailer magic/預期 byte count 作 accidental truncation 的快速診斷，但不能取代
   外部 checksum。
5. altered embedded payload 測試與 syntactically-valid truncation 測試都要保留。

目前未修改版本的 patch SHA-256 是：

```text
6b019bc9454d3ac0ecf97582302b5c70556b0976fd33621c5563bdd06092e8fb
```

Claude Code 修檔後此值必然要重新產生，不能沿用。

---

## 7. R3-05 — Medium：package/release gate 重現 early-close pipeline，漏掉 PAX xattr，且 hash 紀錄失真

### 7.1 位置

- `package.sh:108-113`：`tar tzf ... | grep -qE ...`
- `package.sh:138`：`tar tzf ... | head -20`
- `tests/check_source_consistency.sh:131-132`、`:162`、`:216`：`ls/sed/find | head/grep -q`

### 7.2 early-close + pipefail

`package.sh` 使用 `set -euo pipefail`，卻重新加入會提早關閉 pipe 的 consumer：

```bash
if tar tzf "$PACKAGE" | grep -qE '...'; then ... fi
tar tzf "$PACKAGE" | head -20
```

在 LAB 的 GNU tar 環境，以 3001-entry、listing 81005 bytes 的隔離 tar 驗證：

```text
head_pipeline_rc=141
grep_q_pipeline_rc=141
```

影響分兩種：

1. `tar | head` 可讓 build 在 artifact 與 `.sha256` 已建立後 exit 141。
2. `if tar | grep -q` 遇到 match 時，`grep -q` 成功但 producer 141；在 pipefail 下整個
   condition 為 false，反而可能漏報本來要拒絕的 metadata entry。

目前 package 只有 17 個 tar entries，所以這一版尚未觸發；但 R3-02 要求 inventory
成長後，這會成為同類回歸。

### 7.3 macOS provenance xattr

現行 package 內仍可找到：

```text
SCHILY.xattr.com.apple.provenance
LIBARCHIVE.xattr.com.apple.provenance
```

在 BIG-IP GNU tar 解開時，每個相關 entry 都產生：

```text
tar: Ignoring unknown extended header keyword `LIBARCHIVE.xattr.com.apple.provenance'
```

這不會讓內容 checksum 失敗，但證明：

- `COPYFILE_DISABLE=1` 沒有移除 PAX xattr；
- consistency gate 所說的「package 無作業系統中繼資料」只檢查檔名，結論過度宣告。

### 7.4 Handoff checksum mismatch

交接文件還有一項可重現的 checksum mismatch：

```text
REVIEW_HANDOFF_PHASE1A.md / process.md 記錄：
5c6fdf26c7314de9fd3432bd97ca2d9c  tests/check_source_consistency.sh

目前 working tree 實際：
726c73c27c25c319c312a05c4d17fd36  tests/check_source_consistency.sh
```

檔案 mtime 早於 handoff，但 handoff 沒更新成實際值。其餘本輪抽查的核心 MD5 與
handoff 相符。這表示交付 hash 表不能直接當 release manifest 使用。

### 7.5 必要修正

1. 對 tar listing 只執行一次並完整讀到 EOF，再由檔案/變數做所有檢查。
2. 顯示前 20 行可用會持續讀到 EOF 的方式，不要用 early-closing `head`。
3. 不要在 pipefail 下用 `producer | grep -q` 作安全判斷。
4. macOS bsdtar 建包時加入適用的 `--no-xattrs`，並實測 BIG-IP 解包零 warning。
5. metadata gate 同時檢查 AppleDouble、`.DS_Store`、`.AppleDouble` 與 PAX xattr。
6. consistency test 增加 large-listing regression，至少在 GNU tar 環境執行一次。
7. 所有 source/test/artifact hash 在最後一次修改後重新計算；handoff 不得沿用舊值。

---

## 8. R3-06 — Medium：部署包內的 INSTALL_GUIDE 仍是舊版且指令無法使用

### 8.1 位置

- `INSTALL_GUIDE.txt:5-6`：仍標版本 1.2 / 2025-12-02
- `INSTALL_GUIDE.txt:25,44-45`：使用 `rpz_local_processor_v1.2_*`
- `INSTALL_GUIDE.txt:48-58`：沒有 VERSION/SHA256 完整性步驟
- `INSTALL_GUIDE.txt:109`：查詢不存在的 `rpz_update_handler`
- `package.sh:41`：把這份舊 guide 放進 v1.2.1 package
- `dist/DO_NOT_DEPLOY.md:48`：使用未定義的 `${PB}`

### 8.2 實際問題

實際 artifact：

```text
rpz_local_processor_v1.2.1_20260821_152107.tar.gz
```

guide 的 pattern：

```text
rpz_local_processor_v1.2_*.tar.gz
```

因為 `1.2` 後面要求立刻是 `_`，它不會匹配 `1.2.1_...`。本機 pattern test：

```text
no_match
```

即使使用者自行改檔名，guide 也沒有要求先驗 outer SHA-256、再驗 inner
`SHA256SUMS`，而 handler 的正確名稱是 `rpz_processor_handler`。

### 8.3 必要修正

1. 把 packaged guide 更新為 v1.2.1，命令直接使用明確 artifact 名稱或安全變數。
2. 加入「解壓縮前 outer SHA-256、解壓縮後 inner SHA256SUMS」兩層驗證。
3. handler 名稱全面統一為 `rpz_processor_handler`。
4. 修正 `dist/DO_NOT_DEPLOY.md` 的未定義 `${PB}`。
5. consistency gate 應檢查 packaged guide：
   - 版本與 `package.sh VERSION` 相同；
   - 不含舊 artifact pattern；
   - 不含舊 handler name；
   - 有 outer/inner checksum 指令。
6. `README.md` 與 `docs/TRAINING_GUIDE.md` 的全面更新仍屬既有 DOC-06，但至少 package
   內直接交付給客戶的 guide 必須在本 release 修正。

---

## 9. R3-07 — High：destructive LAB test 的 guard/target 仍不一致，且 final assertion 無效

### 9.1 位置

- `tests/lab/f5_manual_cleanup_test.sh:10-15`：宣告「不會碰 final/」
- `tests/lab/f5_manual_cleanup_test.sh:52-54,149-150`：guard/fixture 使用 `DATA_DIR`/`D`
- `tests/lab/f5_manual_cleanup_test.sh:175-190`：B～D 呼叫 parse/generate 時未傳 `OUTPUT_DIR`
- `tests/lab/f5_manual_cleanup_test.sh:194-202`：A 呼叫 `main.sh --force` 時也未傳 `OUTPUT_DIR`
- `scripts/main.sh:30`、`parse_rpz.sh:21`、`generate_datagroup.sh:19`：實際只認 `OUTPUT_DIR`
- `tests/lab/f5_manual_cleanup_test.sh:220-227`：final checksum 的兩個分支都呼叫 `ok`

### 9.2 問題

hostname、confirm、handler inactive 與 orig MD5 這些第二輪要求已改善，但 R2-03 的
核心 guard/target mismatch 仍存在，只是藏在被呼叫腳本的環境變數 contract：

```bash
# test 自己的 guard / 顯示 / fill / delete
DATA_DIR="${DATA_DIR:-/config/snmp/rpz_datagroups}"
D="$DATA_DIR"

# child call 沒有 OUTPUT_DIR="$D"
bash "$S/parse_rpz.sh"
bash "$S/generate_datagroup.sh"
bash "$S/main.sh" --force
```

三支 child script 都不讀 `DATA_DIR`，只讀：

```bash
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"
```

因此若 reviewer/operator 設定一個安全的 `DATA_DIR=/var/tmp/...`：

1. 顯示、production marker、fill/delete 都針對安全 fixture。
2. child `main/parse/generate` 卻仍回到預設 `/config/snmp/rpz_datagroups`。
3. 這正是第二輪要求消除的「guard 一個 path、實際執行另一個 path」。

除此之外還有獨立的 final/state 問題：

1. 情境 A 的 `main.sh --force` 會合法重寫 `final/` 並更新 DataGroup。
2. 情境 B～D 每一輪 `generate_datagroup.sh` 也會直接寫 effective OUTPUT_DIR 的 `final/`。
3. `fill_parsed()` 建立的是空 fixture；generate 成功時可能把 final 變成空檔。
4. 腳本結束時不 restore raw/parsed/final，也沒有最後一次有效 full run 保證 LAB 回到健康狀態。
5. 最後 checksum 判斷不論相同或不同都 `ok`：

   ```bash
   if [ "$FSIG_BEFORE" = "$FSIG_AFTER" ]; then
       ok ...
   else
       ok ...
   fi
   ```

   這不是 assertion，也不能證明變更只來自情境 A。

### 9.3 必要修正

1. 只保留一個有效資料路徑變數，建議直接改用 child contract 的 `OUTPUT_DIR`；guard、
   顯示、fill/delete 與所有 child invocation 都必須使用/傳入同一個值。
2. 每個 child call 必須明確傳入，例如：

   ```bash
   OUTPUT_DIR="$D" ZONELIST_FILE="$INSTALL_DIR/config/zonelist.txt" bash "$S/parse_rpz.sh"
   ```

   `main.sh` 也必須收到 `OUTPUT_DIR="$D"`。
3. 增加反向測試：指定 `/var/tmp` fixture，並在預設 `/config/snmp/rpz_datagroups`
   放 sentinel；完整測試後 default path 的 mtime/checksum 必須完全不變。
4. 文件應改成「不直接 delete final；測試流程會更新 final/DataGroup」，不能說不碰。
5. 優先把 B～D 改成真正隔離的 OUTPUT_DIR；不要用 LAB 的 live data path 做壓力 fixture。
6. 如果 A 必須做真實 full run，應在測試結尾再跑一次有效資料的 full run，並 assert：
   - final 三檔存在；
   - expected zone 筆數合理；
   - DataGroup update 成功；
   - fixture 已清除。
7. 任一 checksum/data-state 不符合精確預期就必須 `bad`/exit 非零，不可兩分支都 PASS。
8. cleanup/restore 應放進 trap；若無法自動 restore，就把每個永久 state change 清楚列為
   測試前置與人工復原步驟。

---

## 10. R3-08 — Low：recovery 已全 new 時仍可能誤報 mixed state

### 10.1 位置

- `patches/rpz_patch_sigpipe_v3.sh:395-409`：`recover_to_new()`
- `patches/rpz_patch_sigpipe_v3.sh:480-488`：caller 的訊息

### 10.2 問題機制

第二輪用 `chattr +i` 鎖住 rollback target。當 rollback replacement 失敗時，該檔案
通常仍是正確的 new 版本。`recover_to_new()` 還是再呼叫一次 `install_file()`；immutable
target 讓這次 copy 失敗，`rc` 被設為 1。即使最後 `detect_state` 是 `new`，`rc` 不會清除，
caller 會印：

```text
recovery 也失敗，系統處於混合狀態
```

後面的 per-file report 又可能顯示 `new/new/new`，兩段訊息互相矛盾。

### 10.3 建議修正

1. 每檔 recovery 前若 MD5 已是 expected new，可直接記錄「已是 new」並跳過替換。
2. `install_file` 失敗後再次驗 target MD5；若 target 本來就正確，不應把整體判成 mixed。
3. 最終訊息必須由 `detect_state` 決定：
   - `new`：recovery 最終成功，rollback 本身仍 exit 非零；
   - 其他：才說 mixed/unknown 並要求人工處理。

---

## 11. 交接文件五個疑問的逐項答案

| 交接疑問 | 第三輪答案 |
|---|---|
| 1. `safe_victim()` 與 symlink | `DATA_DIR` symlink 正常；subdir symlink 不會越界刪除，但會 false-success，成立為 R3-03 |
| 2. zone 白名單是否誤擋 | 對一般 DNS protocol 而言確實較窄；但對 BIG-IP DNS Express/RPZ 支援的 zone naming 不會誤擋，反而還稍微過寬。不要為了 RFC 2181 任意放寬 |
| 3. manifest 只掃 `*.sh` / zonelist | 疑慮成立且比預期嚴重；symlink `*.sh` 現在就可繞過，見 R3-02 |
| 4. embedded recovery 遇 patch 損毀 | embedded byte alteration 會安全拒絕；合法截斷可 silent exit 0，需外部 SHA-256，見 R3-04 |
| 5. `is_within()` 與 symlink | 明確成立；LAB 已重現兩個 lexical target 對應同一 canonical target，見 R3-01 |

---

## 12. Zone 字元查證結論

### 12.1 不建議放寬目前 cleanup 白名單

DNS protocol 本身允許的 label 比 hostname 廣。RFC 2181 §11 說明 DNS label 除長度外
可包含任意 octet；但同一節也明確允許使用 DNS 的 application 對自己的 input 加上
適合該情境的限制。

BIG-IP 官方「Creating an RPZ DNS Express zone」則要求 zone name：

- 開頭與結尾是字母；
- 只含字母、數字、句點與連字號；
- zone name 不分大小寫。

因此 `A-Za-z0-9._-` 不會誤擋 BIG-IP 文件所支援的字元。國際化域名的 A-label
使用 `xn--` ASCII/Punycode 形式，也落在這個集合內；raw Unicode U-label 不應直接成為
目前 shell filename/tmsh object contract。

反而目前 validator 比 F5 規則寬，仍接受：

- `_`；
- trailing dot；
- 結尾 `-`；
- 數字開頭/結尾；
- 大小寫視為不同的 duplicate。

本 validator 目前只保護 patch cleanup 的 path/glob scope，因此這些不構成本輪 path
traversal blocker。但它不能被描述成完整 RPZ semantic validator。既有 CR-15 仍需：

1. 集中 zone validation，讓 check/parse/generate/update/cleanup 共用。
2. 明確採 BIG-IP 支援 contract，不採「所有 DNS wire-format label」。
3. case-insensitive duplicate、label/name length、trailing dot 與 nested-zone policy 一併處理。

### 12.2 主要來源

- [F5 BIG-IP：Configuring DNS Response Policy Zones](https://techdocs.f5.com/en-us/bigip-14-1-0/big-ip-dns-services-implementations/configuring-dns-response-policy-zones.html)
- [RFC 2181 §11：DNS name syntax](https://www.rfc-editor.org/rfc/rfc2181.html#section-11)
- [RFC 5890：A-label / U-label / IDNA terminology](https://www.rfc-editor.org/rfc/rfc5890.html)

---

## 13. 第三輪實際驗證紀錄

### 13.1 本機

| 驗證 | 結果 |
|---|---|
| `bash tests/check_source_consistency.sh` | `PASS=25 FAIL=0` |
| 全部 shell `bash -n` | PASS（19 支） |
| `git diff --check` | PASS |
| DATA_DIR symlink cleanup-dry | exit 0，正確 planned 4 |
| parsed subdir symlink dry/real | 都 exit 0；拒絕 parsed 候選但宣告 cleanup 完成，重現 R3-03 |
| matched file symlink → outside | 只刪 link，outside checksum 不變 |
| altered embedded source rollback | exit 1，任何 replacement 前停止，全 new |
| syntactically-valid truncated patch | exit 0、0 bytes output、完全沒執行，重現 R3-04 |
| packaged guide wildcard | `no_match` |
| package PAX header inspection | 發現 `SCHILY/LIBARCHIVE.xattr.com.apple.provenance` |
| handoff hash 對帳 | gate 記錄 `5c6f...`，實檔為 `726c...`；不一致 |
| destructive test path contract | test guard 使用 `DATA_DIR`，三支 child 只讀 `OUTPUT_DIR`；確認 R3-07 mismatch |

現有 gate 全過只能證明 gate 已涵蓋的條件成立；R3-01～R3-07 說明目前 gate 仍有盲點。

### 13.2 BIG-IP LAB 17.1.3.1

| 驗證 | 結果 |
|---|---|
| production installed 三支 MD5 | 與 tracked new source 一致 |
| v3 patch MD5 | `685afe4c3e817abeb6a1861510a120f9` |
| v3 selftest `REPS=3` | exit 0，`PASS=16 FAIL=0` |
| installer target symlink overlap | installer exit 0，兩 lexical path 的 canonical path 完全相同 |
| unmanifested `extra.sh` symlink | SHA/coverage/installer 全過，extra 被 dereference 安裝 |
| GNU tar large listing | `tar|head` 與 `tar|grep -q` 都 rc 141 |
| 現行 package 解壓 | 內容成功，但出現 provenance extended-header warnings |

### 13.3 LAB 復原狀態

- 本輪所有 `rpzinst-review.*`、`rpzmanifest-review.*`、`rpztarpipe.*`、`rpzst.*`
  fixture 已清除。
- 本輪上傳的 package、review patch 與 selftest log 已刪除。
- `/config` 沒有被 installer 反向測試寫入。
- production installed 三支腳本未改動。
- `rpz_processor_handler` 維持 `active`、interval 300。

---

## 14. Claude Code 必須完成的修正順序

### Step 1 — 先修三個 High

1. R3-01：canonical path boundary，含建立前後重驗。
2. R3-02：exact package inventory，拒絕所有 symlink/special entry，copy 不用 wildcard。
3. R3-07：統一 destructive test 的 effective `OUTPUT_DIR`，並改成真正可失敗的 assertion。

完成前不要把 `dist/DO_NOT_DEPLOY.md` 的「路徑覆寫有安全邊界」與「manifest 未涵蓋
檔案會拒絕」保留為已完成敘述。

### Step 2 — 修 cleanup 與 patch artifact integrity

1. R3-03：subdir symlink policy + error propagation；任何 `[FAIL]` 不可最後 exit 0。
2. R3-04：patch `.sha256`、SOP preflight 與 gate。
3. R3-08：讓 recovery 摘要與 final detected state 一致。

### Step 3 — 修 release tooling 與文件

1. R3-05：移除 early-closing pipeline、移除 xattr、擴充 gate。
2. R3-06：更新 package 內 guide 與 release 文件。

### Step 4 — 重建所有衍生物

修正完成後必須重新產生：

- patch MD5 與 SHA-256 sidecar；
- v1.2.1 package（若仍維持此版本號，需說明這是未 release artifact 的 rebuild）；
- package outer `.sha256`；
- inner `SHA256SUMS`；
- handoff 的全部 hash、package 名稱與 LAB state；
- `dist/DO_NOT_DEPLOY.md` 的狀態。

不可手動只改 handoff hash；必須由實際 artifact 重新計算。

---

## 15. 第四輪驗收矩陣

Claude Code 完成後，下一輪至少要提供以下可重跑證據：

| Gate | 必要結果 |
|---|---|
| G1 syntax/diff | 全 shell `bash -n`、`git diff --check` 都 0 |
| G2 source consistency | tracked / embedded / expected hash / package 全一致 |
| G3 path symlink matrix | R3-01 的 7 種情境全部在 mutation 前正確拒絕/接受 |
| G4 manifest matrix | regular extra、symlink、dir symlink、`.conf`、FIFO、prefix collision 全部 fail-closed |
| G5 cleanup symlink matrix | DATA_DIR link、subdir link、file link；任何拒絕都 exit 非零且 final 不變 |
| G6 patch corruption | altered payload 與 valid truncation 都被外部 SHA gate 擋住 |
| G7 package pipeline | GNU tar large listing 下 build/gate 不得 141 或 false-negative |
| G8 package metadata | BIG-IP 解壓零 AppleDouble/PAX xattr warning |
| G9 packaged guide | 實際 artifact 名稱可逐字照 guide 完成 outer/inner checksum 與安裝 |
| G10 rollback matrix | 正常全 orig；三個 failure point 都全 new；訊息與 detected state 一致 |
| G11 core behavior | `f5_hotfix_test fixed` 與 v3 selftest 都 PASS/FAIL=0 |
| G12 LAB restoration | 無 temp、handler 狀態還原、production script/DataGroup state 有前後證據 |

另外必須保留前兩輪所有 regression tests，不能只新增第三輪測試而移除舊 assertion。

---

## 16. 不得誤宣告結案的既有項目

即使 R3-01～R3-08 全部修完，下列仍是第一輪已記錄、目前明確延後的專案可靠性債務：

- CR-06：SOA 取得錯誤誤判 NO_UPDATE。
- CR-07：SOA cache 在完整成功前提交。
- CR-08：serial decrease/rollover。
- CR-09：全流程 lock。
- CR-10：run manifest、atomic artifact/final publish、資料完整性門檻。
- CR-11：長期 cleanup/disk/log lifecycle。
- CR-12：`cleanup.sh` uninstall 保留 DataGroup 的安全性。
- CR-13：rpzip backend/policy。
- CR-14：iCall setup credential/update transaction。
- CR-15：全 pipeline 的集中 zone validation 與 input/output contract。
- DOC-06：全套 README、training、specification 同步。

第三輪只是在 Phase 1A artifact 上再次把關，不能用「SIGPIPE hotfix 通過」推論整個專案
已沒有其他造成靜默停滯、部分發布或磁碟累積的路徑。
