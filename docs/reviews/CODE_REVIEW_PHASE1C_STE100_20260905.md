# Phase 1C 獨立程式碼審核

審核日期：2026-09-05。文字採短句及一致術語。

本輪審核尚未提交的 Phase 1C 變更。比較基準為 Git `f560b80`。
交接文件中的歷史結果，與本輪實測結果分開記錄。

## 1. 判定

| 項目 | 判定 | 條件 |
|---|---|---|
| 三支腳本的日誌修正 | **GO** | 17 處替換正確。未發現本次變更造成的資料處理缺陷 |
| Phase 1C patch 工具 | **GO，依既定維護程序使用** | 先確認 v4 與 Phase 1B 已安裝。停止排程並等程序結束後操作 |
| 客戶單機 canary | **CONDITIONAL GO** | 先完成 P1C-01 的 SOP 與 P1C-03 的交付文字修正。Splunk 收件是現場驗收條件 |
| 現行 Phase 1C destructive e2e driver | **NO-GO** | P1C-02 已重現錯誤條件仍回報 PASS。修正前不再用它操作真實資料 |
| v1.2.3 完整安裝包 | **HOLD / NO-GO** | installer 仍只接受 1.2.1。本輪不審核或修復完整安裝包 |

目前不要求修改三支 production scripts 的執行邏輯。
不要求加入 transaction、recovery staging、cleanup 子命令或內嵌 selftest。
e2e 工具問題與 production patch 分開處理。不因測試工具的缺陷要求重寫 patch。

## 2. 問題與修正是否相符

本地郵件記錄的需求是：原本直接寫入本機日誌的 RPZ 事件，未出現在 Splunk。
郵件也記錄了使用 `logger -p local0.notice` 可收件的客戶自測。
本輪未登入客戶設備或 Splunk，沒有把客戶自述列為獨立端對端證據。

原版使用 `echo ... >> "$LOG_FILE"`，預設目標為 `/var/log/ltm`。
這是檔案寫入，不是送交系統日誌服務。
Phase 1C 改用 `logger -t RPZLocal -p local0.err` 或 `local0.notice`。
這個方向符合需求。

LAB 的 logger 是 util-linux 2.23.2。
已讀取 LAB syslog-ng 設定：本機來源經系統日誌管道處理，local0 訊息送至 ltm destination。
本輪既有 regression 也實際確認 notice 與 err 事件進入 `/var/log/ltm`。
logger 的本機送訊息行為，可對照 [util-linux 2.23.2 原始碼](https://github.com/util-linux/util-linux/blob/v2.23.2/misc-utils/logger.c)。

遠端轉送仍需要 F5 的遠端日誌設定及收件端接受該訊息。
不能把本機 ltm 出現事件，等同於 Splunk 已收件。
F5 官方文件將 `remote-servers` 列為獨立設定，預設為 none。參考 [F5 sys syslog 文件](https://clouddocs.f5.com/cli/tmsh-reference/latest/modules/sys/sys_syslog.html)。

### 2.1 實際事件數量

| 檔案 | local0.err | local0.notice | 合計 |
|---|---:|---:|---:|
| main.sh | 5 | 3 | 8 |
| extract_rpz.sh | 3 | 1 | 4 |
| update_datagroup.sh | 3 | 2 | 5 |
| 合計 | **11** | **6** | **17** |

所有替換都保留原事件主體。時間、主機及等級不再重複放入訊息主體。
`|| true` 讓日誌送出失敗不改變 RPZ 處理結果。
它不提供遠端收件保證，也不提供重送功能。本次不要求新增重送機制。
wrapper 的詳細診斷日誌仍是本機檔案。

## 3. Findings

### P1C-01 — Medium：部署及還原文件未涵蓋 Phase 1C 的版本關係

位置：

- [REVIEW_HANDOFF_PHASE1C.md:53](/Users/ryan/project/RPZ_Local_Processor/docs/reviews/REVIEW_HANDOFF_PHASE1C.md:53)
- [build_patch_phase1c.sh:11](/Users/ryan/project/RPZ_Local_Processor/patches/build_patch_phase1c.sh:11)
- [patches/README.md:204](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:204)

交接文件稱 `check` 強制 v4 → 1B → 1C 的完整順序。
實際工具只檢查 main、extract、update 三檔，不讀取 v4 的三檔。

本輪在 LAB 隔離目錄放入三個合法部署前檔案，不放入任何 v4 檔案：

```text
MISSING_V4_CHECK_RC=0 V4_FILES=0
MISSING_V4_APPLY_RC=0
```

這不是 logger 邏輯錯誤。這表示完整前置條件必須由 SOP 確認，不能只依賴 1C check。

安裝 1C 後，main.sh 的 MD5 已改變。
本輪對目前 LAB 執行唯讀檢查，結果如下：

```text
v4 check: RC=0，三檔已修正
1B check: RC=2，main.sh 版本不明
1C check: RC=0，三檔已套用 Phase 1C
```

這個 1B RC=2 是舊工具不認得新 main.sh，不表示 KEEP 修正被移除。
同理，已裝 1C 時直接執行舊版 1B rollback，會被目前版本檢查拒絕。
現有手冊第 5 節只寫「先還原 Patch 2，再還原 Patch 1」，不適用於已裝 1C 的設備。
手冊目前將 Patch 3 標成暫不部署，這個限制應維持到新 SOP 完成。

最小修正：

1. 補充 Phase 1C 部署章節，或新增一份短 SOP 並由主手冊連結。
2. 安裝前明確確認 v4 三檔均為修正版，及 1B main 為已知修正版。不是只看 RC=0。
3. 安裝後使用 v4 check 加 1C check。說明此時 1B check 的 RC=2。
4. 只回復日誌修正時，使用 1C 的純部署前備份。此動作保留 v4 與 1B。
5. 需要全部還原時，順序為 1C → 1B → v4。不得跳過 1C。
6. 記錄停止排程、等待程序結束、備份路徑，以及成功和失敗時的排程恢復步驟。
7. 部署前後都核對正確的 SHA-256 與檔案狀態。
8. canary 須在本機與 Splunk 比對帶有 `RPZLocal` 標籤的 notice 和 err 測試訊息。使用唯一測試識別碼；不故意破壞客戶流程來產生錯誤。

只需補 SOP。不要為此建立新的跨 patch 相依管理器，也不要放寬舊工具的未知版本保護。

### P1C-02 — Medium：e2e 在錯誤狀態下仍可回報全部通過

位置：

- [f5_e2e_1c_controlled.sh:26](/Users/ryan/project/RPZ_Local_Processor/tests/lab/f5_e2e_1c_controlled.sh:26)
- [f5_e2e_1c_controlled.sh:38](/Users/ryan/project/RPZ_Local_Processor/tests/lab/f5_e2e_1c_controlled.sh:38)
- [f5_e2e_1c_controlled.sh:94](/Users/ryan/project/RPZ_Local_Processor/tests/lab/f5_e2e_1c_controlled.sh:94)

本輪以本機 shell mock 執行完整 driver 副本。
只改本機輸出檔路徑；F5 指令全部由 mock 攔截。沒有連接設備做故障注入。
正常 mock 先得到 PASS=15，之後每次只改一個條件：

| 注入條件 | 實際 driver 結果 | 問題 |
|---|---|---|
| handler interval=3000 | PASS=15 FAIL=0 RC=0；印出 interval=300 | grep 的部分比對把 3000 當成 300 |
| tmsh list 輸出合法欄位，但 RC=42 | PASS=15 FAIL=0 RC=0 | 只檢查文字，忽略查詢失敗 |
| pgrep 回傳 2 | PASS=15 FAIL=0 RC=0 | 把查詢錯誤當成沒有程序 |
| EXIT trap 的第二次 save 回傳 42 | PASS=15 FAIL=0 RC=0，最後另印警告 | 顯示成功後又執行未納入判定的操作 |

這些反向測試不證明前一日的正常 e2e 失敗。
它們證明目前不能宣稱此 driver 在所有上述錯誤條件下都會停止。
部分寫法沿用 1B driver；本 finding 針對本次新增的 1C driver。
不追溯撤回 1B runtime 的既有判定。

最小修正：

1. 保存 `tmsh list` 的 RC。RC 非 0 時，不使用其輸出作成功證據。
2. 精確比對 status 與 interval 欄位。3000 不得通過 300 的檢查。
3. pgrep 的 1 表示沒有程序；2 以上表示檢查失敗。不要混用。
4. 正常完成後，不再由 EXIT trap 重複執行未驗證的 save。
   可在已完成且已核對恢復後解除 trap。失敗路徑保留恢復處理與非零 RC。
5. 補上以上反向測試。保留原有 --lab-only、主機名及確認字串。

不需要新增測試框架。
這是測試工具修正，不是 production runtime 修正。
修正前不要重跑這支 destructive driver。可以繼續使用經人工核對的隔離測試。

### P1C-03 — Low：交付文字與目前檔案不一致

主要位置：

- [REVIEW_HANDOFF_PHASE1C.md:27](/Users/ryan/project/RPZ_Local_Processor/docs/reviews/REVIEW_HANDOFF_PHASE1C.md:27)
- [REVIEW_HANDOFF_PHASE1C.md:43](/Users/ryan/project/RPZ_Local_Processor/docs/reviews/REVIEW_HANDOFF_PHASE1C.md:43)
- [process.md:1997](/Users/ryan/project/RPZ_Local_Processor/process.md:1997)
- [patches/README.md:326](/Users/ryan/project/RPZ_Local_Processor/patches/README.md:326)
- [rpz_patch_phase1c_v1.sh:9](/Users/ryan/project/RPZ_Local_Processor/patches/rpz_patch_phase1c_v1.sh:9)

修正以下文字即可：

| 現有說明 | 本輪核對結果 |
|---|---|
| err 10 處、notice 7 處 | err 11 處、notice 6 處 |
| 移除 local timestamp 共 3 處 | 共 4 處；update 內有兩個函式各一處 |
| builder 341 行、e2e 121 行 | builder 314 行、e2e 101 行 |
| LAB license 2026-09-05 到期 | 本輪 `tmsh show sys license` 顯示 2026/10/06。記錄查詢日期，勿沿用舊值 |
| 所有 builder 均可從目前 tracked source 重建 | 1B builder 對目前 1C main 回傳 RC=1。歷史來源應使用固定版本 |
| patch 註解稱本機與 Splunk 都收得到 | 改為本機已驗證；遠端由既有設定轉送，Splunk 須現場確認 |
| dist 的 HOLD 文件只列至 v1.2.2 | 補 v1.2.3 HOLD，不能用一致性 gate 的 PASS 表示可安裝 |

1B builder 的失敗是保護，不應刪除其 MD5 檢查。
本輪確認 `f560b80` 的 main MD5 為 `d1e1f688d939a5a5e87282605d0e3eed`，builder 也與該版本相同。
在文件註明使用該歷史版本重建 1B 即可。不要求新增版本選擇功能。
不要把 1B builder 的期望值改成 1C main，再覆寫已核准的 1B patch。

## 4. 本輪獨立驗證

| 項目 | 本輪結果 |
|---|---|
| Project gate | PASS=42 FAIL=0 RC=0 |
| Shell 語法 | gate 檢查 30 支腳本，通過 |
| Phase 1C deterministic rebuild | 在隔離副本重建，與交付檔 byte-for-byte 相同 |
| 三個 patch 的 sidecar 與嵌入內容 | gate 通過；v4、1B 的 SHA-256 未變 |
| LAB 現有 1C regression | PASS=29 FAIL=0 RC=0 |
| LAB 額外隔離 runtime 檢查 | PASS=46 FAIL=0；包含既有行為的確認，見下文 |
| 未知 target 的 rollback | RC=2，三個 target MD5 全部不變 |
| 缺 v4 的 1C check/apply | 均 RC=0，證實 P1C-01 的文件限制 |
| e2e 本機 mock | 正常對照成功；四種錯誤條件仍成功，證實 P1C-02 |
| git diff --check | 通過 |
| ShellCheck | 開發機未安裝，本輪未執行。語法檢查不等於 ShellCheck |
| 真實資料 destructive e2e | 本輪未執行；09-04 的 15 項與 revision 34→35 是交接記錄 |
| Splunk 收件 | 本輪未驗證。不能列為 PASS |

### 4.1 額外 runtime 檢查的範圍

以實際 1C main 搭配最小子程序替身執行。
測試在 LAB 獨立目錄，不使用真實 SOA 快取、不執行真實 tmsh 更新。

- 無變更與正常完成：RC=0。
- extract、parse、generate、update 失敗：主流程 RC=1，事件參數含 local0.err。
- logger 替身回傳 42：以上各路徑的主流程 RC 不變。
- 額外執行 extract 的缺指令、指令失敗、空輸出與正常輸出路徑。
- 額外執行 update 的建立成功／失敗、更新成功／失敗與缺來源檔路徑。
- 客戶提到的 `RPZ parsing failed` 已在隔離流程確認送給 logger，等級為 local0.err。

46 項包含兩次對既有 SOA 行為的確認，不是宣稱 46 種需求都已修復。
當 SOA 子程序回傳非零且沒有狀態字串時，main 的 pipeline 會先被 `set -e` 終止。
此時不會執行後面的 `RPZ SOA check failed` logger。
這段控制流程在本次 diff 前已存在，屬既有錯誤處理範圍。
本次 17 處是「呼叫位置數」，不是「所有錯誤皆可送至 Splunk」的保證。
不要求把此既有 SOA 問題或 CR-10 塞入 Phase 1C。

### 4.2 證據及重現入口

本輪的本機測試資料在：

`/private/tmp/rpz-phase1c-review.vvnk6J/`

| 檔案 | 用途 |
|---|---|
| [mock_e2e.sh](/private/tmp/rpz-phase1c-review.vvnk6J/mock_e2e.sh) | 本機 e2e 對照及四個反向測試，不操作 F5 |
| [runtime_extra.sh](/private/tmp/rpz-phase1c-review.vvnk6J/runtime_extra.sh) | 本輪 LAB 隔離 runtime 檢查原始碼 |
| [patch_extra.sh](/private/tmp/rpz-phase1c-review.vvnk6J/patch_extra.sh) | 本輪缺 v4、未知 target rollback 檢查原始碼 |
| [lab-evidence](/private/tmp/rpz-phase1c-review.vvnk6J/lab-evidence) | 回收的 LAB fixture 與各路徑日誌 |

重現本機 e2e 誤判：

```bash
/bin/bash /private/tmp/rpz-phase1c-review.vvnk6J/mock_e2e.sh normal
/bin/bash /private/tmp/rpz-phase1c-review.vvnk6J/mock_e2e.sh interval3000
/bin/bash /private/tmp/rpz-phase1c-review.vvnk6J/mock_e2e.sh read_error
/bin/bash /private/tmp/rpz-phase1c-review.vvnk6J/mock_e2e.sh pgrep_error
/bin/bash /private/tmp/rpz-phase1c-review.vvnk6J/mock_e2e.sh trap_save_error
```

測試輔助檔是本輪隔離資料，不是部署檔案。
LAB 輔助腳本內的目錄已清除，不能直接重跑；須重新建立隔離目錄並調整路徑。

### 4.3 LAB 收尾

本輪沒有修改已安裝腳本、DataGroup、SOA 快取、iRule、排程或 syslog 設定。
現有 regression 會在本機 ltm 留下少量測試事件。未刪除設備日誌。
自建隔離資料已回收至開發機。LAB 測試目錄已清除。

本輪讀取結果：handler active／interval 300；rpztw revision 35、size 2243094。
開始與收尾的值相同。已安裝腳本的 MD5 與受審 payload 一致。

## 5. 受審檔案識別

Phase 1C patch：

```text
9e0eca91b481ff20ab822deb5c741696581ce508a184de6b896d19a4168390bd
```

三支 production source 的 SHA-256：

```text
e3ec18ca5310897dff2400104db450cf9e4f35e23a4859312d93c736dfac4f7b  main.sh
d88dab144e6441ca358abcbab111050a3ced3d458d92d2b547c45e2dfc1fccc8  extract_rpz.sh
782684fa5ac2cacbbe14536b13675dcd77536bb3ce5f62ae7ca68d231579a5ae  update_datagroup.sh
```

e2e 受審版本 SHA-256：

```text
97cd08f119f2a247d966d66e3679df60cc9a7ac9475db52a7fe33dcc8106a82e
```

本輪在專案內只新增這份審核文件。沒有修改既有 source、patch、builder、測試或交接文件。
沒有 commit，沒有 push。

## 6. 修正與短確認要求

1. 完成 P1C-01 的短 SOP。保持未知版本拒絕覆寫。
2. 修正 P1C-02 的查詢 RC、精確欄位比對及收尾判定。只改測試工具。
3. 修正 P1C-03 的文字。更新交接文件及 v1.2.3 HOLD 說明。
4. 將 parsing-failure 與 logger-failure 的小測試加入既有 regression，建議作為永久保護；不需要移入全部 46 項審核探測。
5. 如果只改 Markdown 與測試檔，不需要重建 production patch。
   如果修改 builder 產生的 patch 註解，則須重建並重算 SHA-256；三支 payload hash 應保持不變。
6. 重跑 project gate、sidecar 與 e2e 的上述 mock 反向測試。
   本輪不要求再跑完整 4096 failure curve，也不要求重做 65 分鐘 soak。
7. Splunk 收件由 canary 現場驗收。收件驗證完成前，不宣稱需求端對端結案。
8. 提交前排除本地 `.eml`。目前它仍是未追蹤檔案，且未被 ignore。不得將郵件及個資提交到公開 repo。

維持 Phase 1C 的小範圍修正。不修改 iRule，不擴充為完整日誌平台，不修完整安裝包。
