FROM caddy:2-builder-alpine AS builder

ENV GOTOOLCHAIN=go1.27.3
# Replaces xcaddy's default "-ldflags '-w -s' -trimpath -tags ...". Keeping
# the symbol table (-w drops only DWARF) lets govulncheck see which packages
# the binary links; on a stripped binary it flags every vulnerable package of
# each dependency module.
ENV XCADDY_GO_BUILD_FLAGS="-ldflags=-w -trimpath -tags=nobadger,nomysql,nopgx"
# CI passes the Caddy release it publishes; local builds take the newest.
ARG CADDY_VERSION=latest

ADD . .

# Each --replace pins a dependency to the patched release the latest Caddy does
# not require yet. A replace fixes the exact version, so remove it once Caddy's
# go.mod requires that version or newer, or it will downgrade the dependency.
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && \
    xcaddy build "$CADDY_VERSION" \
    --output /usr/bin/caddy \
    --replace "github.com/klauspost/compress=github.com/klauspost/compress@v1.20.2" \
    --with "github.com/caddy-dns/cloudflare=."

FROM alpine:3.22

RUN apk add --no-cache \
    ca-certificates \
    libcap \
    mailcap

RUN set -eux; \
    mkdir -p \
        /config/caddy \
        /data/caddy \
        /etc/caddy \
        /usr/share/caddy \
    ; \
    wget -O /etc/caddy/Caddyfile "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/config/Caddyfile"; \
    wget -O /usr/share/caddy/index.html "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/welcome/index.html"

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

RUN setcap cap_net_bind_service=+ep /usr/bin/caddy; \
    chmod +x /usr/bin/caddy; \
    caddy version

LABEL org.opencontainers.image.title="Caddy with Cloudflare DNS module"
LABEL org.opencontainers.image.description="Caddy web server image with the caddy-dns/cloudflare DNS provider module baked in"
LABEL org.opencontainers.image.url=https://caddyserver.com
LABEL org.opencontainers.image.documentation=https://caddyserver.com/docs
LABEL org.opencontainers.image.licenses=Apache-2.0
LABEL org.opencontainers.image.source="https://github.com/0xmichalis/caddy-cloudflare"

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

WORKDIR /srv

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
