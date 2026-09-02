#!/usr/bin/env zsh
# Hermes Master Launcher — dispatcher for all Hermes interfaces
# Usage: hermes-launch.sh [command] [args...]
set -euo pipefail

HERMES_DIR="$HOME/.hermes"
CONFIG="$HERMES_DIR/config.yaml"
LOG="$HERMES_DIR/logs/launcher.log"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11435}"
HERMES_BIN="$HOME/.local/bin/hermes"
mkdir -p "$HERMES_DIR/logs"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────
current_model() { grep '^primary_model:' "$CONFIG" | awk '{print $2}'; }
ollama_up()     { curl -sf --max-time 2 "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; }

ensure_ollama() {
  if ! ollama_up; then
    echo -e "${YELLOW}Starting Ollama...${RESET}"
    ollama serve >> "$HERMES_DIR/logs/ollama.log" 2>&1 &
    local i=0
    while ! ollama_up && [[ $i -lt 15 ]]; do sleep 1; (( i++ )); done
    ollama_up || { echo -e "${RED}Ollama failed to start${RESET}"; return 1; }
    echo -e "${GREEN}✓ Ollama ready${RESET}"
    log "Ollama started"
  fi
}

# ── Commands ──────────────────────────────────────────────────────────

cmd_agent() {
  ensure_ollama
  local profile="${1:-default}"
  echo -e "${GREEN}Launching Hermes CLI agent (profile: ${profile})...${RESET}"
  log "agent start — profile=$profile"
  exec "$HERMES_BIN" -p "$profile" "${@:2}"
}

cmd_dashboard() {
  ensure_ollama
  echo -e "${GREEN}Launching Hermes dashboard...${RESET}"
  log "dashboard start"
  "$HERMES_BIN" dashboard &
  sleep 2
  open "http://localhost:8080" 2>/dev/null || echo "Open http://localhost:8080 in your browser"
}

cmd_status() {
  echo -e "${BOLD}Hermes Status${RESET}"
  echo ""

  # Ollama
  if ollama_up; then
    echo -e "  Ollama      : ${GREEN}✓ running${RESET} at ${OLLAMA_HOST}"
    local loaded
    loaded=$(curl -sf "${OLLAMA_HOST}/api/ps" 2>/dev/null | \
      python3 -c "import sys,json; ms=json.load(sys.stdin).get('models',[]); print(', '.join(m['name'] for m in ms) or 'none loaded')" 2>/dev/null || echo "unknown")
    echo -e "  Loaded      : ${CYAN}${loaded}${RESET}"
  else
    echo -e "  Ollama      : ${RED}✗ not running${RESET}"
  fi

  # Primary model
  echo -e "  Primary     : ${CYAN}$(current_model)${RESET}"

  # Available models
  local model_count
  model_count=$(curl -sf "${OLLAMA_HOST}/api/tags" 2>/dev/null | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "?")
  echo -e "  Models      : ${CYAN}${model_count} available${RESET}"

  # Hermes binary
  if [[ -x "$HERMES_BIN" ]]; then
    local ver
    ver=$("$HERMES_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "  Hermes      : ${GREEN}✓${RESET} $ver"
  else
    echo -e "  Hermes      : ${RED}✗ not found at $HERMES_BIN${RESET}"
  fi

  # System
  local ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  local cores=$(sysctl -n hw.ncpu)
  echo -e "  System      : ${CYAN}${cores} cores · ${ram_gb}GB RAM${RESET}"
  echo ""
}

cmd_models() {
  echo -e "${BOLD}Available local models:${RESET}"
  echo ""
  if ollama_up; then
    curl -sf "${OLLAMA_HOST}/api/tags" 2>/dev/null | python3 -c "
import sys, json
models = json.load(sys.stdin).get('models', [])
for m in models:
    size_gb = m.get('size', 0) / 1073741824
    print(f\"  {m['name']:<45} {size_gb:.1f}GB\")
" 2>/dev/null || echo "  (could not parse model list)"
  else
    echo -e "  ${RED}Ollama not running${RESET}"
  fi
  echo ""
  echo -e "  ${CYAN}Primary: $(current_model)${RESET}"
  echo ""
}

cmd_use() {
  local model="${1:-}"
  [[ -z "$model" ]] && { echo "Usage: hermes-launch.sh use <model-name>"; exit 1; }
  python3 - "$CONFIG" "$model" <<'PYEOF'
import sys, re
config_path, model = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    content = f.read()
content = re.sub(r'^primary_model:.*$', f'primary_model: {model}', content, flags=re.MULTILINE)
# NOTE: `[ \t]*`, never `\s*` — `\s` matches newlines, so on a key with an
# empty value the match runs past the end of the line and DELETES the line
# below it. Config destruction with no error. Pinned by tests/test_monitor.py.
content = re.sub(r'^(ollama:.*?\n  default_model:)[ \t]*.*$',
                 lambda m: f'{m.group(1)} {model}',
                 content, flags=re.MULTILINE)
with open(config_path, 'w') as f:
    f.write(content)
print(f"  ✓ Switched primary_model → {model}")
PYEOF
  log "Switched to $model"
}

cmd_logs() {
  local which="${1:-launcher}"
  case "$which" in
    ollama)  tail -f "$HERMES_DIR/logs/ollama.log" ;;
    setup)   tail -f "$HERMES_DIR/logs/setup.log" ;;
    opt*)    tail -f "$HERMES_DIR/logs/optimize.log" ;;
    *)       tail -f "$LOG" ;;
  esac
}

cmd_config() {
  echo -e "${BOLD}Key config values (${CONFIG}):${RESET}"
  echo ""
  python3 - "$CONFIG" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
keys = ['primary_model', 'primary_provider', 'context_window', 'temperature',
        'max_turns', 'interface', 'memory_enabled']
for key in keys:
    m = re.search(rf'^[ ]*{key}:\s*(.+)$', content, re.MULTILINE)
    if m:
        print(f"  {key:<22} {m.group(1).strip()}")
PYEOF
  echo ""
}

cmd_browser() {
  local target="${1:-claude}"
  declare -A URLS=(
    [claude]="https://claude.ai"
    [chatgpt]="https://chat.openai.com"
    [gemini]="https://gemini.google.com"
    [grok]="https://grok.x.ai"
  )
  local url="${URLS[$target]:-https://claude.ai}"
  echo -e "${GREEN}Opening ${target} in browser...${RESET}"
  open "$url"
  log "browser: $target"
}

cmd_help() {
  echo -e "${BOLD}${CYAN}Hermes Launch Commands${RESET}"
  echo ""
  echo -e "  ${BOLD}agent${RESET}   [profile]    — start CLI agent (default/maritime/local-ai)"
  echo -e "  ${BOLD}dashboard${RESET}            — start web dashboard + open browser"
  echo -e "  ${BOLD}status${RESET}               — show Ollama, model, system status"
  echo -e "  ${BOLD}models${RESET}               — list available local models"
  echo -e "  ${BOLD}use${RESET}     <model>      — switch primary model"
  echo -e "  ${BOLD}logs${RESET}    [ollama|setup|optimize] — tail logs"
  echo -e "  ${BOLD}config${RESET}               — show key config values"
  echo -e "  ${BOLD}browser${RESET} [claude|chatgpt|gemini|grok] — open AI browser UI"
  echo -e "  ${BOLD}setup${RESET}                — run interactive setup wizard"
  echo -e "  ${BOLD}optimize${RESET}             — benchmark & tune performance"
  echo ""
  echo -e "  Wrapper scripts:"
  echo -e "    hermes-setup.sh     — 3-prompt setup wizard"
  echo -e "    hermes-optimize.sh  — benchmark all models"
  echo ""
}

# ── Dispatch ──────────────────────────────────────────────────────────
CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
  agent)     cmd_agent "$@" ;;
  dashboard) cmd_dashboard "$@" ;;
  status)    cmd_status ;;
  models)    cmd_models ;;
  use)       cmd_use "$@" ;;
  logs)      cmd_logs "$@" ;;
  config)    cmd_config ;;
  browser)   cmd_browser "$@" ;;
  setup)     exec "$HERMES_DIR/bin/hermes-setup.sh" ;;
  optimize)  exec "$HERMES_DIR/bin/hermes-optimize.sh" ;;
  help|--help|-h) cmd_help ;;
  *) echo -e "${RED}Unknown command: $CMD${RESET}"; cmd_help; exit 1 ;;
esac
