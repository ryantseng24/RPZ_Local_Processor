# dist/ 內 artifact 的部署狀態

**最後更新**: 2026-08-23

## 不可部署

| 檔案 | 原因 |
|---|---|
| `rpz_local_processor_v1.2_20251202_140235.tar.gz` | 內含的 `parse_rpz.sh`、`generate_datagroup.sh`、`utils.sh` 是**未修正**的 v1.2 原版，仍有 `ls -t \| head -1` 的 SIGPIPE 缺陷。安裝這個包等於把缺陷裝回去。 |
| `../RPZ_Local_Processor.tar.gz` | 只有 29 bytes，是空 archive，不是有效的部署包。 |

上述兩個檔案**刻意保留**供對照與追溯，未刪除。

## v1.2.2 的狀態（HOLD，不可部署）

Phase 1B 三輪審核對完整安裝包維持 **NO-GO**。逐 artifact 記錄：

| tarball | SHA-256 | 狀態 |
|---|---|---|
| `rpz_local_processor_v1.2.2_20260823_003641.tar.gz` | `144ce079…` | 含 macOS xattr headers（P1B-06 原始發現對象），HOLD |
| `rpz_local_processor_v1.2.2_20260823_014255.tar.gz` | `783514f9…` | HOLD |
| `rpz_local_processor_v1.2.2_20260823_071238.tar.gz` | `0db3e50f8c0df5e44f8133f7f605fe4dc2be6af17e0992aad04caf2084b510f2` | 審核輪 3 本機掃描未見 `LIBARCHIVE.xattr`/`SCHILY.xattr` 字串，但 **P1B-06 不因此關閉**——需在 F5 GNU tar 實際解壓驗證後才能重判。HOLD |

**P1B-05 仍然成立**：`install.sh` 的 `SUPPORTED_VERSIONS="1.2.1"`，
任何 v1.2.2 包安裝必失敗。

`tests/check_source_consistency.sh` 的 PASS 只代表**內容一致性**（CR-03），
**不代表可安裝性**。在 P1B-05/06 關閉並重新送審前，v1.2.2 tarball
一律 HOLD。此 HOLD **不影響**既有設備套用 patch（v4 與 Phase 1B）。

## v1.2.1 的狀態（已被 v1.2.2 內容取代，同樣不可部署）

**尚未取得無條件上線許可。**

目前的包：

```
rpz_local_processor_v1.2.1_20260822_201752.tar.gz
SHA-256: b963cf213214ab203766ab38dc4b7d1e7e440715f5afd0aad85e4309dbab1682
```

已完成：

- 三處 SIGPIPE 缺陷修正，LAB 行為矩陣 17 項全過
- `SHA256SUMS` 完整性 manifest 與 `VERSION`
- `install.sh` fail-closed：缺 `VERSION`、`SHA256SUMS` 或 `sha256sum` 一律拒絕安裝；
  manifest 未涵蓋的可安裝檔案也拒絕；路徑覆寫有安全邊界
- 兩輪獨立審核的第一階段 findings 已修正並通過驗收矩陣

**上線前仍需要的條件**（見 `docs/reviews/CODE_REVIEW_PHASE1A_ROUND2_20260821.md` 第 13 節）：

1. 第三輪獨立審核通過。
2. 取得四台正式機的 `tmsh show sys version` 與 `md5sum scripts/*.sh`，
   確認腳本版本是本 patch 支援的原版 v1.2。

在這兩項完成前，不要把 v1.2.1 描述為可無條件部署。

## 部署方式

**全新安裝**用部署包：

```bash
sha256sum -c rpz_local_processor_v1.2.1_20260822_201752.tar.gz.sha256
tar xzf rpz_local_processor_v1.2.1_20260822_201752.tar.gz
cd ${PB%.tar.gz}
sha256sum -c SHA256SUMS
bash install.sh
```

**已安裝的機器要升級**不要用部署包覆蓋，用兩個 patch：
`patches/rpz_patch_sigpipe_v4.sh`（先）與 `patches/rpz_patch_phase1b_v1.sh`（後）。
SOP 見 `patches/README.md`。
