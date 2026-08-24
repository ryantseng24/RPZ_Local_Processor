#!/bin/bash
# =============================================================================
# package.sh - 打包 RPZ Local Processor 部署檔案
# =============================================================================
# 用途: 產生可傳輸到客戶 F5 的安裝包
# 輸出: rpz_local_processor_YYYYMMDD_HHMMSS.tar.gz
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 版本與時間戳
# 1.2.1: 修正 ls|head 在 pipefail 下的 SIGPIPE 缺陷 (見 process.md 第 2 節)
# 1.2.2: Phase 1B 暫存檔保留策略，只改 main.sh (見 process.md 第 22 節)
VERSION="1.2.2"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
PACKAGE_NAME="rpz_local_processor_v${VERSION}_${TIMESTAMP}"
OUTPUT_DIR="${SCRIPT_DIR}/dist"

# =============================================================================
# 部署包內容的單一定義
# =============================================================================
# 這是 package 內容的唯一來源。tests/check_source_consistency.sh 會解析
# 同一份清單來逐檔比對，避免「tracked source 已改、package 未重建」時
# 測試仍然過關。參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md R2-06。
# 每一行是相對於 repo 根目錄的路徑，在 package 內使用相同的相對路徑。
# PACKAGE_INPUTS_BEGIN
PACKAGE_INPUTS="
scripts/check_soa.sh
scripts/extract_rpz.sh
scripts/generate_datagroup.sh
scripts/main.sh
scripts/parse_rpz.sh
scripts/update_datagroup.sh
scripts/utils.sh
config/zonelist.txt
config/icall_setup_api.sh
install.sh
cleanup.sh
INSTALL_GUIDE.txt
"
# PACKAGE_INPUTS_END

echo "=========================================="
echo "  RPZ Local Processor 打包工具"
echo "=========================================="
echo ""
echo "版本: $VERSION"
echo "時間: $TIMESTAMP"
echo ""

# 建立輸出目錄
mkdir -p "$OUTPUT_DIR"

# 建立臨時打包目錄
TEMP_DIR=$(mktemp -d)
PACKAGE_DIR="${TEMP_DIR}/${PACKAGE_NAME}"
mkdir -p "$PACKAGE_DIR"

echo "[1/5] 複製核心檔案..."

for rel in $PACKAGE_INPUTS; do
    [ -n "$rel" ] || continue
    if [ ! -f "$rel" ]; then
        echo "  ✗ 找不到 package input: $rel"
        exit 1
    fi
    mkdir -p "${PACKAGE_DIR}/$(dirname "$rel")"
    cp "$rel" "${PACKAGE_DIR}/$rel"
    echo "  ✓ $rel"
done

echo ""
echo "[2/5] 設定檔案權限..."
for rel in $PACKAGE_INPUTS; do
    case "$rel" in *.sh) chmod +x "${PACKAGE_DIR}/$rel" ;; esac
done
echo "  ✓ 執行權限已設定"

echo ""
echo "[3/5] 產生 SHA-256 manifest..."
cd "$PACKAGE_DIR"
# 清除作業系統的中繼資料檔案。macOS 的 tar 會產生 ._* AppleDouble 檔案，
# 若進了部署包會被解到 F5 上，而且不在 manifest 內。
find . \( -name '._*' -o -name '.DS_Store' -o -name '.AppleDouble' \) -print -delete | sed 's|^|  移除 |'

printf '%s\n' "$VERSION" > VERSION
# manifest 用相對路徑，讓 install.sh 可以直接 sha256sum -c
find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
echo "  ✓ SHA256SUMS ($(wc -l < SHA256SUMS) 個檔案)"
echo "  ✓ VERSION = $VERSION"
if sha256sum -c SHA256SUMS >/dev/null 2>&1; then
    echo "  ✓ manifest 自我驗證通過"
else
    echo "  ✗ manifest 自我驗證失敗"
    exit 1
fi
cd "$TEMP_DIR"

echo ""
echo "[4/5] 建立壓縮檔..."
# COPYFILE_DISABLE=1 讓 macOS 的 tar 不要寫入 AppleDouble/擴充屬性
COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
    tar czf "${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"

# 打包後回頭確認壓縮檔內沒有中繼資料檔案
# 不用 `tar tzf | grep -q`：grep -q 會提早關閉 pipe，讓 tar 收到 SIGPIPE。
# 這正是本次要修的缺陷型態，工具本身不應重現。先完整讀進變數再比對。
TAR_LISTING=$(tar tzf "${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz")
META_ENTRIES=$(printf '%s\n' "$TAR_LISTING" | grep -E '/\._|\.DS_Store' || true)
if [ -n "$META_ENTRIES" ]; then
    echo "  ✗ 壓縮檔內含作業系統中繼資料檔案"
    printf '%s\n' "$META_ENTRIES" | sed 's|^|    |'
    exit 1
fi
echo "  ✓ 壓縮檔內無作業系統中繼資料檔案"
echo "  ✓ ${PACKAGE_NAME}.tar.gz"

echo ""
echo "[5/5] 清理暫存..."
rm -rf "$TEMP_DIR"
echo "  ✓ 暫存目錄已清理"

# 顯示結果
PACKAGE_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz"
PACKAGE_SIZE=$(ls -lh "$PACKAGE_FILE" | awk '{print $5}')
PACKAGE_SHA=$(sha256sum "$PACKAGE_FILE" | awk '{print $1}')
printf '%s  %s\n' "$PACKAGE_SHA" "${PACKAGE_NAME}.tar.gz" > "${PACKAGE_FILE}.sha256"

echo ""
echo "=========================================="
echo "  打包完成！"
echo "=========================================="
echo ""
echo "輸出檔案: $PACKAGE_FILE"
echo "檔案大小: $PACKAGE_SIZE"
echo "SHA-256:  $PACKAGE_SHA"
echo "         （另存於 ${PACKAGE_NAME}.tar.gz.sha256）"
echo ""
echo "包含內容:"
printf '%s\n' "$TAR_LISTING" | sed -n '1,20p'
echo ""
echo "----------------------------------------"
echo "部署步驟:"
echo "----------------------------------------"
echo "1. 上傳檔案到 F5:"
echo "   scp ${PACKAGE_FILE} admin@<F5_IP>:/var/tmp/"
echo ""
echo "2. SSH 登入 F5 執行:"
echo "   cd /var/tmp"
echo "   tar xzf ${PACKAGE_NAME}.tar.gz"
echo "   cd ${PACKAGE_NAME}"
echo "   sha256sum -c SHA256SUMS      # 驗證檔案完整性"
echo "   bash install.sh"
echo ""
echo "3. 上傳前後可比對整包的 SHA-256:"
echo "   sha256sum ${PACKAGE_NAME}.tar.gz"
echo "   預期: $PACKAGE_SHA"
echo ""
