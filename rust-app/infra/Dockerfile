# Multi-stage build for the hello-rust API.
#
# Build from the crate root (the Dockerfile lives in infra/):
#   docker build -f infra/Dockerfile -t hello-rust:latest .
#
# The base images are overridable so the build works behind a registry mirror:
#   --build-arg BUILDER_IMAGE=mirror.gcr.io/library/rust:1-slim-bookworm

ARG BUILDER_IMAGE=rust:1-slim-bookworm
ARG RUNTIME_IMAGE=gcr.io/distroless/cc-debian12:nonroot

# ---- Build stage -------------------------------------------------------------
FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app

# Optional trust anchors for networks that inspect TLS (corporate proxies, CI
# egress gateways). Drop .crt files into certs/ at the crate root; the
# directory is empty by default and this layer is then a no-op.
COPY certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Compile dependencies against a stub binary first, so editing src/ does not
# invalidate the (slow) dependency layer.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src \
    && echo 'fn main() {}' > src/main.rs \
    && cargo build --release \
    && rm -rf src

COPY src ./src
# Bust the stub's mtime so cargo rebuilds the real binary.
RUN touch src/main.rs && cargo build --release

# ---- Runtime stage -----------------------------------------------------------
# Distroless: no shell, no package manager, minimal attack surface.
FROM ${RUNTIME_IMAGE}

WORKDIR /app
COPY --from=builder /app/target/release/hello-rust /app/hello-rust

ENV PORT=8080
EXPOSE 8080

# uid 65532, provided by the distroless :nonroot tag.
USER nonroot
ENTRYPOINT ["/app/hello-rust"]
