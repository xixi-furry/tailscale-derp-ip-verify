#!/bin/sh
# generate-cert.sh - 为 IP 地址生成自签名证书并输出指纹
# 用于无法使用 Let's Encrypt 的场景（如仅有 IP 地址的服务器）

set -e

CERT_DIR="${DERP_CERT_DIR:-/app/certs}"
HOSTNAME="${DERP_HOSTNAME}"

if [ -z "${HOSTNAME}" ]; then
    echo "❌ 错误: 必须设置 DERP_HOSTNAME 环境变量"
    echo ""
    echo "用法:"
    echo "  docker run --rm -v \$(pwd)/certs:/app/certs -e DERP_HOSTNAME=1.2.3.4 <image> generate-cert.sh"
    exit 1
fi

CERT_FILE="${CERT_DIR}/${HOSTNAME}.crt"
KEY_FILE="${CERT_DIR}/${HOSTNAME}.key"

# 如果证书已存在，显示指纹并退出
if [ -f "${CERT_FILE}" ] && [ -f "${KEY_FILE}" ]; then
    echo "✅ 证书已存在"
    echo ""
    echo "证书文件: ${CERT_FILE}"
    echo "密钥文件: ${KEY_FILE}"
    echo ""
    
    # 显示证书信息
    echo "证书信息:"
    openssl x509 -in "${CERT_FILE}" -noout -subject -dates
    echo ""
    
    # 计算并显示证书指纹
    echo "================================================"
    echo "📋 证书 SHA256 指纹（用于 Tailscale ACL）"
    echo "================================================"
    FINGERPRINT=$(openssl x509 -in "${CERT_FILE}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
    echo ""
    echo "  CertName: \"sha256-raw:${FINGERPRINT}\""
    echo ""
    echo "================================================"
    echo ""
    echo "ℹ️  如需重新生成，请先删除现有证书文件"
    exit 0
fi

echo "🔐 为 ${HOSTNAME} 生成自签名证书..."
echo ""

# 确保目录存在
mkdir -p "${CERT_DIR}"

# 生成自签名证书（有效期 10 年）
# -x509: 生成自签名证书
# -newkey rsa:4096: 使用 4096 位 RSA 密钥
# -sha256: 使用 SHA-256 哈希
# -days 3650: 有效期 10 年
# -nodes: 不加密私钥（Docker 环境中不需要密码）
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
    -nodes \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/CN=${HOSTNAME}" \
    -addext "subjectAltName=IP:${HOSTNAME}" 2>/dev/null

# 设置正确的权限
chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

echo "✅ 证书生成完成！"
echo ""
echo "证书文件: ${CERT_FILE}"
echo "密钥文件: ${KEY_FILE}"
echo ""

# 显示证书信息
echo "证书信息:"
openssl x509 -in "${CERT_FILE}" -noout -subject -dates
echo ""

# 计算并显示证书指纹
echo "================================================"
echo "📋 证书 SHA256 指纹（用于 Tailscale ACL）"
echo "================================================"
FINGERPRINT=$(openssl x509 -in "${CERT_FILE}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
echo ""
echo "  CertName: \"sha256-raw:${FINGERPRINT}\""
echo ""
echo "================================================"
echo ""
echo "⚠️  重要提示："
echo "  1. 请将上面的 CertName 添加到 Tailscale ACL 配置中"
echo "  2. 这是自签名证书，客户端需要配置正确的 CertName"
echo "  3. 证书有效期 10 年，过期后需要重新生成"
echo ""