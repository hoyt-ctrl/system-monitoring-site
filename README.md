# Hermes Monitor

Real-time dashboard for your local Hermes/Ollama AI stack.

## What it shows

- Ollama connection status + host
- Primary model
- All available local models with sizes
- Currently loaded (hot) models
- System RAM usage (with backend)
- Quick benchmark runner

## Quick start

```bash
# 1. Serve the dashboard
cd system-monitoring-site
python3 -m http.server 7799
open http://localhost:7799

# 2. (Optional) Start the backend for live system stats
python3 backend/main.py &
```

## Configuration

Edit [`data.js`](data.js) to point at your Ollama host and set your primary model:

```js
window.HERMES_CONFIG = {
  ollamaHost:   'http://127.0.0.1:11435',
  backend:      'http://127.0.0.1:7788',
  primaryModel: 'hermes-qwen-64k-fixed:latest',
  refreshMs:    30000
};
```

## Launcher scripts

The [`scripts/`](scripts/) directory contains the Hermes CLI launcher suite.
Full scripts live in `~/.hermes/bin/` — see that directory for:

| Script | Purpose |
|---|---|
| `hermes-setup.sh` | 3-prompt setup wizard |
| `hermes-optimize.sh` | Benchmark all models + tune config |
| `hermes-launch.sh` | Master dispatcher (`h` alias) |

## Shell aliases

After running setup, these are available:

```zsh
h status          # Ollama + model + system check
h agent           # start CLI agent
h dashboard       # open Hermes web dashboard
h models          # list local models
h use <model>     # switch primary model
h optimize        # benchmark + tune
```

## Requirements

- [Ollama](https://ollama.ai) running locally
- Python 3 (stdlib only — no install needed for the dashboard server)
- `pip3 install psutil` for live RAM metrics in the backend