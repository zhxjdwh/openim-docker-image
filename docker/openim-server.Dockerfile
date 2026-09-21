# syntax=docker/dockerfile:1
# OpenIM Server v3.8.3-patch.16 optimized build.
# Deviation from upstream tag Dockerfile:
#   1. golang:1.22 -> 1.25 (go.mod at this tag requires go >= 1.25; root cause of upstream publish failure)
#   2. Precompile the magefile into a standalone binary (mage -compile) so the container
#      needs NO Go toolchain and NO network at runtime (upstream downloads Go modules
#      from proxy.golang.org on every container start).
#   3. Final stage is plain alpine (~5MB base) instead of golang:alpine.

########## stage 1: build services + precompile mage targets ##########
FROM golang:1.25-alpine AS builder

ENV SERVER_DIR=/openim-server
WORKDIR $SERVER_DIR

COPY . .

RUN go mod download

RUN go install github.com/magefile/mage@v1.15.0

# pin gomake like the upstream Dockerfile does
RUN go get github.com/openimsdk/gomake@v0.0.15-alpha.5

# compile all services into _output
RUN mage build

# precompile the magefile (build/start/check targets) into a standalone binary
RUN mkdir -p /out && mage -compile /out/openim-mage

########## stage 2: runtime, no Go toolchain, zero runtime downloads ##########
FROM alpine:3.21

ENV SERVER_DIR=/openim-server
WORKDIR $SERVER_DIR

RUN apk add --no-cache bash ca-certificates tzdata curl

COPY --from=builder $SERVER_DIR/_output $SERVER_DIR/_output
COPY --from=builder $SERVER_DIR/config $SERVER_DIR/config
COPY --from=builder $SERVER_DIR/start-config.yml $SERVER_DIR/
COPY --from=builder /out/openim-mage /usr/local/bin/openim-mage

# compat shim: `mage <target>` inside the container runs the precompiled binary
RUN printf '#!/bin/sh\nexec /usr/local/bin/openim-mage "$@"\n' > /usr/local/bin/mage \
    && chmod +x /usr/local/bin/mage

ENTRYPOINT ["sh", "-c", "openim-mage start && tail -f /dev/null"]
