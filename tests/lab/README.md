# tests/lab/

只在 LAB 執行的測試腳本。**不會**被 `package.sh` 打包，不可放進部署包。

| 腳本 | 破壞性 | 說明 |
|---|---|---|
| `f5_hotfix_test.sh` | 無 | 行為驗收矩陣 T1~T9。全程在 `mktemp -d` 的隔離目錄，不碰 `/config/snmp/rpz_datagroups`，不呼叫 tmsh。可對原版或修正版執行 |
| `f5_rate_probe.sh` | 無 | 用真實 `parse_rpz.sh` 量測 SIGPIPE 失敗率。輸出在 `/var/tmp` |
| `f5_e2e_probe.sh` | 無 | 用 `bash -x` 追出死亡行號。輸出在 `/var/tmp` |
| `f5_pipefail_probe.sh` | 低 | 合成測試。預設只在 `/var/tmp`；加 `--on-config` 才會在 `/config/snmp/rpzprobe/` 建 0 bytes 假檔並自刪 |
| **`f5_manual_cleanup_test.sh`** | **高** | **會刪除 `OUTPUT_DIR/raw`、`OUTPUT_DIR/parsed` 的檔案並執行 `main.sh --force`** |
| `f5_patch_v4_test.sh` | 低 | v4 patch 工具迴歸（78 斷言）。fixture 在 `/var/tmp/rpz_v4_test`，以 sed 副本改指 fixture，不碰 `/config` |
| `f5_patch_1b_test.sh` | 低 | Phase 1B 迴歸（112 斷言）。fixture 在 `/var/tmp/rpz_1b_test`；用 chattr +i 做故障注入，trap 會解除 |
| **`f5_e2e_1b_controlled.sh`** | **高** | **寫真實 `rpz_datagroups`、停/啟 handler、套 patch、`tmsh save sys config`。四道硬性防護：`--lab-only`、主機名必須 `cdns.ryantseng.work`（用 `uname -n`，無 bypass）、`E2E_CONFIRM` 完整確認字串、handler 初始必須 active/300。合成檔記錄於 manifest，只刪 manifest 內的檔案** |

## f5_manual_cleanup_test.sh 的執行條件

這支腳本的目的是驗證「人力手動刪檔能否在套 patch 前恢復 pipeline」，
必須在**原版 v1.2 腳本**的狀態下執行才有意義。

七道 guard 全部通過才會動作：

1. 必須明確 `--lab-only`
2. hostname 必須精確等於 `LAB_HOSTNAME`（**沒有旗標能繞過**）
3. `OUTPUT_DIR` 與 `SCRIPTS_DIR` 必須存在
4. `final/rpztw.txt` 非空時，必須加專屬旗標 `--allow-production-marker`
5. 互動輸入完整 hostname，或非互動時 `RPZ_LAB_CONFIRM` 精確相符
6. iCall periodic handler 必須全部 inactive，且無執行中的 processor
7. 三支腳本必須是原版 v1.2 的 md5

`f5_pipefail_probe.sh` 內含刻意重現 `ls -t | head -1` SIGPIPE 的程式碼。
那是缺陷的示範，不是要修的對象。其他腳本已移除同型的 early-close pipeline。
