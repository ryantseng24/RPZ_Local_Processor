# iRule Archive

此目錄存放舊版本的 iRule 檔案，僅供參考。

## 檔案說明

### rpzdg_v15.tcl
- **版本**: V15（已棄用）
- **日期**: 2025-11-04
- **架構**: 多 DataGroup 方式
- **特點**:
  - 使用 `dg_ip_map` 映射多個 DataGroup
  - 按 Landing IP 分類（7 個不同的 DataGroup）
  - 需要在 foreach 循環中查詢多個 DataGroup
- **棄用原因**: 架構過於複雜，已改用單一 DataGroup 方式（rpzdg_local_v1.tcl）

## 當前使用版本

請使用 `irules/rpzdg_local_v1.tcl`（2025-11-07 更新）
- 單一 DataGroup 架構
- DataGroup 格式：`"domain" := "landing_ip"`
- 效能更優，維護更簡單
