#!/bin/bash
# 建一个自签的代码签名证书「Reverie Local」放进登录钥匙串，让每次编译的签名身份都一样，
# 这样「辅助功能」「自动化」授权不会因为重编而失效。中途系统会弹一次密码框（信任证书）。
# 也可以在「钥匙串访问 → 证书助理 → 创建证书」里手动建，类型选「代码签名」，名字填 Reverie Local。
set -e
NAME=${REVERIE_SIGN_IDENTITY:-Reverie Local}
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then echo "已有证书 $NAME"; exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout pass:reverie
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P reverie -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# 信任它做代码签名（这一步会弹密码框）。
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
security find-identity -p codesigning | grep -q "$NAME" && echo "证书 $NAME 已就绪" || { echo "证书没建成，试试钥匙串访问里手动建" >&2; exit 1; }
