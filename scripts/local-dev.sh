#!/usr/bin/env bash
# Build the image and run it locally on http://localhost:8000
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="devops-challenge:local"

echo ">>> Building ${TAG}"
docker build \
  --build-arg APP_VERSION=local \
  --build-arg GIT_SHA="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo none)" \
  -t "${TAG}" "${ROOT}"

echo ">>> Running on http://localhost:8000  (Ctrl-C to stop)"
docker run --rm -p 8000:8000 "${TAG}"
