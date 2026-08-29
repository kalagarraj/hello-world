# hello-rust

A minimal HTTP API in Rust, built with [axum](https://github.com/tokio-rs/axum) on Tokio.

## Endpoints

| Method | Path      | Response       |
| ------ | --------- | -------------- |
| `GET`  | `/`       | `Hello, Rust!` |
| `GET`  | `/health` | `ok`           |

> **The API is public by design.** There is no authentication, no API key and no
> IP allowlist — anyone who can reach the port can call it. Keep it that way only
> for endpoints that expose nothing sensitive.

## Configuration

| Variable   | Default | Purpose                       |
| ---------- | ------- | ----------------------------- |
| `PORT`     | `8080`  | Port the server binds to      |
| `RUST_LOG` | `info`  | `tracing-subscriber` filter   |

The server binds `0.0.0.0` so it is reachable from outside its container.

## Run locally

```bash
cargo run            # http://localhost:8080
cargo test           # unit tests for both routes
```

## Container

The Dockerfile lives in `infra/`, but the build context is the crate root so
that `Cargo.toml` and `src/` are visible to it.

```bash
./infra/build.sh                                   # -> hello-rust:latest
docker run --rm -p 8080:8080 hello-rust:latest
curl http://localhost:8080/
```

Or with compose:

```bash
docker compose -f infra/docker-compose.yml up --build
```

### How the image is put together

- **Multi-stage.** `rust:1-slim-bookworm` compiles; the runtime stage is
  `gcr.io/distroless/cc-debian12:nonroot` — no shell, no package manager.
- **Dependency caching.** Dependencies are compiled against a stub `main.rs`
  first, so editing `src/` does not rebuild the whole dependency graph.
- **Non-root.** Runs as uid 65532; compose adds `read_only` and
  `no-new-privileges`.
- **Small.** ~39 MB, with `strip`, `lto` and `panic = "abort"` in the release
  profile.

### Overriding base images

Both base images are build args, for networks that mirror registries:

```bash
BUILDER_IMAGE=mirror.gcr.io/library/rust:1-slim-bookworm ./infra/build.sh
```

### TLS-inspecting proxies

If your build network re-terminates TLS, drop the proxy's CA certificate into
`certs/` (`*.crt`) — the builder stage installs anything it finds there before
running cargo. The directory is empty by default and its contents are
gitignored.
