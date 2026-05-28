# lemonade-server Workshop SDK

A community [Canonical Workshop](https://documentation.ubuntu.com/canonical-workshop/latest/) SDK that installs and manages [Lemonade Server](https://lemonade-server.ai/) — a lightweight, open-source local LLM inference server — inside a workshop environment.

> **Status: Phase 2.1 (reproducible upstream packaging, verified end-to-end).** Lemonade is installed from the upstream embeddable tarball — no PPA dependency, no in-container Launchpad calls. Acceptance criteria (pack, launch, health, model pull, refresh persistence) all pass on a clean checkout.

## What this SDK provides

- **Lemonade** installed from the upstream `lemonade-embeddable-<version>-ubuntu-x64.tar.gz`, packaged as a deterministic SDK part — no PPA, no apt repository configuration at install time.
- **lemond** running as a systemd user service, auto-started on workshop launch.
- Backend binaries (llama.cpp, whisper.cpp, sd.cpp, kokoro, etc.) are downloaded by `lemond` from upstream GitHub on first use; downloads land inside `model-cache` and persist across refreshes.
- A persistent **model cache** via the `model-cache` mount plug.
- A persistent **Hugging Face cache** via the `huggingface-cache` mount plug — Lemonade's default `models_dir: "auto"` resolves under `~/.cache/huggingface`, so this is what actually keeps downloaded weights across refreshes.
- An OpenAI-compatible REST API on port 13305, exposed through a `tunnel` slot named `lemonade-api`.

## Quick start

### 1. Build and try locally

```bash
# Pack the SDK and copy the resulting artifacts into your local "try area".
# This is the local equivalent of publishing to the SDK Store.
sdkcraft try
```

`sdkcraft try` packs `lemonade-server_amd64_ubuntu@24.04.sdk` into the try area and makes it referenceable as `try-lemonade-server` from any workshop definition.

### 2. Launch a workshop that uses it

Drop a `workshop.yaml` into your project directory (the layout below mirrors `examples/workshop.yaml`):

```yaml
name: ai-dev
base: ubuntu@24.04
sdks:
  - name: try-lemonade-server
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

Then launch:

```bash
workshop launch --verbose --wait-on-error
workshop info        # status: ready
```

### 3. Pull a model and chat

```bash
workshop run ai-dev -- pull Qwen3-0.6B-GGUF
workshop run ai-dev -- list
workshop exec ai-dev -- lemonade run Qwen3-0.6B-GGUF
# The Lemonade web UI is reachable from the host at http://localhost:13305
```

> First model pulls and any `*_bin: latest` resolution require outbound HTTPS to `github.com` and the Hugging Face Hub from inside the workshop. The SDK install itself does not need internet — the embeddable tarball is fetched once at `sdkcraft pack` time on the build machine.

## Using the example workshop definition

```bash
cp examples/workshop.yaml workshop.yaml
workshop launch
```

The shipped example targets `latest/edge` from the SDK Store. Until this SDK is published, replace the SDK reference with `try-lemonade-server` (the comment in the example file shows exactly how).

## SDK internals

### Directory layout

```
lemonade-server/
├── sdkcraft.yaml             # SDK definition (lemonade + service-files parts)
├── service/
│   └── lemond.service        # systemd user unit (shipped as a part)
├── hooks/
│   ├── setup-base            # root: install runtime deps (ca-certificates, curl), set PATH and HF env
│   ├── setup-project         # workshop user: write minimal config.json, start lemond as user service
│   └── check-health          # single-shot probe of /api/v1/health; defers retry to Workshop
├── tests/
│   └── spread/
│       └── spread.yaml       # placeholder (real tests land in Phase 3)
└── examples/
    └── workshop.yaml         # ready-to-use consumer workshop definition
```

There are no `save-state` / `restore-state` hooks: persistent data lives in the `model-cache` and `huggingface-cache` mount plugs, which Workshop preserves across refreshes by definition (this is the pattern the [Workshop best-practices guide](https://documentation.ubuntu.com/canonical-workshop/latest/explanation/sdks/best-practices/#sdk-dependencies) explicitly recommends).

### Plugs and slots

| Name                 | Type   | Purpose                                                                             |
| -------------------- | ------ | ----------------------------------------------------------------------------------- |
| `model-cache`        | mount  | Persists `~/.cache/lemonade` (config, user models, backend binaries) across refresh |
| `huggingface-cache`  | mount  | Persists `~/.cache/huggingface` (the default `models_dir: "auto"` location)         |
| `gpu`                | gpu    | Enables ROCm / Vulkan hardware-accelerated inference                                |
| `lemonade-api`       | tunnel | Exposes port 13305; pair with a `system` tunnel plug of the same name on the host    |

### Hooks

| Hook            | Runs as  | When                            |
| --------------- | -------- | ------------------------------- |
| `setup-base`    | root     | First install and every refresh |
| `setup-project` | workshop | Every launch and refresh        |
| `check-health`  | root     | Post-launch / post-refresh      |

### Configuration

The SDK writes a sensible `config.json` on first launch only — subsequent refreshes preserve user edits. You can customise it at any time with the `lemonade config set` command inside the workshop:

```bash
# Increase context window
workshop exec ai-dev -- lemonade config set ctx_size=8192

# Pin llamacpp to a specific Vulkan build
workshop exec ai-dev -- lemonade config set llamacpp.vulkan_bin=b8664

# Accept connections from other machines on the network
workshop exec ai-dev -- lemonade config set host=0.0.0.0
```

Changes are persisted automatically because `config.json` lives inside the `model-cache` mount.

## Backends

Lemonade supports multiple inference backends. `lemond` probes available hardware on startup and selects the appropriate backend automatically — the SDK no longer runs its own `lspci` detection. Override per-backend at any time with `lemonade config set llamacpp.backend=...`.

| Hardware              | Typical backend       |
| --------------------- | --------------------- |
| AMD GPU (dGPU)        | `rocm`                |
| NVIDIA / Intel GPU    | `vulkan`              |
| AMD Ryzen AI NPU      | `flm` / `ryzenai`     |
| CPU fallback          | `cpu`                 |

## Platforms

Phase 2 ships `amd64` only, sourced from the upstream `lemonade-embeddable-*-ubuntu-x64.tar.gz` artifact. arm64 will be re-introduced once upstream publishes a Linux arm64 build.

## Security notes

- The server binds to `localhost` by default. Change `host` to `0.0.0.0` only on trusted networks and set `LEMONADE_API_KEY`.
- No API key is configured out of the box inside a workshop — this is intentional for local development. See the [Lemonade configuration docs](https://lemonade-server.ai/docs/guide/configuration/#api-key-and-security) for production hardening.

## Networking

Workshop runs its containers on a dedicated `workshopbr0` bridge. On hosts that also run Docker and/or have UFW with restrictive defaults, `workshopbr0` may end up with no outbound IPv4 connectivity (only IPv6 SLAAC), which causes `apt-get update` inside `setup-base` and `lemonade pull <model>` to hang. Workshop will surface this via `workshop warnings`.

Pick one of:

```bash
# Simplest: allow all routed traffic through the host
sudo ufw default allow routed && sudo ufw reload

# Or surgically open just the workshop bridge
sudo ufw allow in on workshopbr0
sudo ufw route allow in on workshopbr0
sudo ufw route allow out on workshopbr0
sudo ufw reload

# Or, if Docker's DOCKER-USER chain is the culprit, what Workshop itself recommends
sudo nft insert rule ip filter DOCKER-USER iifname workshopbr0 accept
sudo nft insert rule ip filter DOCKER-USER oifname workshopbr0 \
    ct state related,established accept
```

The nft rules don't persist across reboots — drop them into `/etc/nftables.conf` or `/etc/ufw/before.rules` if you need persistence.

## Verifying a local build

The canonical recipe for end-to-end testing without publishing to the SDK Store:

```bash
# 1. Pack and stage in the try area
cd lemonade-ai-community-sdk
sdkcraft clean && sdkcraft try

# 2. Launch a consumer workshop pointed at the try-area artifact
mkdir -p /tmp/ai-dev && cp examples/workshop.yaml /tmp/ai-dev/
cd /tmp/ai-dev
workshop launch ai-dev --verbose --wait-on-error
workshop info        # expect: status: ready

# 3. Health endpoint reachable from the host through the tunnel slot
curl -sf http://127.0.0.1:13305/api/v1/health
# expect: {"status":"ok","version":"10.6.0",...}

# 4. Pull a small model and confirm it survives a refresh
workshop run ai-dev -- pull Qwen3-0.6B-GGUF
workshop refresh ai-dev
workshop exec ai-dev -- bash -c 'lemonade list | grep Qwen3-0.6B-GGUF'
# expect a "Yes" in the Downloaded column
```

If step 2 hangs at `setup-base`'s `apt-get update`, see the Networking section above.

## License

Apache-2.0 — same as Lemonade Server upstream.
