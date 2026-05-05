# syntax=docker/dockerfile:1.7
# Two-stage Go build: tiny static binary in a distroless final image.

# --- Stage 1: build ---
FROM golang:1.23-alpine AS builder

ARG APP_VERSION=dev
ARG GIT_SHA=unknown

WORKDIR /src
# Cache-friendly: copy go.mod first, then sources.
COPY app/go.mod ./
RUN go mod download
COPY app/ ./

# Static, stripped binary; inject build metadata via -ldflags.
ENV CGO_ENABLED=0 GOOS=linux
RUN go build -trimpath \
      -ldflags="-s -w -X main.appVersion=${APP_VERSION} -X main.gitSHA=${GIT_SHA}" \
      -o /out/server .

# --- Stage 2: runtime ---
# Distroless: no shell, no package manager, no root. Smallest credible attack surface.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/server /server

EXPOSE 8000
USER nonroot:nonroot

ENTRYPOINT ["/server"]
