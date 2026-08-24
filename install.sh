#!/bin/bash
# =============================================================================
# install.sh - RPZ Local Processor 本地安裝腳本
# =============================================================================
# 用途: 在 F5 BIG-IP 上安裝 RPZ Local Processor
# 執行: 解壓縮部署包後，在 F5 上執行此腳本
#
# 完整性驗證為 fail-closed：缺少 VERSION、SHA256SUMS 或 sha256sum 都會拒絕安裝。
# 路徑覆寫有安全邊界。參見 CODE_REVIEW_PHASE1A_ROUND2_20260821.md R2-04、R2-07。
#
# 環境變數:
#   INSTALL_DIR            安裝目錄，預設 /config/snmp/RPZ_Local_Processor
#   OUTPUT_DIR             資料目錄，預設 /config/snmp/rpz_datagroups
#   RPZ_INSTALL_TEST_MODE  設為 1 時允許安裝到 /var/tmp 或 /shared/tmp 底下，
#                          供隔離測試使用。正式安裝不要設。
#   RPZ_ALLOW_UNVERIFIED_PACKAGE
#                          設為 "yes-i-accept-an-unverified-package" 時跳過
#                          完整性驗證。高風險，預設關閉，只給 legacy 包用。
# =============================================================================

set -euo pipefail

# 此 installer 支援的部署包版本
SUPPORTED_VERSIONS="1.2.1"

# 取得腳本所在目錄（解壓縮後的目錄）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# 安裝目標目錄。可用環境變數覆寫，但必須通過下方的路徑驗證。
INSTALL_DIR="${INSTALL_DIR:-/config/snmp/RPZ_Local_Processor}"
OUTPUT_DIR="${OUTPUT_DIR:-/config/snmp/rpz_datagroups}"

TEST_MODE="${RPZ_INSTALL_TEST_MODE:-0}"
ALLOW_UNVERIFIED="${RPZ_ALLOW_UNVERIFIED_PACKAGE:-}"

echo "=========================================="
echo "  RPZ Local Processor 安裝程式"
echo "=========================================="
echo ""
echo "來源目錄: $SCRIPT_DIR"
echo "安裝目錄: $INSTALL_DIR"
echo "輸出目錄: $OUTPUT_DIR"
if [[ "$TEST_MODE" == "1" ]]; then
    echo ""
    echo "  ****  RPZ_INSTALL_TEST_MODE=1：隔離測試模式  ****"
fi
echo ""

# =============================================================================
# 步驟 1: 驗證路徑與部署包完整性
# =============================================================================
# 這一步的所有檢查都必須在任何 mkdir / cp 之前完成。

echo "[1/7] 驗證路徑與部署包完整性..."

# ---------- 1a. 路徑安全驗證 (R2-07) ----------

validate_abs_path() {
    local label="$1" p="$2"
    if [[ -z "$p" ]]; then echo "  ✗ $label 不可為空"; return 1; fi
    case "$p" in
        /)  echo "  ✗ $label 不可為 /"; return 1 ;;
        /*) ;;
        *)  echo "  ✗ $label 必須是絕對路徑: $p"; return 1 ;;
    esac
    case "$p" in
        */)        echo "  ✗ $label 不可以 / 結尾: $p"; return 1 ;;
        *//*)      echo "  ✗ $label 不可含連續斜線: $p"; return 1 ;;
        */./*|*/.) echo "  ✗ $label 不可含 '.' 路徑元素: $p"; return 1 ;;
        */../*|*/..) echo "  ✗ $label 不可含 '..' 路徑元素: $p"; return 1 ;;
    esac
    return 0
}

is_within() {   # is_within <inner> <outer>：相同或被包含都算 true
    case "$1" in
        "$2"|"$2"/*) return 0 ;;
    esac
    return 1
}

validate_abs_path "INSTALL_DIR" "$INSTALL_DIR" || exit 1
validate_abs_path "OUTPUT_DIR"  "$OUTPUT_DIR"  || exit 1
echo "  ✓ 兩個路徑都是安全的絕對路徑"

if [[ "$INSTALL_DIR" == "$OUTPUT_DIR" ]]; then
    echo "  ✗ INSTALL_DIR 與 OUTPUT_DIR 不可相同"; exit 1
fi
if is_within "$INSTALL_DIR" "$OUTPUT_DIR" || is_within "$OUTPUT_DIR" "$INSTALL_DIR"; then
    echo "  ✗ INSTALL_DIR 與 OUTPUT_DIR 不可互相包含"; exit 1
fi
echo "  ✓ 兩個路徑不相同也不互相包含"

if is_within "$INSTALL_DIR" "$SCRIPT_DIR" || is_within "$SCRIPT_DIR" "$INSTALL_DIR"; then
    echo "  ✗ INSTALL_DIR 不可與部署包來源目錄相同或互相包含"; exit 1
fi
if is_within "$OUTPUT_DIR" "$SCRIPT_DIR" || is_within "$SCRIPT_DIR" "$OUTPUT_DIR"; then
    echo "  ✗ OUTPUT_DIR 不可與部署包來源目錄相同或互相包含"; exit 1
fi
echo "  ✓ 兩個路徑都不與來源目錄重疊"

if [[ "$TEST_MODE" == "1" ]]; then
    ALLOWED_ROOTS="/var/tmp /shared/tmp"
else
    ALLOWED_ROOTS="/config/snmp"
fi
for d in "$INSTALL_DIR" "$OUTPUT_DIR"; do
    root_ok=false
    for r in $ALLOWED_ROOTS; do
        if is_within "$d" "$r" && [[ "$d" != "$r" ]]; then root_ok=true; break; fi
    done
    if [[ "$root_ok" != "true" ]]; then
        echo "  ✗ $d 不在允許的範圍內（允許: $ALLOWED_ROOTS）"
        if [[ "$TEST_MODE" != "1" ]]; then
            echo "    隔離測試請設 RPZ_INSTALL_TEST_MODE=1 並使用 /var/tmp 或 /shared/tmp 底下的路徑"
        fi
        exit 1
    fi
done
echo "  ✓ 兩個路徑都在允許的範圍內 ($ALLOWED_ROOTS)"

# ---------- 1b. 部署包完整性驗證 (R2-04) ----------

if [[ "$ALLOW_UNVERIFIED" == "yes-i-accept-an-unverified-package" ]]; then
    echo ""
    echo "  **************************************************************"
    echo "  ****  RPZ_ALLOW_UNVERIFIED_PACKAGE 已啟用                 ****"
    echo "  ****  跳過完整性驗證。安裝內容可能損毀或被修改。          ****"
    echo "  ****  這個選項只給 legacy 部署包使用，正式流程不應使用。  ****"
    echo "  **************************************************************"
    echo ""
    PKG_VERSION="unverified"
else
    if [[ ! -f "${SCRIPT_DIR}/VERSION" ]]; then
        echo "  ✗ 找不到 VERSION 檔案"
        echo "    這份 installer 只接受帶 VERSION 的部署包（1.2.1 起）。"
        echo "    若確定要安裝 legacy 包，設 RPZ_ALLOW_UNVERIFIED_PACKAGE=yes-i-accept-an-unverified-package"
        exit 1
    fi
    PKG_VERSION=$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")
    ver_ok=false
    for v in $SUPPORTED_VERSIONS; do
        [[ "$PKG_VERSION" == "$v" ]] && { ver_ok=true; break; }
    done
    if [[ "$ver_ok" != "true" ]]; then
        echo "  ✗ 部署包版本 '$PKG_VERSION' 不在此 installer 支援的版本內 ($SUPPORTED_VERSIONS)"
        exit 1
    fi
    echo "  ✓ 部署包版本: $PKG_VERSION"

    if ! command -v sha256sum >/dev/null 2>&1; then
        echo "  ✗ 系統沒有 sha256sum，無法驗證完整性"; exit 1
    fi
    if [[ ! -f "${SCRIPT_DIR}/SHA256SUMS" ]]; then
        echo "  ✗ 找不到 SHA256SUMS"; exit 1
    fi
    if ! ( cd "$SCRIPT_DIR" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
        echo "  ✗ SHA256SUMS 驗證失敗，部署包可能損毀或被修改"
        echo ""
        echo "  失敗的檔案："
        ( cd "$SCRIPT_DIR" && sha256sum -c SHA256SUMS 2>&1 | grep -v ': OK$' | sed 's/^/    /' ) || true
        exit 1
    fi
    echo "  ✓ SHA256SUMS 驗證通過（$(wc -l < "${SCRIPT_DIR}/SHA256SUMS" | tr -d ' ') 個檔案）"

    # 所有即將安裝的檔案都必須在 manifest 內，且不得有額外未列入的可安裝腳本
    extra=0
    while IFS= read -r f; do
        rel="./${f#"${SCRIPT_DIR}/"}"
        if ! grep -qF "  $rel" "${SCRIPT_DIR}/SHA256SUMS"; then
            echo "  ✗ 部署包內有未列入 manifest 的檔案: $rel"
            extra=$((extra + 1))
        fi
    done < <(find "$SCRIPT_DIR" -type f \( -name '*.sh' -o -name 'zonelist.txt' \) -print)
    if [[ "$extra" -ne 0 ]]; then
        echo "    拒絕安裝：manifest 未涵蓋全部可安裝檔案"
        exit 1
    fi
    echo "  ✓ 所有可安裝檔案都在 manifest 內，沒有額外檔案"
fi

# =============================================================================
# 步驟 2: 檢查系統環境
# =============================================================================

echo ""
echo "[2/7] 檢查系統環境..."

# 檢查是否為 root 或 admin
if [[ $EUID -ne 0 ]] && [[ "$(whoami)" != "admin" ]]; then
    echo "  ⚠ 警告: 建議使用 root 或 admin 執行"
fi

# 檢查必要指令
for cmd in bash awk sed grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✗ 缺少必要指令: $cmd"
        exit 1
    fi
    echo "  ✓ $cmd"
done

# =============================================================================
# 步驟 3: 檢查 F5 環境
# =============================================================================

echo ""
echo "[3/7] 檢查 F5 環境..."

F5_ENV=true

if command -v tmsh >/dev/null 2>&1; then
    echo "  ✓ tmsh 指令可用"
else
    echo "  ✗ tmsh 指令不存在"
    F5_ENV=false
fi

if command -v /usr/local/bin/dnsxdump >/dev/null 2>&1; then
    echo "  ✓ dnsxdump 指令可用"
else
    echo "  ⚠ dnsxdump 指令不存在 (需要 DNS Express)"
fi

if [[ "$F5_ENV" != "true" ]]; then
    echo ""
    echo "錯誤: 此腳本需要在 F5 BIG-IP 環境執行"
    exit 1
fi

# =============================================================================
# 步驟 4: 建立目錄結構
# =============================================================================

echo ""
echo "[4/7] 建立目錄結構..."

# 建立安裝目錄
mkdir -p "$INSTALL_DIR"/{scripts,config}
echo "  ✓ $INSTALL_DIR"

# 建立輸出目錄
mkdir -p "$OUTPUT_DIR"/{raw,parsed,final,.soa_cache}
echo "  ✓ $OUTPUT_DIR"

# =============================================================================
# 步驟 5: 複製檔案
# =============================================================================

echo ""
echo "[5/7] 複製檔案..."

# 複製 scripts
if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
    cp -f "${SCRIPT_DIR}/scripts"/*.sh "$INSTALL_DIR/scripts/"
    echo "  ✓ scripts/*.sh"
else
    echo "  ✗ 找不到 scripts 目錄"
    exit 1
fi

# 複製 config
if [[ -d "${SCRIPT_DIR}/config" ]]; then
    # zonelist.txt - 如果目標已存在則保留（避免覆蓋客戶配置）
    if [[ -f "$INSTALL_DIR/config/zonelist.txt" ]]; then
        echo "  ⚠ zonelist.txt 已存在，保留現有配置"
        cp -f "${SCRIPT_DIR}/config/zonelist.txt" "$INSTALL_DIR/config/zonelist.txt.new"
        echo "    新版本已存為 zonelist.txt.new"
    else
        cp -f "${SCRIPT_DIR}/config/zonelist.txt" "$INSTALL_DIR/config/"
        echo "  ✓ config/zonelist.txt"
    fi

    cp -f "${SCRIPT_DIR}/config/icall_setup_api.sh" "$INSTALL_DIR/config/"
    echo "  ✓ config/icall_setup_api.sh"
fi

# =============================================================================
# 步驟 6: 設定權限
# =============================================================================

echo ""
echo "[6/7] 設定執行權限..."

chmod +x "$INSTALL_DIR/scripts"/*.sh
chmod +x "$INSTALL_DIR/config"/*.sh
echo "  ✓ 執行權限已設定"

# =============================================================================
# 步驟 7: 驗證安裝
# =============================================================================

echo ""
echo "[7/7] 驗證安裝..."

# 檢查關鍵檔案
REQUIRED_FILES=(
    "$INSTALL_DIR/scripts/main.sh"
    "$INSTALL_DIR/scripts/utils.sh"
    "$INSTALL_DIR/scripts/parse_rpz.sh"
    "$INSTALL_DIR/config/zonelist.txt"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        echo "  ✓ $(basename "$f")"
    else
        echo "  ✗ 缺少: $f"
        ALL_OK=false
    fi
done

if [[ "$ALL_OK" != "true" ]]; then
    echo ""
    echo "錯誤: 安裝驗證失敗"
    exit 1
fi

# =============================================================================
# 完成
# =============================================================================

echo ""
echo "=========================================="
echo "  安裝完成！"
echo "=========================================="
echo ""
echo "安裝位置: $INSTALL_DIR"
echo "版本:     $PKG_VERSION"
echo ""
echo "----------------------------------------"
echo "下一步操作:"
echo "----------------------------------------"
echo ""
echo "1. 編輯 Zone 清單 (如需修改):"
echo "   vi $INSTALL_DIR/config/zonelist.txt"
echo ""
echo "2. 測試執行:"
echo "   bash $INSTALL_DIR/scripts/main.sh --force"
echo ""
echo "3. 設定 iCall 定期執行 (每 5 分鐘):"
echo "   bash $INSTALL_DIR/config/icall_setup_api.sh"
echo ""
echo "4. 檢查執行結果:"
echo "   ls -lh $OUTPUT_DIR/final/"
echo "   tmsh list ltm data-group external"
echo ""
echo "5. 監控日誌:"
echo "   tail -f /var/log/ltm | grep -E '(RPZ|rpz)'"
echo ""
