#!/usr/bin/env bash
#
# 生成「Quick」自签名代码签名证书（连同私钥）。
#
# ⚠️  这是**一次性**操作。证书生成后：
#   · 指纹（leaf hash）会写进每个 Release 的 designated requirement；
#   · TCC（屏幕录制 / 辅助功能）按「bundle id + certificate leaf」认 App；
#   · 再生成一张新证书 = 换身份 = 用户升级后要重新授权。
#
# 所以：本机已经有「Quick」身份时，本脚本**直接拒绝**，请改用
#   bash Scripts/export-signing-cert.sh
# 把现有证书导出给 CI。
#
# 用法：bash Scripts/generate-signing-cert.sh
#
# 产出（默认写到 ~/.config/quick/，不进 git）：
#   quick-signing.p12           证书 + 私钥
#   quick-signing.p12.password  p12 密码
#   quick-signing.p12.base64    给 GitHub Secret QUICK_CERT_P12_BASE64
#
# @author ygw
set -euo pipefail

IDENTITY_NAME="Quick"
OUT_DIR="${QUICK_CERT_OUT_DIR:-$HOME/.config/quick}"
DAYS="${QUICK_CERT_DAYS:-3650}"   # 默认 10 年
COMMON_NAME="$IDENTITY_NAME"

if security find-identity -p codesigning 2>/dev/null | grep "\"${IDENTITY_NAME}\"" >/dev/null; then
    echo "已经存在代码签名身份「${IDENTITY_NAME}」，拒绝重新生成。" >&2
    echo "" >&2
    echo "重新生成会换掉 certificate leaf，用户升级后屏幕录制授权会丢。" >&2
    echo "要把现有证书交给 CI，请跑：" >&2
    echo "  bash Scripts/export-signing-cert.sh" >&2
    echo "" >&2
    security find-identity -p codesigning 2>/dev/null | grep "\"${IDENTITY_NAME}\"" >&2 || true
    exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

TMP="$(mktemp -d -t quick-cert)"
trap 'rm -rf "$TMP"' EXIT

P12_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)"
KEYCHAIN="$TMP/quick-gen.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"

echo "==> 1/4 生成自签名证书（CN=${COMMON_NAME}，${DAYS} 天）"
# 专用临时钥匙串：避免污染 login，也方便只导出这一份身份。
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

# openssl 出一对密钥 + 自签证书，再导进钥匙串。
openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$TMP/quick.key" \
    -out "$TMP/quick.csr" \
    -subj "/CN=${COMMON_NAME}/OU=Local/C=CN" \
    >/dev/null 2>&1

openssl x509 -req -days "$DAYS" \
    -in "$TMP/quick.csr" \
    -signkey "$TMP/quick.key" \
    -out "$TMP/quick.crt" \
    -extfile <(printf "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n") \
    >/dev/null 2>&1

openssl pkcs12 -export \
    -inkey "$TMP/quick.key" \
    -in "$TMP/quick.crt" \
    -out "$TMP/quick.p12" \
    -name "$IDENTITY_NAME" \
    -passout "pass:${P12_PASSWORD}" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 \
    >/dev/null 2>&1

echo "==> 2/4 导入登录钥匙串（本机 codesign / Xcode 要用）"
# 也放进 login，方便日常 Debug / 本地 Release。
LOGIN_KC="$(security default-keychain | tr -d '" ')"
security import "$TMP/quick.p12" -k "$LOGIN_KC" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# 允许 codesign 静默用私钥（否则每次构建弹「要使用钥匙串」）。
#
# **不要写 `-k ""`**：`-k` 已废弃，传空密码在带密码的登录钥匙串上必定失败；失败又被
# `|| true` 吞掉，于是证书装好了、构建时却卡在钥匙串授权框上。这里不带 `-k`，
# 让 `security` 就地提示输入登录钥匙串密码（本脚本是一次性交互脚本，可以提示）。
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$LOGIN_KC"; then
    echo "    ⚠️  未能自动授权 codesign 使用私钥。" >&2
    echo "        首次构建会弹一次钥匙串授权框，选「始终允许」并输入登录密码即可，之后不再弹。" >&2
fi

echo "==> 3/4 写出 p12 / 密码 / base64 → ${OUT_DIR}"
cp "$TMP/quick.p12" "$OUT_DIR/quick-signing.p12"
printf '%s' "$P12_PASSWORD" > "$OUT_DIR/quick-signing.p12.password"
base64 -i "$OUT_DIR/quick-signing.p12" | tr -d '\n' > "$OUT_DIR/quick-signing.p12.base64"
chmod 600 "$OUT_DIR/quick-signing.p12" \
    "$OUT_DIR/quick-signing.p12.password" \
    "$OUT_DIR/quick-signing.p12.base64"

FINGERPRINT="$(openssl x509 -in "$TMP/quick.crt" -noout -fingerprint -sha1 | sed 's/^.*=//')"

echo "==> 4/4 校验"
security find-identity -p codesigning 2>/dev/null | grep "\"${IDENTITY_NAME}\"" \
    || { echo "导入后找不到「${IDENTITY_NAME}」" >&2; exit 1; }

cat <<EOF

完成。这张证书从现在起就是 Quick 的长期签名身份，**不要再跑本脚本**。

  指纹（SHA-1）: ${FINGERPRINT}
  身份名称      : ${IDENTITY_NAME}
  文件目录      : ${OUT_DIR}/
    quick-signing.p12
    quick-signing.p12.password
    quick-signing.p12.base64

下一步（一次性，配到 GitHub）：

  gh secret set QUICK_CERT_P12_BASE64 < ${OUT_DIR}/quick-signing.p12.base64
  gh secret set QUICK_CERT_P12_PASSWORD < ${OUT_DIR}/quick-signing.p12.password

或仓库网页：Settings → Secrets and variables → Actions → New repository secret

详见 AGENTS.md「发布」一节。
EOF
