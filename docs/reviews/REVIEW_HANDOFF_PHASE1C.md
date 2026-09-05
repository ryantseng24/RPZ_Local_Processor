# REVIEW_HANDOFF_PHASE1C — Phase 1C patch 審核交接

**初版**: 2026-09-04（送審）
**本版**: 2026-09-05（第一輪審核回應後更新）
**第一輪判定**: 日誌修正 GO / canary CONDITIONAL GO / e2e 驅動器修正前 NO-GO
（`CODE_REVIEW_PHASE1C_STE100_20260905.md`，SHA-256 `e1f0d694…`）。
**P1C-01（SOP）、P1C-02（e2e）、P1C-03（文字）已全部修正並重驗**：
mock 反向測試四模式全數中止、迴歸 PASS=33（新增 F4/F5 永久保護）、
gate PASS=42、patch 重建 SHA-256 `a0ca535f…`（payload 三檔 md5 不變）。
詳見 `process.md` 第 29 節。
**請求**: 短確認 P1C-01~03 關閉。
**判定格式**: GO / CONDITIONAL GO / NO-GO，findings 編號 P1C-xx。
**前情**: v4 與 Phase 1B 均已審核 GO（`process.md` 第 19~25 節）。
Phase 1C 是客戶 TAC 的新需求（09-03），獨立 patch，走既有流程。

---

## 1. 需求與診斷

客戶問題：腳本事件 log 以 `echo >> /var/log/ltm` 檔案直寫，繞過
syslog-ng，remote syslog（Splunk）收不到；事件期間 `RPZ parsing failed`
在 Splunk 完全不可見。需求：改用 `logger`（facility local0）產生。

診斷屬實：三支腳本共 17 處直寫（main 8、extract 4、update 5）。
LAB 實測 `logger -t RPZLocal -p local0.*` 落入 `/var/log/ltm`，
F5 原生格式。remote 段客戶已自證（`TEST--2`）。

## 2. 受審 artifacts

| 檔案 | md5 | 行數 | 角色 |
|---|---|---|---|
| `patches/rpz_patch_phase1c_v1.sh` | 見 sidecar | 890 | patch 本體（內嵌 647 + 邏輯 243） |
| `patches/rpz_patch_phase1c_v1.sh.sha256` | — | 1 | sidecar |
| `patches/build_patch_phase1c.sh` | — | 316 | builder（deterministic，已驗） |
| `scripts/main.sh` | `9d8538a68480a1a0489058be6b1d6622` | 350 | payload（1B 版 -> 1C 版） |
| `scripts/extract_rpz.sh` | `fea7c2e29f5380ab22611f7b2cc97fbc` | 85 | payload（v1.2 -> 1C 版） |
| `scripts/update_datagroup.sh` | `67227cb39028dc2bf17b14ef9c871bc4` | 200 | payload（v1.2 -> 1C 版） |
| `tests/lab/f5_patch_1c_test.sh` | — | 202 | 迴歸（33 斷言，含 F4 parsing 失敗、F5 logger 失敗永久保護） |
| `tests/lab/f5_e2e_1c_controlled.sh` | — | 132 | fail-closed e2e（15 斷言 + 4 拒絕 + P1C-02 修正與 mock 反向驗證） |
| `tests/check_source_consistency.sh` 第 9~10 節 | — | — | gate 改鏈模型 + 1C 檢查（PASS=42） |

patch SHA-256：
`a0ca535f84f744cb50dfbdbe84e9dec7362d398968dd53bd33ee9d2de04610ec`（輪 1 修正後；受審輪 1 版為 `9e0eca91…`）

## 3. payload 變更

1. 17 處 `echo "$ts $(uname -n) LEVEL: msg" >> /var/log/ltm` 改為
   `logger -t RPZLocal -p local0.err|notice "msg" || true`。
   訊息文字不變；移除自帶時間戳/主機名（syslog 加原生格式）；
   severity：ERROR 類 -> err（11 處）、INFO 類 -> notice（6 處）；
   `|| true` 使 logger 失敗不影響主流程（set -e 下安全）。
2. 移除失效的 `LOG_FILE` 變數 ×3 與只服務直寫的 `local timestamp` ×4（update 內兩函式各一）；
   main.sh usage 同步。
3. 修正 main.sh 兩處註解章節號（既有勘誤，patches/README 第 10.4 節
   等的就是這次 payload 變更）。
4. extract_rpz.sh 補結尾 newline（v1.2 同型問題）。

## 4. payload 鏈設計（請重點審這裡）

1. 1C 的「部署前版本」：main.sh = **1B 修正版**（`d1e1f688`）、
   extract/update = v1.2 原版。check 以 md5 強制部署順序
   v4 -> 1B -> 1C；未套 1B 的設備回報版本不明並拒絕。
2. gate 改鏈模型：1B patch 內嵌對「1B 凍結版」驗證（tracked main.sh
   已前進到 1C 版）；鏈尾對 tracked source。1B 的 GO 資產未改動
   （SHA-256 `aa97950e…` 不變），其迴歸測試（112 斷言）不依賴
   tracked source，仍可重跑。
3. 工具邏輯與 v4/1B 同款：md5 整批核對、pgrep guard、備份 +
   md5sums、原子取代、純部署前版本 rollback gate、目前檔案預檢。
   無 provider 依賴（三檔的 logging 變更互相獨立，混合狀態可運作）。

## 5. LAB 驗證證據（2026-09-04，BIG-IP 17.1.3.1 實機）

1. 迴歸：**PASS=29 FAIL=0**（M1-M8 機制 + F1-F3 syslog 功能，
   功能斷言以 ltm 行數基準比對新增行，含格式與無重複前綴檢查）。
2. e2e（fail-closed，拒絕案例 4 項全 RC=2）：**PASS=15 FAIL=0**。
   真實資料執行後 ltm 新增行實例：
   `Sep 4 12:12:02 <host> notice RPZLocal[24207]: dnsxdump exported 185458 lines`
   `... notice RPZLocal[24272]: updated DataGroup rpztw (58611 records, ...)`
   `... notice RPZLocal[24335]: RPZ processing completed in 8s`
   revision 34 -> 35、raw 保留策略仍有效、handler 恢復 active/300。
3. rollback e2e -> 再 apply 全 RC=0；v4 與 1C 兩條 check 鏈同時 RC=0。
4. deterministic 重建一致；sidecar RC=0；gate PASS=42 FAIL=0。

## 6. 已知限制

1. remote syslog -> Splunk 段在 LAB 無法驗證（無 Splunk）；依據為
   syslog 管道原理與客戶自測。canary 時由客戶在 Splunk 端確認。
2. 迴歸的功能測試會在 LAB 的真實 `/var/log/ltm` 產生少量 RPZLocal
   測試行（fixture 無法攔截 syslog；LAB 限定，良性）。
3. LAB license 到期日 2026/10/06（09-05 以 tmsh 查詢）。
4. wrapper 詳細 log（`rpz_wrapper.log`）機制不變，仍為本機檔案。

## 7. 給審核者的問題

1. 17 處替換與 severity 對映是否有遺漏或誤分級？
2. payload 鏈模型（1C 的 ORIG = 1B 版）與 gate 鏈式驗證是否成立？
3. `|| true` 的失敗容忍（logger 失敗不擋主流程）是否可接受？

## 8. 建議閱讀順序

1. 本文件
2. `patches/rpz_patch_phase1c_v1.sh`（工具邏輯與 1B 同款，可對照審）
3. `scripts/main.sh`、`scripts/extract_rpz.sh`、`scripts/update_datagroup.sh` 的 diff
4. `tests/lab/f5_patch_1c_test.sh`、`tests/lab/f5_e2e_1c_controlled.sh`
5. `process.md` 第 28 節
