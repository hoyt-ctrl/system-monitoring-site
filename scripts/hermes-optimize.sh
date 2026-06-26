#!/usr/bin/env zsh
# Hermes Optimizer — benchmark all local models, tune Ollama & config
set -euo pipefail

HERMES_DIR="$HOME/.hermes"
CONFIG="$HERMES_DIR/config.yaml"
LOG="$HERMES_DIR/logs/optimize.log"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11435}"
mkdir -p "$HERMES_DIR/logs"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

CPU_CORES=$(sysctl -n hw.ncpu)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
CURRENT_MODEL=$(grep '^primary_model:' "$CONFIG" | awk '{print $2}')

banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════╗"
  echo "║        HERMES PERFORMANCE OPTIMIZER      ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo -e "  System : ${GREEN}${CPU_CORES} cores · ${RAM_GB}GB RAM${RESET}"
  echo -e "  Current: ${GREEN}${CURRENT_MODEL}${RESET}"
  echo ""
}

# ── Benchmark a single model ──────────────────────────────────────────
bench_model() {
  local model="$1"
  local prompt="Explain photosynthesis in exactly 20 words."
  local result tokens elapsed

  local start=$(date +%s%3N)
  result=$(curl -sf --max-time 60 "${OLLAMA_HOST}/api/generate" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\",\"prompt\":\"${prompt}\",\"stream\":false,\"options\":{\"num_predict\":30}}" 2>/dev/null) || {
      echo "TIMEOUT"
      return
    }
  local end=$(date +%s%3N)

  elapsed=$(( end - start ))
  tokens=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo 0)

  if [[ "$tokens" -gt 0 && "$elapsed" -gt 0 ]]; then
    echo "$(( tokens * 1000 / elapsed )) tok/s · ${elapsed}ms · ${tokens} tokens"
    log "$model: $(( tokens * 1000 / elapsed )) tok/s"
  else
    echo "ERROR"
  fi
}

# ── Benchmark all available models ───────────────────────────────────
bench_all() {
  echo -e "${BOLD}Benchmarking available models...${RESET}"
  echo -e "${YELLOW}(This may take 2-5 minutes)${RESET}"
  echo ""

  local models
  models=$(curl -sf "${OLLAMA_HOST}/api/tags" 2>/dev/null | \
    python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null || echo "")

  if [[ -z "$models" ]]; then
    echo -e "${RED}Ollama not reachable at ${OLLAMA_HOST}${RESET}"
    return 1
  fi

  declare -A RESULTS
  local best_model="" best_speed=0

  printf "  %-45s %s\n" "MODEL" "SPEED"
  printf "  %-45s %s\n" "─────────────────────────────────────────────" "──────────────────────────"

  while IFS= read -r model; do
    # Skip embedding models
    [[ "$model" == *"embed"* ]] && continue

    printf "  %-45s " "$model"
    local result
    result=$(bench_model "$model")
    echo "$result"

    # Track best
    if [[ "$result" != "TIMEOUT" && "$result" != "ERROR" ]]; then
      local speed
      speed=$(echo "$result" | grep -oE '^[0-9]+')
      if [[ -n "$speed" && "$speed" -gt "$best_speed" ]]; then
        best_speed=$speed
        best_model=$model
      fi
    fi
  done <<< "$models"

  echo ""
  if [[ -n "$best_model" ]]; then
    echo -e "  ${GREEN}${BOLD}Fastest: ${best_model} (${best_speed} tok/s)${RESET}"
    echo -e "  Current: ${CYAN}${CURRENT_MODEL}${RESET}"
    BEST_MODEL="$best_model"
    BEST_SPEED="$best_speed"
  fi
}

# ── Ollama tuning recommendations ────────────────────────────────────
tune_env() {
  echo ""
  echo -e "${BOLD}Environment tuning recommendations:${RESET}"
  echo ""

  local num_threads=$CPU_CORES
  local keep_alive="10m"
  local ctx_window=32768

  # Tune context window based on RAM
  if [[ "$RAM_GB" -ge 48 ]]; then
    ctx_window=65536
  elif [[ "$RAM_GB" -ge 32 ]]; then
    ctx_window=49152
  elif [[ "$RAM_GB" -ge 16 ]]; then
    ctx_window=32768
  else
    ctx_window=16384
  fi

  echo "  Add to ~/.zshrc:"
  echo ""
  echo -e "  ${CYAN}export OLLAMA_NUM_THREAD=${num_threads}${RESET}"
  echo -e "  ${CYAN}export OLLAMA_KEEP_ALIVE=${keep_alive}${RESET}"
  echo -e "  ${CYAN}export OLLAMA_FLASH_ATTENTION=1${RESET}"
  echo -e "  ${CYAN}export OLLAMA_KV_CACHE_TYPE=q8_0${RESET}  # quantized KV cache"
  echo ""
  echo -e "  Recommended context_window for ${RAM_GB}GB RAM: ${GREEN}${ctx_window}${RESET}"

  # Check current config context_window
  local current_ctx
  current_ctx=$(grep 'context_window:' "$CONFIG" | head -1 | awk '{print $2}')
  if [[ "$current_ctx" != "$ctx_window" ]]; then
    echo -e "  ${YELLOW}Config has context_window: ${current_ctx} → suggest ${ctx_window}${RESET}"
    echo ""
    read -r "apply?  Apply context_window=${ctx_window}? [y/N]: "
    if [[ "$apply" == "y" || "$apply" == "Y" ]]; then
      sed -i.bak "s/context_window: .*/context_window: ${ctx_window}/" "$CONFIG"
      echo -e "  ${GREEN}✓ context_window updated to ${ctx_window}${RESET}"
      log "context_window updated to ${ctx_window}"
    fi
  else
    echo -e "  ${GREEN}✓ context_window already optimal (${ctx_window})${RESET}"
  fi
}

# ── Offer to switch model ────────────────────────────────────────────
offer_switch() {
  if [[ -n "${BEST_MODEL:-}" && "$BEST_MODEL" != "$CURRENT_MODEL" ]]; then
    echo ""
    echo -e "${BOLD}Fastest model differs from current:${RESET}"
    echo -e "  Current : ${CYAN}${CURRENT_MODEL}${RESET}"
    echo -e "  Fastest : ${GREEN}${BEST_MODEL} (${BEST_SPEED} tok/s)${RESET}"
    echo ""
    read -r "sw?  Switch primary_model to ${BEST_MODEL}? [y/N]: "
    if [[ "$sw" == "y" || "$sw" == "Y" ]]; then
      python3 - "$CONFIG" "$BEST_MODEL" <<'PYEOF'
import sys, re
config_path, model = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    content = f.read()
content = re.sub(r'^primary_model:.*$', f'primary_model: {model}', content, flags=re.MULTILINE)
content = re.sub(r'^(ollama:.*?\n  default_model:)\s*.*$',
                 lambda m: f'{m.group(1)} {model}',
                 content, flags=re.MULTILINE)
with open(config_path, 'w') as f:
    f.write(content)
print(f"  ✓ Switched to {model}")
PYEOF
      log "Switched primary_model to $BEST_MODEL"
    fi
  fi
}

# ── Write shell env snippet ──────────────────────────────────────────
write_env_snippet() {
  local snippet="$HERMES_DIR/logs/env-tuning.sh"
  cat > "$snippet" <<SNIPPET
# Hermes / Ollama tuning — generated $(date)
# Source with: source $snippet
export OLLAMA_NUM_THREAD=${CPU_CORES}
export OLLAMA_KEEP_ALIVE=10m
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
SNIPPET
  echo ""
  echo -e "  Snippet saved: ${CYAN}${snippet}${RESET}"
  echo -e "  To apply now: ${CYAN}source ${snippet}${RESET}"
}

# ── Main ─────────────────────────────────────────────────────────────
BEST_MODEL=""
BEST_SPEED=0

banner
bench_all
tune_env
offer_switch
write_env_snippet

echo ""
echo -e "${GREEN}${BOLD}✓ Optimization complete — log: ${LOG}${RESET}"
echo ""
