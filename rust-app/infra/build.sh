#!/usr/bin/env bash
# Build the hello-rust container image.
# The Dockerfile lives in infra/ but the build context is the crate root.
set -euo pipefail

IMAGE="${IMAGE:-hello-rust}"
TAG="${TAG:-latest}"

cd "$(dirname "$0")/.."

build_args=()
# Set BUILDER_IMAGE / RUNTIME_IMAGE to pull bases from a mirror instead of
# the defaults baked into the Dockerfile.
[[ -n "${BUILDER_IMAGE:-}" ]] && build_args+=(--build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}")
[[ -n "${RUNTIME_IMAGE:-}" ]] && build_args+=(--build-arg "RUNTIME_IMAGE=${RUNTIME_IMAGE}")

docker build -f infra/Dockerfile "${build_args[@]}" -t "${IMAGE}:${TAG}" .

echo "Built ${IMAGE}:${TAG}"
echo "Run with: docker run --rm -p 8080:8080 ${IMAGE}:${TAG}"
