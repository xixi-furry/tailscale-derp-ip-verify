# ===========================================
# 第一阶段：构建阶段
# ===========================================
FROM golang:1-alpine AS builder

WORKDIR /build

# 允许通过 build-arg 指定 GOPROXY（可选）
ARG GOPROXY=""

# 设置 Go 环境
ENV GO111MODULE=on \
    CGO_ENABLED=0

# 如果提供了 GOPROXY，则使用；否则使用默认
RUN if [ -n "$GOPROXY" ]; then \
        export GOPROXY=$GOPROXY; \
    fi && \
    apk add --no-cache git ca-certificates && \
    go install tailscale.com/cmd/derper@latest && \
    go install tailscale.com/cmd/tailscaled@latest && \
    go install tailscale.com/cmd/tailscale@latest

# ===========================================
# 第二阶段：运行阶段
# ===========================================
FROM alpine:latest

RUN apk add --no-cache \
        ca-certificates \
        tzdata \
        openssl && \
    mkdir -p /app/certs /var/lib/tailscale /var/run/tailscale

ENV TZ=Asia/Shanghai

COPY --from=builder /go/bin/derper /usr/local/bin/derper
COPY --from=builder /go/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=builder /go/bin/tailscale /usr/local/bin/tailscale

COPY generate-cert.sh /usr/local/bin/generate-cert.sh
COPY start-with-tailscale.sh /usr/local/bin/start-with-tailscale.sh
RUN chmod +x /usr/local/bin/generate-cert.sh \
             /usr/local/bin/start-with-tailscale.sh

WORKDIR /app

EXPOSE 443 3478/udp

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

CMD ["/usr/local/bin/start-with-tailscale.sh"]