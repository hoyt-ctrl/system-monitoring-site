#!/usr/bin/env zsh
# Hermes Setup Wizard — 3-prompt interactive setup
set -euo pipefail

HERMES_DIR="$HOME/.hermes"
CONFIG="$HERMES_DIR/config.yaml"
LOG="$HERMES_DIR/logs/setup.log"
mkdir -p "$HERMES_DIR/logs"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════╗"
  echo "║          HERMES SETUP WIZARD             ║"
  echo "║     Local AI · Optimized for macOS       ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${RESET}"
}

# ── System Detection ────────────────────────────────────────────────────
detect_system() {
  CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 8589934592)
  RAM_GB=$(( RAM_BYTES / 1073741824 ))
  HAS_GPU=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Metal" || echo 0)
  OLLAMA_RUNNING=$(pgrep -x ollama >/dev/null 2>&1 && echo yes || echo no)
  OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11435}"

  echo -e "${BOLD}System detected:${RESET}"
  echo -e "  CPU cores : ${GREEN}${CPU_CORES}${RESET}"
  echo -e "  RAM       : ${GREEN}${RAM_GB}GB${RESET}"
  echo -e "  Metal GPU : ${GREEN}$([ "$HAS_GPU" -gt 0 ] && echo yes || echo no)${RESET}"
  echo -e "  Ollama    : ${GREEN}${OLLAMA_RUNNING}${RESET} at ${OLLAMA_HOST}"
  echo ""
}

# ── Prompt 1: Use case ──────────────────────────────────────────────────
ask_usecase() {
  echo -e "${BOLD}Q1 of 3 — What's your primary use case?${RESET}"
  echo "  1) Maritime / navigation intelligence"
  echo "  2) Software development / coding"
  echo "  3) Research & long-form analysis"
  echo "  4) General assistant"
  echo ""
  read -r "choice?→ Choose [1-4]: "
  case "$choice" in
    1) USE_CASE="maritime";  PROFILE="maritime"  ;;
    2) USE_CASE="coding";    PROFILE="default"   ;;
    3) USE_CASE="research";  PROFILE="local-ai"  ;;
    4) USE_CASE="general";   PROFILE="default"   ;;
    *) USE_CASE="general";   PROFILE="default"   ;;
  esac
  log "Use case: $USE_CASE / profile: $PROFILE"
}

# ── Prompt 2: Model tier ────────────────────────────────────────────────
ask_model() {
  echo ""
  echo -e "${BOLD}Q2 of 3 — Model preference?${RESET}"
  echo "  1) Fast  — hermes-fast (9GB, ~8 tok/s)"
  echo "  2) Smart — hermes-qwen-64k-fixed (9GB, 64k ctx)  [current default]"
  echo "  3) Coder — hermes-coder (9.3GB, code-optimized)"
  echo "  4) Big   — qwen3:32b (20GB, best quality, needs 20GB+ free RAM)"
  echo ""
  read -r "choice?→ Choose [1-4]: "
  case "$choice" in
    1) MODEL="hermes-fast:latest" ;;
    2) MODEL="hermes-qwen-64k-fixed:latest" ;;
    3) MODEL="hermes-coder:latest" ;;
    4) MODEL="qwen3:32b" ;;
    *) MODEL="hermes-qwen-64k-fixed:latest" ;;
  esac
  log "Model selected: $MODEL"
}

# ── Prompt 3: Interface ─────────────────────────────────────────────────
ask_interface() {
  echo ""
  echo -e "${BOLD}Q3 of 3 — Default launch interface?${RESET}"
  echo "  1) CLI agent    — terminal chat, scriptable"
  echo "  2) Dashboard    — web UI at localhost:8080"
  echo "  3) Both         — launch CLI, dashboard in background"
  echo ""
  read -r "choice?→ Choose [1-3]: "
  case "$choice" in
    1) INTERFACE="cli" ;;
    2) INTERFACE="dashboard" ;;
    3) INTERFACE="both" ;;
    *) INTERFACE="cli" ;;
  esac
  log "Interface: $INTERFACE"
}

# ── Apply config changes ─────────────────────────────────────────────────
apply_config() {
  echo ""
  log "Applying config changes..."

  # Backup existing config
  cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

  # Update primary model using Python (avoids yaml parse issues with sed)
  python3 - "$CONFIG" "$MODEL" "$PROFILE" <<'PYEOF'
import sys, re

config_path = sys.argv[1]
model = sys.argv[2]
profile = sys.argv[3]

with open(config_path, 'r') as f:
    content = f.read()

# Update primary_model
content = re.sub(r'^primary_model:.*$', f'primary_model: {model}', content, flags=re.MULTILINE)

# Update ollama default_model
content = re.sub(r'^(ollama:.*?\n  default_model:)\s*.*$',
                 lambda m: f'{m.group(1)} {model}',
                 content, flags=re.MULTILINE)

with open(config_path, 'w') as f:
    f.write(content)

print(f"  ✓ primary_model → {model}")
PYEOF

  # Set display interface
  if [[ "$INTERFACE" == "dashboard" || "$INTERFACE" == "both" ]]; then
    python3 - "$CONFIG" <<'PYEOF'
import sys, re
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = re.sub(r'^(  interface:)\s*.*$', r'\1 dashboard', content, flags=re.MULTILINE)
with open(sys.argv[1], 'w') as f:
    f.write(content)
print("  ✓ interface → dashboard")
PYEOF
  fi

  log "Config updated."
}

# ── Benchmark ────────────────────────────────────────────────────────────
run_benchmark() {
  echo ""
  echo -e "${BOLD}Running quick inference benchmark...${RESET}"
  local prompt="Reply in exactly 5 words: what is machine learning?"
  local start end elapsed tokens

  start=$(date +%s%3N)
  result=$(curl -sf "${OLLAMA_HOST}/api/generate" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"${prompt}\",\"stream\":false}" 2>/dev/null) || {
      echo -e "  ${YELLOW}⚠ Ollama not reachable — skipping benchmark${RESET}"
      return
    }

  end=$(date +%s%3N)
  elapsed=$(( end - start ))
  tokens=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo 0)
  response=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response','').strip())" 2>/dev/null || echo "")

  echo -e "  Response : ${GREEN}${response}${RESET}"
  echo -e "  Tokens   : ${GREEN}${tokens}${RESET}"
  echo -e "  Time     : ${GREEN}${elapsed}ms${RESET}"
  [[ "$tokens" -gt 0 && "$elapsed" -gt 0 ]] && \
    echo -e "  Speed    : ${GREEN}$(( tokens * 1000 / elapsed )) tok/s${RESET}"

  log "Benchmark: ${tokens} tokens in ${elapsed}ms"
}

# ── Summary ──────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}✓ Setup complete${RESET}"
  echo ""
  echo -e "  Use case  : ${CYAN}${USE_CASE}${RESET}"
  echo -e "  Model     : ${CYAN}${MODEL}${RESET}"
  echo -e "  Interface : ${CYAN}${INTERFACE}${RESET}"
  echo -e "  Profile   : ${CYAN}${PROFILE}${RESET}"
  echo ""
  echo -e "${BOLD}Next steps:${RESET}"
  echo "  hermes-launch.sh          — launch with your chosen interface"
  echo "  hermes-optimize.sh        — benchmark & tune performance"
  echo "  hermes -p ${PROFILE}      — start with your profile directly"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  banner
  detect_system
  ask_usecase
  ask_model
  ask_interface
  apply_config
  run_benchmark
  print_summary
}

main "$@"
