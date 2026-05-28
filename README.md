# lemonade-server Workshop SDK

A community [Canonical Workshop](https://documentation.ubuntu.com/canonical-workshop/latest/) SDK that installs and manages [Lemonade Server](https://lemonade-server.ai/) — a lightweight, open-source local LLM inference server — inside a workshop environment.

> **Status: Phase 1 (structural alignment).** The hook layout, plug/slot vocabulary, and consumer example are now in line with the documented Workshop SDK contract. Lemonade itself is still installed from the upstream PPA in `setup-base`; switching to the prebuilt `lemonade-embeddable` tarball part is Phase 2 of the realignment plan.

## What this SDK provides

- **lemonade-server** installed via the official stable PPA (`ppa:lemonade-team/stable`) — Phase 2 will replace this with a reproducible upstream tarball part.
- **lemond** running as a systemd user service, auto-started on workshop launch.
- Best-effort GPU/NPU backend detection at setup time (`cpu` → `vulkan` → `rocm` → `npu`); the result is written into a default `config.json`.
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
├── sdkcraft.yaml             # SDK definition
├── service/
│   └── lemond.service        # systemd user unit (shipped as a part)
├── hooks/
│   ├── setup-base            # root: PPA install, PATH, disable system service
│   ├── setup-project         # workshop user: GPU detect, config.json, start unit
│   └── check-health          # poll /api/v0/status; report okay / waiting / error
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

Lemonade supports multiple inference backends. The SDK auto-selects one at `setup-project` time based on detected hardware, but you can override it later with `lemonade config set`.

| Hardware              | Auto-detected backend |
| --------------------- | --------------------- |
| AMD GPU (dGPU)        | `rocm`                |
| NVIDIA / Intel GPU    | `vulkan`              |
| AMD Ryzen AI NPU      | `flm` / `ryzenai`     |
| CPU fallback          | `cpu`                 |

## Platforms

Phase 1 ships `amd64` only. Upstream Lemonade does not currently publish a Linux arm64 binary or PPA suite; arm64 support will land once upstream provides one or once the SDK adopts a source-built part.

## Security notes

- The server binds to `localhost` by default. Change `host` to `0.0.0.0` only on trusted networks and set `LEMONADE_API_KEY`.
- No API key is configured out of the box inside a workshop — this is intentional for local development. See the [Lemonade configuration docs](https://lemonade-server.ai/docs/guide/configuration/#api-key-and-security) for production hardening.

## License

Apache-2.0 — same as Lemonade Server upstream.
