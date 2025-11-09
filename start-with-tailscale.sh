#!/bin/sh
# start-with-tailscale.sh
# 启动脚本：根据配置决定是否启动 tailscaled 进行客户端验证

set -e

echo "================================================"
echo "  Tailscale DERP Server"
echo "  with Client Verification Support"
echo "================================================"
echo ""

# 检查必要的环境变量
if [ -z "${DERP_HOSTNAME}" ]; then
    echo "❌ 错误: 必须设置 DERP_HOSTNAME 环境变量"
    echo ""
    echo "示例: -e DERP_HOSTNAME=1.2.3.4"
    exit 1
fi

# 如果启用了验证但没有提供 Auth Key
if [ "${DERP_VERIFY_CLIENTS}" = "true" ] && [ -z "${TS_AUTHKEY}" ]; then
    echo "❌ 错误: 启用验证模式必须提供 TS_AUTHKEY"
    echo ""
    echo "获取 Auth Key:"
    echo "  1. 访问 https://login.tailscale.com/admin/settings/keys"
    echo "  2. 点击 'Generate auth key'"
    echo "  3. 勾选 'Reusable' 和添加 tag 'tag:derp-server'"
    echo "  4. 复制生成的 key（格式：tskey-auth-xxxxx）"
    echo ""
    exit 1
fi

# 创建必要的目录
mkdir -p /var/run/tailscale /var/lib/tailscale /app/certs

# ===========================================
# 显示证书信息
# ===========================================
if [ "${DERP_CERT_MODE}" = "manual" ] && [ -f "${DERP_CERT_DIR}/${DERP_HOSTNAME}.crt" ]; then
    echo "📋 证书信息:"
    FINGERPRINT=$(openssl x509 -in "${DERP_CERT_DIR}/${DERP_HOSTNAME}.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
    echo "  SHA256 指纹: sha256-raw:${FINGERPRINT}"
    echo ""
elif [ "${DERP_CERT_MODE}" = "manual" ]; then
    echo "⚠️  警告: 未找到证书文件"
    echo "  路径: ${DERP_CERT_DIR}/${DERP_HOSTNAME}.crt"
    echo ""
    echo "请先生成证书:"
    echo "  docker run --rm -v \$(pwd)/certs:/app/certs -e DERP_HOSTNAME=${DERP_HOSTNAME} <image> generate-cert.sh"
    echo ""
    exit 1
fi

# ===========================================
# 启动 tailscaled（如果需要验证）
# ===========================================
if [ "${DERP_VERIFY_CLIENTS}" = "true" ]; then
    echo "🔐 启用客户端验证模式"
    echo "📡 正在启动 tailscaled（仅用于验证）..."
    echo ""
    
    # 启动 tailscaled（后台运行）
    # --tun=userspace-networking: 使用用户空间网络（不需要 TUN 设备）
    # tailscaled 仅用于验证，不转发任何流量
    tailscaled \
        --state=${TS_STATE_DIR}/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock \
        --tun=userspace-networking \
        ${TS_EXTRA_ARGS} &
    
    TAILSCALED_PID=$!
    echo "✅ tailscaled 已启动 (PID: ${TAILSCALED_PID})"
    
    # 等待 tailscaled 启动
    echo "⏳ 等待 tailscaled 就绪..."
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if tailscale status >/dev/null 2>&1; then
            echo "✅ tailscaled 就绪"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "❌ tailscaled 启动超时"
            kill ${TAILSCALED_PID} 2>/dev/null || true
            exit 1
        fi
        sleep 2
    done
    
    # 检查 tailscaled 是否在运行
    if ! kill -0 ${TAILSCALED_PID} 2>/dev/null; then
        echo "❌ tailscaled 启动失败"
        exit 1
    fi
    
    # 使用 Auth Key 认证
    echo ""
    echo "🔑 使用 Auth Key 进行认证..."
    echo "💡 tailscaled 仅用于验证客户端，不会转发流量"
    echo ""
    
    # 最小化配置：只连接网络，不提供任何服务
    # --advertise-routes=: 不广播任何路由
    # --accept-routes=false: 不接受其他节点的路由
    # --accept-dns=false: 不使用 Tailscale DNS
    # --shields-up: 开启防火墙，拒绝入站连接
    # --ssh=false: 不开启 SSH
    # --netfilter-mode=off: 关闭网络过滤（不需要）
    if tailscale up \
        --authkey=${TS_AUTHKEY} \
        --hostname=derp-verifier \
        --advertise-tags=tag:derp-server \
        --advertise-routes= \
        --accept-routes=false \
        --accept-dns=false \
        --shields-up \
        --ssh=false \
        --netfilter-mode=off 2>&1; then
        echo ""
        echo "✅ Tailscale 认证成功"
    else
        echo ""
        echo "❌ Tailscale 认证失败"
        echo ""
        echo "可能的原因:"
        echo "  1. Auth Key 无效或已过期"
        echo "  2. tag:derp-server 未在 ACL 中定义"
        echo "  3. 网络连接问题"
        echo ""
        echo "解决方法:"
        echo "  1. 获取新的 Auth Key: https://login.tailscale.com/admin/settings/keys"
        echo "  2. 在 ACL 中添加: \"tagOwners\": {\"tag:derp-server\": [\"your-email@example.com\"]}"
        echo ""
        kill ${TAILSCALED_PID} 2>/dev/null || true
        exit 1
    fi
    
    # 显示 Tailscale 状态
    echo ""
    echo "📊 Tailscale 状态:"
    tailscale status || echo "⚠️  无法获取状态"
    echo ""
    echo "💡 提示: tailscaled 已连接到你的 tailnet"
    echo "💡 它仅用于验证客户端身份，不会转发任何流量"
    echo ""
    
    # 定义清理函数
    cleanup() {
        echo ""
        echo "🛑 正在关闭服务..."
        echo "📡 关闭 tailscaled..."
        kill ${TAILSCALED_PID} 2>/dev/null || true
        wait ${TAILSCALED_PID} 2>/dev/null || true
        echo "✅ 服务已停止"
        exit 0
    }
    
    # 捕获退出信号
    trap cleanup TERM INT
else
    echo "ℹ️  客户端验证已禁用"
    echo ""
    echo "⚠️  警告: 任何人都可以使用你的 DERP 服务器"
    echo "⚠️  强烈建议:"
    echo "     1. 使用防火墙限制访问（推荐）"
    echo "     2. 或启用验证模式（DERP_VERIFY_CLIENTS=true）"
    echo ""
fi

# ===========================================
# 启动 derper
# ===========================================
echo "🚀 正在启动 DERP 服务器..."
echo ""
echo "配置信息:"
echo "  - Hostname: ${DERP_HOSTNAME}"
echo "  - Address: ${DERP_ADDR}"
echo "  - Cert Mode: ${DERP_CERT_MODE}"
echo "  - HTTP Port: ${DERP_HTTP_PORT}"
echo "  - STUN Port: ${DERP_STUN_PORT}"
echo "  - Verify Clients: ${DERP_VERIFY_CLIENTS}"
echo ""

if [ "${DERP_VERIFY_CLIENTS}" = "true" ]; then
    echo "🔒 验证模式已启用"
    echo "✅ 只有你 tailnet 中的设备可以使用此 DERP 服务器"
    echo ""
fi

echo "================================================"
echo "  DERP Server is starting..."
echo "================================================"
echo ""

# 使用 exec 让 derper 成为主进程（接收信号）
exec derper \
    --hostname=${DERP_HOSTNAME} \
    --certmode=${DERP_CERT_MODE} \
    --certdir=${DERP_CERT_DIR} \
    --a=${DERP_ADDR} \
    --http-port=${DERP_HTTP_PORT} \
    --stun-port=${DERP_STUN_PORT} \
    --verify-clients=${DERP_VERIFY_CLIENTS}