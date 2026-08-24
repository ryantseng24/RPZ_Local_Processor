# Phase 1A 交接說明 — 第三輪修訂版審核後

**日期**: 2026-08-22
**依據**: `CODE_REVIEW_PHASE1A_ROUND3_REV2_20260821.md`
（SHA-256 `1d7e9412d00cdabfa9d944825803deadfb0c3836e2689a98e012b13e648342c6`，已核對相符）
**判定**: v3 核心修正 PASS；既有客戶機器 rollout CONDITIONAL GO
**本文件**: 回答審核第 10.3 節的九個問題，並列出第 10.1 節清單的完成狀態

---

## 1. 第 10.1 節清單完成狀態

| 項目 | 狀態 |
|---|---|
| 保持 `find_newest_file` 與三個 call site 核心行為不回歸 | 完成。F1 fixed variant REPS=20，raw/parsed 300 檔各 0 失敗 |
| 修正 cleanup 子目錄 symlink false-success | 完成，選擇直接小修（見第 3 節） |
| 產生最終 patch `.sha256` sidecar | 完成 |
| 在 `process.md` / `patches/README.md` 寫清楚完整 SOP | 完成，SOP 在 `patches/README.md`，10 個步驟 + 中止/回復表 |
| 明列 production 不使用任意路徑覆寫 | 完成，SOP 每個命令都明確傳入固定路徑 |
| 修正後重跑第 4.4 節 gate | 完成，見第 4 節 |
| 更新所有 MD5/SHA-256，移除舊 handoff 的錯誤 hash | 完成。上一份 handoff 的 `tests/check_source_consistency.sh` md5 `5c6fdf26…` 確實是舊值，實際是 `726c73c2…`，本輪再改後為 `76a99cdd…` |
| 提供 canary 前後狀態表 | 完成，見第 5 節 |

第 10.2 節（不阻擋 patch）：`f5_manual_cleanup_test.sh` 的 `OUTPUT_DIR` contract
已修正；package.sh 與 consistency gate 的 early-close pipeline 已移除；
recovery 訊息已改為依 `detect_state` 判定。installer / INSTALL_GUIDE / 新安裝包
仍為 HOLD，未在本輪處理。

---

## 2. 回答第 10.3 節的九個問題

### Q1 最終 patch SHA-256，以及 F5 上 `sha256sum -c` 的實際退出碼

```
9876a90aa04e3748a37e23a7af3af4720f45028877b6b8fb08c7a891dd60d7d0  rpz_patch_sigpipe_v3.sh
```

sidecar `patches/rpz_patch_sigpipe_v3.sh.sha256` 內容只有 basename，不含絕對路徑。

F5 上實際執行：

```
# cd /var/tmp && sha256sum -c rpz_patch_sigpipe_v3.sh.sha256
rpz_patch_sigpipe_v3.sh: OK
退出碼 0
```

### Q2 `check` 對 orig / new / unknown 的退出碼

本輪新增退出碼語意（原本三種狀態都回 0，SOP 無法用退出碼判斷）：

| 狀態 | 退出碼 | LAB 實測 |
|---|---|---|
| orig | 0 | 0 |
| new | 0 | 0 |
| **unknown / mixed** | **2** | **2**，並額外印出每支檔案的實際 md5 與分類 |

unknown 的實測輸出：

```
utils.sh                 3cab6cbca952f3780350e9882e5f7c11  orig
parse_rpz.sh             cefa71b6623632dd51c60a51cdf72196  new
generate_datagroup.sh    9599755a54db53652c070cd70ae92652  new
整體判定: unknown
```

### Q3 apply 後三支實際 MD5 是否精確等於 embedded expected MD5

是。隔離 fixture 從原版 v1.2 apply 後：

```
b8294149dc978305e19bcd83fcb650e6  utils.sh
cefa71b6623632dd51c60a51cdf72196  parse_rpz.sh
9599755a54db53652c070cd70ae92652  generate_datagroup.sh
```

與 patch 內嵌的 expected new MD5 完全相同。
`tests/check_source_consistency.sh` 也逐檔驗證 patch 嵌入內容與 tracked source
byte-for-byte 一致。

### Q4 `REPS=10` selftest 的 PASS/FAIL 與退出碼

LAB production 安裝目錄：`PASS=16 FAIL=0`，退出碼 **0**，無殘留 temp 目錄。
隔離 fixture 同樣 `PASS=16 FAIL=0`。

### Q5 fixed variant 300 檔、REPS 20 的 raw/parsed 失敗數

```
T8 raw 300 檔     ls 輸出 18361B   失敗 0/20
T9 parsed 300 檔  ls 輸出 18361B   失敗 0/20
variant=fixed  PASS=17  FAIL=0   退出碼 0
```

### Q6 cleanup 遇 subdir symlink 是否非零，且沒有部分刪除

是。隔離測試把 `parsed` 做成 symlink：

```
[FAIL] …/data/parsed 是 symlink。cleanup 只支援實體目錄，拒絕執行。
[FAIL] 資料子目錄檢查失敗，拒絕執行 cleanup（未列舉任何檔案，未刪除任何東西）
退出碼 1
parsed 檔案數 15 -> 15（完全沒有刪除）
```

對照組（實體目錄）退出碼 0，parsed 15 -> 3，正常運作。

### Q7 真實 `main.sh --force` 是否成功；final 與 DataGroup 前後狀態

成功。raw 填到 202 檔（`ls` 輸出 12322 bytes，遠超 4096）：

```
退出碼 0，總耗時 00:00:07
rpztw 58610 筆、phishtw 819 筆
成功: 2 個, 失敗: 0 個, 跳過: 0 個
DataGroup revision 9 -> 10
final/ 三個檔案 mtime 一致（2026-08-22 20:21）
```

### Q8 handler 是否恢復 active、interval 300，並已 save config

是。

```
sys icall handler periodic rpz_processor_handler {
    interval 300
    script rpz_processor_script
}
```

輸出沒有 `status inactive` 即為 active。恢復 active 之後有再執行一次
`tmsh save sys config`（因為 `main.sh --force` 內部會 save，若不補這一次，
inactive 狀態會被留在設定檔）。

### Q9 LAB 是否清除 fixture，production scripts 與資料是否處於預期最終狀態

fixture 已清除：`rpzst.*`、`rpzstage.*`、`rpzrecov.*`、`rpzhf.*`、
`rpzunsafe.*` 殘留數為 **0**。

LAB 的 production 路徑處於預期最終狀態，見第 5 節。
`/var/tmp` 保留：patch 與 sidecar、patch 備份目錄、現行 package、
比對用的 `origsrc`/`newsrc`。

---

## 3. cleanup false-success 的修法（第 4.2 節）

選擇直接小修，不留在 SOP 靠人工檢查。

| 新增 | 作用 |
|---|---|
| `validate_data_subdirs()` | 列舉前要求 `raw`、`parsed`、`final` 都是 `DATA_DIR` 下的實體目錄。任一是 symlink 或不存在就整體拒絕 |
| `CLEANUP_UNSAFE_LOG` | `cleanup_victims` 遇到 `safe_victim` 拒絕的候選時寫入此檔。`do_cleanup` 在規劃完成後檢查，非空就整體回傳非零且**不進入刪除階段** |
| 刪除階段後再檢查一次 | 防止刪除過程中出現新的不安全候選 |

沒有支援任意 symlink topology，對本案固定的 production layout 明確拒絕即可。

---

## 4. 第 4.4 節 gate 的實際結果

所有 hash 都在最後一次修改之後才計算。

| 項目 | 結果 |
|---|---|
| 1. 所有 shell `bash -n` | 19 支全部通過 |
| 2. `git diff --check` | 通過 |
| 3. `tests/check_source_consistency.sh` | **PASS=25 FAIL=0** |
| 4. v3 selftest REPS=10 | **PASS=16 FAIL=0**，退出碼 0 |
| 5. `f5_hotfix_test` fixed REPS=20，raw/parsed 300 檔 | **PASS=17 FAIL=0**，兩者皆 0/20 失敗 |
| 6. 原版 fixture 的 check → apply → selftest → 重複 apply → rollback → apply | 全部通過，狀態依序 orig / new / new / new / orig / new，退出碼皆 0 |
| 7. 重新計算所有 MD5/SHA-256 | 見第 6 節 |

consistency gate 本身也依審核第 6.1 節移除了 `ls -t | head -1`，
改用與 production 同型的純 bash mtime 迴圈。`package.sh` 的
`tar tzf | grep -q` 與 `| head -20`、`f5_rate_probe.sh` 的 `grep | head`
也一併移除。

`tests/lab/f5_pipefail_probe.sh` 仍保留 `ls|head`，那是刻意重現缺陷的示範，
已在 `tests/lab/README.md` 註明。

---

## 5. Canary 前後狀態表（LAB `10.8.34.223`）

| 項目 | BEFORE | AFTER |
|---|---|---|
| handler | interval 300，active | interval 300，**active**，已 save config |
| `utils.sh` | `b8294149…` | `b8294149…` |
| `parse_rpz.sh` | `cefa71b6…` | `cefa71b6…` |
| `generate_datagroup.sh` | `9599755a…` | `9599755a…` |
| `/config` | 2.1G，37M used，2% | 2.1G，44M used，3% |
| raw / parsed / final | 2 / 6 / 3 | 3 / 9 / 3 |
| `final/rpztw.txt` | 2243064 B，08-21 15:22 | 2243064 B，08-22 20:21 |
| `final/phishtw.txt` | 30862 B，08-21 15:22 | 30862 B，08-22 20:21 |
| `final/rpzip.txt` | 0 B，08-21 15:22 | 0 B，08-22 20:21 |
| DataGroup rpztw | revision 9，size 2243064 | **revision 10**，size 2243064 |
| DataGroup phishtw | revision 9，size 30862 | **revision 10**，size 30862 |
| temp 殘留 | — | 0 |

LAB 在本輪 apply 前已是 v3 修正版，所以三支 md5 前後相同；
revision 前進證明 force run 真的重新載入了 DataGroup。

---

## 6. 最終 hash

### tracked source

| 檔案 | 原版 v1.2 | 現行 |
|---|---|---|
| `scripts/utils.sh` | `3cab6cbca952f3780350e9882e5f7c11` | `b8294149dc978305e19bcd83fcb650e6` |
| `scripts/parse_rpz.sh` | `bbe45c6f79b56922388d4af7aa6e7583` | `cefa71b6623632dd51c60a51cdf72196` |
| `scripts/generate_datagroup.sh` | `35547d33ce109945d1ca17e8eb241e0a` | `9599755a54db53652c070cd70ae92652` |
| `scripts/check_soa.sh` | `19700e7c413d6c809dda6434292406cc` | 未修改 |
| `scripts/extract_rpz.sh` | `62aeaf053b08f3411fe530f33555c414` | 未修改 |
| `scripts/main.sh` | `0041c1d74e5b8514dea506608607b8c6` | 未修改 |
| `scripts/update_datagroup.sh` | `f8b038bc06df1c07050cd2922a91c5aa` | 未修改 |

### 工具與 artifact

| 檔案 | md5 |
|---|---|
| `patches/rpz_patch_sigpipe_v3.sh` | `3b50f5ec394aad24536d1ffc9851f4a8` |
| `install.sh` | `f9fd0e2f106caee52aa36f597a3d2361` |
| `package.sh` | `9092561f65ec9355f504a101aea6d327` |
| `cleanup.sh` | `4790412f2873d6fea74719f0a9ea224c`（未修改） |
| `tests/check_source_consistency.sh` | `76a99cdd38762c59118d68f1f054799f` |
| `tests/lab/f5_hotfix_test.sh` | `4124f45adfd1869d2a221ba9567fe519` |
| `tests/lab/f5_manual_cleanup_test.sh` | `79dee3dffbee3f94d582052bd9cad958` |
| `tests/lab/f5_rate_probe.sh` | `bb6a2efd7af80262a1138f3748447882` |
| `tests/lab/f5_e2e_probe.sh` | `f1aacaf211daf8535a37d93ca5e235fa` |
| `tests/lab/f5_pipefail_probe.sh` | `e93f448e6a13bfb848c441b27c831da5` |

### SHA-256

```
9876a90aa04e3748a37e23a7af3af4720f45028877b6b8fb08c7a891dd60d7d0  patches/rpz_patch_sigpipe_v3.sh
b963cf213214ab203766ab38dc4b7d1e7e440715f5afd0aad85e4309dbab1682  dist/rpz_local_processor_v1.2.1_20260822_201752.tar.gz
```

---

## 7. 必須向客戶與維運說明的界線

**v3 永久排除的是 `ls`/`head` 引發的 4096/SIGPIPE 缺陷。**
檔案數再多也不會因為這個原因失敗。

**它不保證其他失敗不會造成暫存檔累積。**
`main.sh` 的 `cleanup()` 仍只在五步全部成功後執行。若未來因 SOA、dnsxdump、
awk、tmsh 或其他原因長期失敗，`raw/`、`parsed/` 仍會累積。這是獨立的
lifecycle 問題，屬 Phase 1B，不應說成已由本 hotfix 解決。

建議的 Phase 1B（不塞進本次 hotfix）：

1. `final/` 最後成功時間的告警，超過數個 handler 週期就通知。
2. `/config` 使用率與 raw/parsed 檔案數的簡單監測。
3. housekeeping 限定 raw/parsed，與主處理成功與否解耦。
   **絕對不要把 `final/` 放進失敗路徑的通用 `find -delete`。**
4. SOA cache 在完整成功前就前進、全流程 lock、final atomic publish。

---

## 8. 仍為 HOLD 的項目

| 項目 | 狀態 |
|---|---|
| v1.2.1 新安裝包 | HOLD。installer 路徑處理、manifest symlink、`INSTALL_GUIDE.txt` 過期都未處理。**不阻擋既有機器套 patch** |
| `tests/lab/f5_manual_cleanup_test.sh` | `OUTPUT_DIR` contract 已修，但**尚未在 LAB 實際執行過**（七道 guard 會擋，需要先把三支腳本還原成原版）。修正內容已驗證 guard 行為，但完整情境 A~D 未跑 |
| `cleanup.sh`（解除安裝腳本） | 未修改。第 230 行有 `tmsh list … \| grep -qE`，是同型的 early-close，但 tmsh 輸出僅數行、遠低於 4096。屬 CR-12 的 Phase 2 範圍 |

---

## 9. 這輪我自己發現並修掉的問題

| 問題 | 說明 |
|---|---|
| `check` 對 unknown 也回傳 0 | SOP 要求「unknown 立即停止」，但退出碼無法區分。已改為 unknown 回傳 2 並列出每支狀態 |
| `f5_manual_cleanup_test.sh` line 104 的錯誤訊息 | 改名後仍引用已不存在的 `$DATA_DIR`。已修 |
| consistency gate 自己用 `ls -t \| head -1` 挑 package | 審核第 6.1 節點名的問題。已改為純 bash mtime 迴圈 |
| `package.sh` 的 `tar tzf \| grep -q` 與 `\| head -20` | 同型 early-close。已改為先讀進變數 |
| `f5_rate_probe.sh` 的 `grep \| head -400` | 對 5 MB 檔案的同型 early-close。已改用 `sed -n` |
