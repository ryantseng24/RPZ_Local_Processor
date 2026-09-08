#!/bin/bash
# =============================================================================
# check_source_consistency.sh
#
# 確保 tracked source、patch 內嵌內容、staging、deployment package 四者一致。
# 這是 CODE_REVIEW_20260821.md CR-03 的驗收 gate。
#
# 在 repo 根目錄執行。任一項不符回傳非零。
# 不需要 F5，可在開發機執行。
# =============================================================================

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }

FIXED="utils.sh parse_rpz.sh generate_datagroup.sh"
# 現行 patch。patches/patch1_sigpipe/ 底下只應該有這一個 patch 腳本。
# 舊版（v3）保留在 patches/archive/ 作審核紀錄，不算現行 patch（V4-04）。
PATCH=patches/patch1_sigpipe/rpz_patch_sigpipe_v4.sh

# 原版 v1.2 的 md5（歷史基準，用來確認 patch 的 MD5_ORIG 表沒有被誤改）
ORIG_utils_sh=3cab6cbca952f3780350e9882e5f7c11
ORIG_parse_rpz_sh=bbe45c6f79b56922388d4af7aa6e7583
ORIG_generate_datagroup_sh=35547d33ce109945d1ca17e8eb241e0a

md5f() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }

echo "=============================================================="
echo " check_source_consistency   $(date '+%F %T')"
echo "=============================================================="
echo

# ---------------------------------------------------------------- 1
echo "1. scripts/ 不得殘留 ls -t | head -1（排除註解）"
if grep -n 'ls -t.*| *head -1' scripts/*.sh 2>/dev/null | grep -v ':[0-9]*:[[:space:]]*#'; then
    bad "scripts/ 仍有 ls|head"
else
    ok "scripts/ 已無 ls|head"
fi

# ---------------------------------------------------------------- 2
echo "2. 所有 shell script 語法檢查"
n=0; e=0
for f in scripts/*.sh config/*.sh install.sh cleanup.sh package.sh patches/*/*.sh tests/*.sh tests/lab/*.sh; do
    [ -f "$f" ] || continue
    n=$((n+1))
    bash -n "$f" 2>/dev/null || { bad "語法錯誤: $f"; e=$((e+1)); }
done
[ "$e" -eq 0 ] && ok "$n 支腳本語法皆正確"

# ---------------------------------------------------------------- 3
echo "3. staging/scripts/ 與 scripts/ 一致"
if [ -d staging/scripts ]; then
    for f in $FIXED; do
        if [ "$(md5f "scripts/$f")" = "$(md5f "staging/scripts/$f")" ]; then
            ok "$f 一致"
        else
            bad "$f 不一致（scripts/ 與 staging/scripts/）"
        fi
    done
else
    ok "無 staging/ 目錄，略過"
fi

# ---------------------------------------------------------------- 4
echo "4. patch 內嵌內容與 scripts/ byte-for-byte 一致"
if [ -f "$PATCH" ]; then
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    # v4: 三個內嵌檔共用 __RPZ_EMBED__ delimiter，
    # 依 build_patch_v4.sh 的固定順序: utils, parse_rpz, generate_datagroup
    i=0
    for f in $FIXED; do
        i=$((i+1))
        awk -v want="$i" '
            /^cat <<'"'"'__RPZ_EMBED__'"'"'$/ { n++; inb=1; next }
            /^__RPZ_EMBED__$/                { inb=0; next }
            inb && n == want                 { print }
        ' "$PATCH" > "$tmp/$f"
        if [ ! -s "$tmp/$f" ]; then
            bad "$f 無法從 patch 抽出嵌入內容"
        elif [ "$(md5f "$tmp/$f")" = "$(md5f "scripts/$f")" ]; then
            ok "$f 嵌入內容一致"
        else
            bad "$f 嵌入內容與 scripts/ 不一致"
        fi
    done
else
    bad "找不到 $PATCH"
fi

# ---------------------------------------------------------------- 5
echo "5. patch 的 md5 表與實際檔案相符"
if [ -f "$PATCH" ]; then
    for f in $FIXED; do
        want_new=$(md5f "scripts/$f")
        eval "want_orig=\$ORIG_$(printf '%s' "$f" | tr '.' '_')"
        if grep -qF "NEW[${f}]=\"${want_new}\"" "$PATCH"; then
            ok "$f 的 NEW md5 相符"
        else
            bad "$f 的 NEW md5 與 scripts/$f 不符（應為 ${want_new}）"
        fi
        if grep -qF "ORIG[${f}]=\"${want_orig}\"" "$PATCH"; then
            ok "$f 的 ORIG md5 相符"
        else
            bad "$f 的 ORIG md5 不是原版 v1.2 的值（應為 ${want_orig}）"
        fi
    done
fi

# ---------------------------------------------------------------- 5b
echo "5b. patches/patch1_sigpipe/ 只有一個現行 patch 腳本"
np=$(ls -1 patches/patch1_sigpipe/rpz_patch_sigpipe_v*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$np" = 1 ] && [ -f "$PATCH" ]; then
    ok "只有 $(basename "$PATCH")"
else
    bad "patches/patch1_sigpipe/ 有 $np 個 patch 腳本，應該只保留現行版本"
    ls -1 patches/patch1_sigpipe/rpz_patch_sigpipe_v*.sh 2>/dev/null | sed 's/^/       /'
fi

# ---------------------------------------------------------------- 5c
echo "5c. patch 的 SHA-256 sidecar 與檔案一致"
if [ -f "${PATCH}.sha256" ]; then
    if ( cd "$(dirname "$PATCH")" && sha256sum -c "$(basename "$PATCH").sha256" >/dev/null 2>&1 ); then
        ok "patch sidecar 驗證通過"
    else
        bad "patch sidecar 驗證失敗（patch 改了但 sidecar 沒重算？）"
    fi
else
    bad "找不到 ${PATCH}.sha256"
fi

# ---------------------------------------------------------------- 6
echo "6. 必要工具存在（缺工具不可因兩邊空字串而假通過）"
tools_ok=1
for tool in md5sum sha256sum tar find sort; do
    if command -v "$tool" >/dev/null 2>&1; then :; else bad "缺少工具: $tool"; tools_ok=0; fi
done
[ "$tools_ok" -eq 1 ] && ok "md5sum / sha256sum / tar / find / sort 皆存在"

# ---------------------------------------------------------------- 7
echo "7. 最新 deployment package 與 tracked source 逐檔一致"
# 不用 `ls -t | head -1` 取最新 package：head 會提早關閉 pipe，
# 那正是本次要修的缺陷型態，測試工具不應重現（審核第 6.1 節）。
# 改用純 bash 迴圈依 mtime 挑選，與 production 的 find_newest_file 同型。
PKG=""
for _f in dist/rpz_local_processor_v*.tar.gz; do
    [ -f "$_f" ] || continue
    if [ -z "$PKG" ] || [ "$_f" -nt "$PKG" ]; then PKG="$_f"; fi
done
EXPECT_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' package.sh | sed -n '1p')
# 從 package.sh 解析同一份 PACKAGE_INPUTS 清單 (R2-06)
INPUTS=$(sed -n '/# PACKAGE_INPUTS_BEGIN/,/# PACKAGE_INPUTS_END/p' package.sh \
         | sed -n 's/^\([a-zA-Z][a-zA-Z0-9_./-]*\)$/\1/p')
# 空白分隔版本，供 case 比對使用（換行分隔的字串無法用 *" x "* 比對）
INPUTS_SP=" $(printf '%s ' $INPUTS)"

if [ -z "$EXPECT_VERSION" ]; then
    bad "無法從 package.sh 解析 VERSION"
else
    ok "package.sh 宣告的版本: $EXPECT_VERSION"
fi
if [ -z "$INPUTS" ]; then
    bad "無法從 package.sh 解析 PACKAGE_INPUTS"
else
    ok "PACKAGE_INPUTS 共 $(printf '%s\n' $INPUTS | wc -l | tr -d ' ') 項"
fi

if [ -z "$PKG" ]; then
    bad "dist/ 沒有 deployment package"
elif [ -z "$INPUTS" ] || [ -z "$EXPECT_VERSION" ]; then
    bad "清單或版本解析失敗，略過 package 比對"
else
    echo "     使用: $PKG"
    px=$(mktemp -d)
    if ! tar xzf "$PKG" -C "$px" 2>/dev/null; then
        bad "無法解開 $PKG"
    else
        # 只能有一個 root，且名稱要含預期版本
        nroot=$(ls -1 "$px" | wc -l | tr -d ' ')
        root=$(ls -1 "$px" | sed -n '1p')
        [ "$nroot" = 1 ] && ok "package 只有一個 root entry" || bad "package 有 $nroot 個 root entries"
        case "$root" in
            *"v${EXPECT_VERSION}_"*) ok "root 名稱含預期版本: $root" ;;
            *) bad "root 名稱與預期版本不符: $root（預期含 v${EXPECT_VERSION}_）" ;;
        esac

        # 逐檔比對 PACKAGE_INPUTS
        mism=0
        for rel in $INPUTS; do
            if [ ! -f "$px/$root/$rel" ]; then bad "package 缺少 $rel"; mism=$((mism+1)); continue; fi
            if [ ! -f "$rel" ]; then bad "tracked source 缺少 $rel"; mism=$((mism+1)); continue; fi
            if [ "$(md5f "$rel")" != "$(md5f "$px/$root/$rel")" ]; then
                bad "package 的 $rel 與 tracked source 不一致"; mism=$((mism+1))
            fi
        done
        [ "$mism" -eq 0 ] && ok "全部 $(printf '%s\n' $INPUTS | wc -l | tr -d ' ') 個 inputs 與 tracked source 一致"

        # package 內不得有 PACKAGE_INPUTS 之外的可安裝檔案
        extra=0
        while IFS= read -r f; do
            rel="${f#"$px/$root/"}"
            case "$INPUTS_SP" in *" $rel "*) continue ;; esac
            case "$rel" in VERSION|SHA256SUMS) continue ;; esac
            bad "package 有清單外的檔案: $rel"; extra=$((extra+1))
        done < <(find "$px/$root" -type f -print)
        [ "$extra" -eq 0 ] && ok "package 沒有清單外的檔案"

        # VERSION 精確值
        if [ -f "$px/$root/VERSION" ]; then
            pv=$(tr -d '[:space:]' < "$px/$root/VERSION")
            [ "$pv" = "$EXPECT_VERSION" ] && ok "package VERSION = $pv" \
                                          || bad "package VERSION=$pv，預期 $EXPECT_VERSION"
        else
            bad "package 缺少 VERSION"
        fi

        # 內層 manifest
        if [ -f "$px/$root/SHA256SUMS" ]; then
            if ( cd "$px/$root" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
                ok "內層 SHA256SUMS 驗證通過（$(wc -l < "$px/$root/SHA256SUMS" | tr -d ' ') 項）"
            else
                bad "內層 SHA256SUMS 驗證失敗"
            fi
        else
            bad "package 缺少 SHA256SUMS"
        fi

        # 不可含 tests/ 或 patches/ 或 OS 中繼資料
        if [ -d "$px/$root/tests" ] || [ -d "$px/$root/patches" ]; then
            bad "package 內含 tests/ 或 patches/"
        else
            ok "package 未包含 tests/ 與 patches/"
        fi
        META=$(find "$px/$root" \( -name '._*' -o -name '.DS_Store' \) -print)
        if [ -n "$META" ]; then
            bad "package 內含作業系統中繼資料檔案"
        else
            ok "package 無作業系統中繼資料檔案"
        fi
    fi
    rm -rf "$px"

    # ---------------------------------------------------------------- 8
    echo "8. 外層 .tar.gz.sha256"
    if [ -f "${PKG}.sha256" ]; then
        if ( cd "$(dirname "$PKG")" && sha256sum -c "$(basename "$PKG").sha256" >/dev/null 2>&1 ); then
            ok "外層 SHA-256 驗證通過"
        else
            bad "外層 SHA-256 驗證失敗"
        fi
    else
        bad "找不到 ${PKG}.sha256"
    fi
fi

# ---------------------------------------------------------------- 9
echo "9. Phase 1B patch 一致性"
P1B=patches/patch2_retention/rpz_patch_phase1b_v1.sh
ORIG_main_sh=0041c1d74e5b8514dea506608607b8c6

np1b=$(ls -1 patches/patch2_retention/rpz_patch_phase1b_v*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$np1b" = 1 ] && [ -f "$P1B" ]; then
    ok "只有一個 Phase 1B patch: $(basename "$P1B")"
else
    bad "patches/patch2_retention/ 有 $np1b 個 Phase 1B patch 腳本，應該只有一個"
fi

# payload 鏈: tracked main.sh 已前進到 Phase 1C 版，
# 1B patch 的內嵌對「1B 凍結版」驗證，不對 tracked source。
P1B_FROZEN_main=d1e1f688d939a5a5e87282605d0e3eed
if [ -f "$P1B" ]; then
    tmp1b=$(mktemp -d)
    awk '
        /^cat <<'"'"'__RPZ_EMBED__'"'"'$/ { n++; inb=1; next }
        /^__RPZ_EMBED__$/                { inb=0; next }
        inb && n == 1                    { print }
    ' "$P1B" > "$tmp1b/main.sh"
    if [ ! -s "$tmp1b/main.sh" ]; then
        bad "main.sh 無法從 Phase 1B patch 抽出嵌入內容"
    elif [ "$(md5f "$tmp1b/main.sh")" = "$P1B_FROZEN_main" ]; then
        ok "main.sh 嵌入內容 = 1B 凍結版"
    else
        bad "main.sh 嵌入內容與 1B 凍結版不一致（應為 ${P1B_FROZEN_main}）"
    fi
    rm -rf "$tmp1b"

    if grep -qF "NEW[main.sh]=\"${P1B_FROZEN_main}\"" "$P1B"; then
        ok "main.sh 的 NEW md5 = 1B 凍結版"
    else
        bad "main.sh 的 NEW md5 不是 1B 凍結版（應為 ${P1B_FROZEN_main}）"
    fi
    if grep -qF "ORIG[main.sh]=\"${ORIG_main_sh}\"" "$P1B"; then
        ok "main.sh 的 ORIG md5 相符"
    else
        bad "main.sh 的 ORIG md5 不是原版 v1.2 的值（應為 ${ORIG_main_sh}）"
    fi

    if [ -f "${P1B}.sha256" ]; then
        if ( cd "$(dirname "$P1B")" && sha256sum -c "$(basename "$P1B").sha256" >/dev/null 2>&1 ); then
            ok "Phase 1B patch sidecar 驗證通過"
        else
            bad "Phase 1B patch sidecar 驗證失敗（patch 改了但 sidecar 沒重算？）"
        fi
    else
        bad "找不到 ${P1B}.sha256"
    fi
fi

# ---------------------------------------------------------------- 10
echo "10. Phase 1C patch 一致性（payload 鏈尾，對 tracked source）"
P1C=patches/patch3_syslog/rpz_patch_phase1c_v1.sh
ORIG1C_main=d1e1f688d939a5a5e87282605d0e3eed
ORIG1C_ext=62aeaf053b08f3411fe530f33555c414
ORIG1C_upd=f8b038bc06df1c07050cd2922a91c5aa

np1c=$(ls -1 patches/patch3_syslog/rpz_patch_phase1c_v*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$np1c" = 1 ] && [ -f "$P1C" ]; then
    ok "只有一個 Phase 1C patch: $(basename "$P1C")"
else
    bad "patches/patch3_syslog/ 有 $np1c 個 Phase 1C patch 腳本，應該只有一個"
fi

if [ -f "$P1C" ]; then
    tmp1c=$(mktemp -d)
    i=0
    for f in main.sh extract_rpz.sh update_datagroup.sh; do
        i=$((i+1))
        awk -v want="$i" '
            /^cat <<'"'"'__RPZ_EMBED__'"'"'$/ { n++; inb=1; next }
            /^__RPZ_EMBED__$/                { inb=0; next }
            inb && n == want                 { print }
        ' "$P1C" > "$tmp1c/$f"
        if [ ! -s "$tmp1c/$f" ]; then
            bad "$f 無法從 Phase 1C patch 抽出嵌入內容"
        elif [ "$(md5f "$tmp1c/$f")" = "$(md5f "scripts/$f")" ]; then
            ok "$f 嵌入內容與 tracked source 一致"
        else
            bad "$f 嵌入內容與 scripts/$f 不一致"
        fi
        want_new=$(md5f "scripts/$f")
        if grep -qF "NEW[${f}]=\"${want_new}\"" "$P1C"; then
            ok "$f 的 NEW md5 相符"
        else
            bad "$f 的 NEW md5 不符（應為 ${want_new}）"
        fi
    done
    rm -rf "$tmp1c"
    grep -qF "ORIG[main.sh]=\"${ORIG1C_main}\"" "$P1C" && ok "main.sh 的 ORIG = 1B 凍結版" || bad "main.sh 的 ORIG 應為 1B 凍結版 ${ORIG1C_main}"
    grep -qF "ORIG[extract_rpz.sh]=\"${ORIG1C_ext}\"" "$P1C" && ok "extract_rpz.sh 的 ORIG = v1.2" || bad "extract_rpz.sh 的 ORIG 應為 ${ORIG1C_ext}"
    grep -qF "ORIG[update_datagroup.sh]=\"${ORIG1C_upd}\"" "$P1C" && ok "update_datagroup.sh 的 ORIG = v1.2" || bad "update_datagroup.sh 的 ORIG 應為 ${ORIG1C_upd}"

    if [ -f "${P1C}.sha256" ]; then
        if ( cd "$(dirname "$P1C")" && sha256sum -c "$(basename "$P1C").sha256" >/dev/null 2>&1 ); then
            ok "Phase 1C patch sidecar 驗證通過"
        else
            bad "Phase 1C patch sidecar 驗證失敗"
        fi
    else
        bad "找不到 ${P1C}.sha256"
    fi
fi

echo
echo "=============================================================="
printf ' PASS=%s  FAIL=%s\n' "$PASS" "$FAIL"
echo "=============================================================="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
