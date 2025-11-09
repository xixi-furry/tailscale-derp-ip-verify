#!/bin/sh
# generate-cert.sh - 为 IP 地址生成自签名证书

set -e

CERT_DIR="${DERP_CERT_DIR:-/app/certs}"
HOSTNAME="${DERP_HOSTNAME}"

if [ -z "${HOSTNAME}" ]; then
    echo "❌ 错误: 必须设置 DERP_HOSTNAME 环境变量"
    exit 1
fi

CERT_FILE="${CERT_DIR}/${HOSTNAME}.crt"
KEY_FILE="${CERT_DIR}/${HOSTNAME}.key"

# 如果证书已存在，显示指纹并退出
if [ -f "${CERT_FILE}" ] && [ -f "${KEY_FILE}" ]; then
    echo "✅ 证书已存在"
    echo ""
    FINGERPRINT=$(openssl x509 -in "${CERT_FILE}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
    echo "CertName: sha256-raw:${FINGERPRINT}"
    echo ""
    exit 0
fi

echo "🔐 生成自签名证书..."

mkdir -p "${CERT_DIR}"

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
    -nodes \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/CN=${HOSTNAME}" \
    -addext "subjectAltName=IP:${HOSTNAME}" 2>/dev/null

chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

echo "✅ 证书生成完成"
echo ""

FINGERPRINT=$(openssl x509 -in "${CERT_FILE}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')

echo "================================================"
echo "CertName: sha256-raw:${FINGERPRINT}"
echo "================================================"