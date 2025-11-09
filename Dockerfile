# ===========================================
# 第一阶段：构建阶段
# ===========================================
# 使用最新的 Go 1.x alpine 镜像作为构建环境
# 1-alpine 表示：使用 Go 1 系列的最新版本
# 例如：现在是 1.25.x，以后 1.26、1.27 出来会自动更新
FROM golang:1-alpine AS builder

# 设置工作目录
WORKDIR /build

# 设置 Go 代理 - 国内加速
# 使用多个代理，按顺序尝试
ENV GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.com.cn,direct \
    GO111MODULE=on \
    CGO_ENABLED=0

# 安装构建依赖
# git: go install 需要用到
# ca-certificates: HTTPS 请求需要的证书
RUN apk add --no-cache \
        git \
        ca-certificates

# 编译 derper、tailscaled 和 tailscale CLI
# 同时安装三个工具，用于完整的验证功能
RUN go install tailscale.com/cmd/derper@latest && \
    go install tailscale.com/cmd/tailscaled@latest && \
    go install tailscale.com/cmd/tailscale@latest

# ===========================================
# 第二阶段：运行阶段
# ===========================================
# 使用更小的 alpine 镜像作为运行环境
# 这样最终镜像会很小，只包含必要的运行文件
FROM alpine:latest

# 安装运行时依赖
# ca-certificates: HTTPS 和证书验证需要
# tzdata: 时区数据，让日志时间正确
# openssl: 用于生成自签名证书和计算指纹
RUN apk add --no-cache \
        ca-certificates \
        tzdata \
        openssl && \
    mkdir -p /app/certs /var/lib/tailscale /var/run/tailscale

# 设置时区为上海
ENV TZ=Asia/Shanghai

# 从构建阶段复制所有二进制文件
COPY --from=builder /go/bin/derper /usr/local/bin/derper
COPY --from=builder /go/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=builder /go/bin/tailscale /usr/local/bin/tailscale

# 复制辅助脚本
COPY generate-cert.sh /usr/local/bin/generate-cert.sh
COPY start-with-tailscale.sh /usr/local/bin/start-with-tailscale.sh
COPY get-cert-fingerprint.sh /usr/local/bin/get-cert-fingerprint.sh
RUN chmod +x /usr/local/bin/generate-cert.sh \
             /usr/local/bin/start-with-tailscale.sh \
             /usr/local/bin/get-cert-fingerprint.sh

# 设置工作目录
WORKDIR /app

# 暴露端口
# 443: HTTPS (DERP 主要服务端口)
# 3478/udp: STUN 端口
EXPOSE 443 3478/udp

# 设置默认环境变量
# 这些可以在 docker run 时通过 -e 参数覆盖
ENV DERP_ADDR=:443 \
    DERP_HTTP_PORT=-1 \
    DERP_STUN_PORT=3478 \
    DERP_CERT_DIR=/app/certs \
    DERP_CERT_MODE=manual \
    DERP_HOSTNAME="" \
    DERP_VERIFY_CLIENTS=true \
    TS_AUTHKEY="" \
    TS_STATE_DIR=/var/lib/tailscale \
    TS_EXTRA_ARGS=""

# 使用启动脚本
# 根据配置决定是否启动 tailscaled 进行客户端验证
CMD ["/usr/local/bin/start-with-tailscale.sh"]