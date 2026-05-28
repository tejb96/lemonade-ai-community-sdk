# lemonade-server Workshop SDK

Run Lemonade Server inside Canonical Workshops with persistent model caching, GPU acceleration support, and an OpenAI-compatible local inference API.

This community SDK packages [Lemonade Server](https://lemonade-server.ai/) for the Ubuntu Workshop ecosystem using reproducible upstream binaries instead of PPAs or runtime repository configuration.

> Experimental but functional. Tested on Ubuntu Server 26.04 (amd64) using CPU fallback inference.

---

# Features

- Reproducible SDK packaging using upstream Lemonade embeddable tarballs
- OpenAI-compatible REST API exposed through Workshop tunnels
- Persistent model and Hugging Face caches across refreshes
- Automatic backend selection for ROCm, Vulkan, Ryzen AI, and CPU fallback
- User-level `lemond` systemd service management
- Compatible with local LLM workflows using Qwen, Llama, Gemma, and GGUF models
- No Launchpad or PPA dependency during workshop installation

---

# Quick Start

## 1. Build the SDK locally

```bash
sdkcraft try
```

This packs the SDK and stages it into the local Workshop "try area" as:

```text
try-lemonade-server-workshop
```

---

## 2. Create a workshop

Create a `workshop.yaml`:

```yaml
name: ai-dev
base: ubuntu@24.04

sdks:
  - name: try-lemonade-server-workshop

  - name: system
    plugs:
      lemonade-api:
        interface: tunnel
        endpoint: localhost:13305

actions:
  status: lemonade status
  pull: lemonade pull "$@"
  list: lemonade list
```

Launch the workshop:

```bash
workshop launch --verbose --wait-on-error
workshop info
```

Expected status:

```text
ready
```

---

## 3. Pull and run a model

```bash
workshop run ai-dev -- pull Qwen3-0.6B-GGUF
workshop run ai-dev -- list
workshop exec ai-dev -- lemonade run Qwen3-0.6B-GGUF
```

The Lemonade API and web UI will be available from the host at:

```text
http://localhost:13305
```

---

# Persistence

The SDK persists downloaded models and backend binaries using Workshop mount plugs.

| Mount               | Purpose                                            |
| ------------------- | -------------------------------------------------- |
| `model-cache`       | Lemonade config, downloaded backends, local models |
| `huggingface-cache` | Hugging Face model weights and cache               |

This allows models and configuration to survive workshop refreshes automatically.

---

# GPU and Backend Support

`lemond` automatically selects the best available backend at startup.

| Hardware           | Typical Backend   |
| ------------------ | ----------------- |
| AMD GPU            | `rocm`            |
| NVIDIA / Intel GPU | `vulkan`          |
| AMD Ryzen AI NPU   | `ryzenai` / `flm` |
| CPU fallback       | `cpu`             |

You can override backend selection manually:

```bash
workshop exec ai-dev -- lemonade config set llamacpp.backend=vulkan
```

---

# Configuration

The SDK creates a default `config.json` on first launch only. Subsequent refreshes preserve user modifications.

Examples:

```bash
# Increase context window
workshop exec ai-dev -- lemonade config set ctx_size=8192

# Pin a specific Vulkan backend build
workshop exec ai-dev -- lemonade config set llamacpp.vulkan_bin=b8664

# Expose the API on the network
workshop exec ai-dev -- lemonade config set host=0.0.0.0
```

Configuration persists automatically because it lives inside the mounted cache directory.

---

# Example Workflow

```bash
# Launch workshop
workshop launch ai-dev

# Pull a model
workshop run ai-dev -- pull Qwen3-0.6B-GGUF

# Verify health endpoint
curl http://127.0.0.1:13305/api/v1/health

# Refresh workshop
workshop refresh ai-dev

# Confirm model persisted
workshop exec ai-dev -- lemonade list
```

---

# SDK Architecture

## Directory Layout

```text
lemonade-server/
├── VERSION                    # upstream Lemonade release (source of truth)
├── sdkcraft.yaml
├── renovate.json
├── scripts/
│   ├── sync-version.sh           # copies VERSION → sdkcraft.yaml version:
│   └── prepare-workshop-snap.sh  # snap download workshop → tests/workshop_<rev>.snap
├── service/
│   └── lemond.service
├── hooks/
│   ├── setup-base
│   ├── setup-project
│   └── check-health
├── examples/
│   └── workshop.yaml
└── tests/
    ├── spread.yaml
    ├── workshop.yaml
    └── main/
        ├── launch/task.yaml
        ├── api/task.yaml
        ├── refresh/task.yaml
        └── cli/task.yaml
```

---

## Hooks

| Hook            | Runs As       | Purpose                                      |
| --------------- | ------------- | -------------------------------------------- |
| `setup-base`    | root          | Install runtime dependencies and environment |
| `setup-project` | workshop user | Configure Lemonade and start `lemond`        |
| `check-health`  | root          | Validate API readiness                       |

---

## Tunnel Slot

The SDK exposes the Lemonade API using a Workshop tunnel slot:

| Slot           | Port    |
| -------------- | ------- |
| `lemonade-api` | `13305` |

Consumers attach this slot through the `system` SDK using a matching tunnel plug.

---

# Networking Notes

Workshop containers run on the `workshopbr0` bridge.

On systems using Docker and/or restrictive UFW policies, outbound IPv4 traffic may be blocked, causing:

- `apt-get update` hangs
- failed model downloads
- stalled backend downloads

Possible fixes:

```bash
sudo ufw default allow routed
sudo ufw reload
```

Or:

```bash
sudo ufw allow in on workshopbr0
sudo ufw route allow in on workshopbr0
sudo ufw route allow out on workshopbr0
sudo ufw reload
```

If Docker's `DOCKER-USER` chain is interfering:

```bash
sudo nft insert rule ip filter DOCKER-USER iifname workshopbr0 accept
sudo nft insert rule ip filter DOCKER-USER oifname workshopbr0 \
    ct state related,established accept
```

---

# Verifying a Local Build

```bash
# Keep sdkcraft.yaml version in sync with upstream (also run before pack/try/test)
./scripts/sync-version.sh

# Build and stage locally
sdkcraft clean && sdkcraft try

# Create test workshop
mkdir -p /tmp/ai-dev
cp examples/workshop.yaml /tmp/ai-dev/
cd /tmp/ai-dev

# Launch
workshop launch ai-dev --verbose --wait-on-error

# Verify API
curl -sf http://127.0.0.1:13305/api/v1/health

# Pull model
workshop run ai-dev -- pull Qwen3-0.6B-GGUF

# Refresh workshop
workshop refresh ai-dev

# Verify persistence
workshop exec ai-dev -- bash -c 'lemonade list | grep Qwen3-0.6B-GGUF'
```

The same steps are automated as spread tests under `tests/main/` (LXD backend in `tests/spread.yaml`). On a machine with Workshop and LXD:

```bash
./scripts/sync-version.sh
./scripts/prepare-workshop-snap.sh   # once per clone / workshop revision
sdkcraft test -v
```

Keep the downloaded file as `tests/workshop_<rev>.snap` (do not rename to `workshop.snap`).

---

# CI

Pull requests and pushes to `main` run [`.github/workflows/build.yml`](.github/workflows/build.yml): **`sdkcraft pack` only** on an `ubuntu-24.04` runner with LXD. Spread tests are not run in GitHub Actions (Workshop install and store auth are kept on the build server).

Run the full spread suite on your **build server** before merging:

```bash
./scripts/sync-version.sh
./scripts/prepare-workshop-snap.sh
sdkcraft test -v
```

Upstream version bumps are proposed by [Renovate](renovate.json) from [lemonade-sdk/lemonade](https://github.com/lemonade-sdk/lemonade) releases (updates `VERSION` and the `version:` field in `sdkcraft.yaml`).

Store upload on merge is stubbed in [`.github/workflows/release.yml`](.github/workflows/release.yml) until the SDK is registered (Phase 4). The Workshop SDK Store name is `lemonade-server-workshop` (`lemonade-server` is reserved on the Store by another publisher).

---

# Platforms

Current support:

- Ubuntu Server 26.04
- amd64

arm64 support will return once upstream Linux arm64 binaries are available.

---

# Security Notes

By default, Lemonade binds to:

```text
localhost
```

To expose the API externally:

```bash
workshop exec ai-dev -- lemonade config set host=0.0.0.0
```

If exposing beyond local development, configure:

```text
LEMONADE_API_KEY
```

See the official Lemonade documentation for production hardening guidance.

---

# License

Apache-2.0, matching Lemonade Server upstream.
