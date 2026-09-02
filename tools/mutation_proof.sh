#!/usr/bin/env bash
# Mutation proof for ./verify.sh — shows the gate CAN fail, with attribution.
#
# Runs on a `cp -Rp` scratch copy (`-p` is load-bearing: mtimes are inputs to
# several checks and `cp -R` alone rewrites them). Baseline must be PASS before
# any mutant is trusted; every mutant is apply-guarded with `cmp -s`, because a
# mutation that never applied is a broken rig, not a passing check.
set -uo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/sysmonproof.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cp -Rp "$SRC/." "$TMP/"
cd "$TMP"

echo "=== BASELINE ==="
if ./verify.sh >/dev/null 2>&1; then
  echo "baseline PASS"
else
  echo "BASELINE IS RED — the whole round is unfalsifiable. Aborting."
  exit 1
fi

killed=0; survived=0; unapplied=0

mutate() { # name file mutation-command
  local name="$1" file="$2"; shift 2
  cp -p "$file" "$TMP/.orig"
  "$@"
  if cmp -s "$TMP/.orig" "$file"; then
    echo "  UNAPPLIED  $name"
    unapplied=$((unapplied+1))
  else
    local out rc
    out=$(./verify.sh 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "  KILLED     $name  ->  $(echo "$out" | grep '  FAIL' | head -1 | sed 's/^ *//')"
      killed=$((killed+1))
    else
      echo "  SURVIVED   $name  (gate asserted nothing)"
      survived=$((survived+1))
    fi
  fi
  cp -p "$TMP/.orig" "$file"
}

echo "=== MUTANTS ==="

# 1. Re-introduce the \s* config-eating regex the suite was written to catch.
mutate "config regex eats next line" scripts/hermes-setup.sh \
  perl -0pi -e 's|\Q  default_model:)[ \t]*\E|  default_model:)\\s*|' scripts/hermes-setup.sh

# 2. Same defect in a different script — coverage must span all three.
mutate "config regex eats next line (launch)" scripts/hermes-launch.sh \
  perl -0pi -e 's|\Q  default_model:)[ \t]*\E|  default_model:)\\s*|' scripts/hermes-launch.sh

# 3. Shell parse error.
mutate "shell parse error" scripts/hermes-optimize.sh \
  perl -0pi -e 's|^banner\(\) \{|banner() { fi|m' scripts/hermes-optimize.sh

# 4. Python syntax error in the backend.
mutate "python syntax error" backend/main.py \
  perl -0pi -e 's|^def system_stats\(\):|def system_stats(:|m' backend/main.py

# 5. Backend binds all interfaces — a localhost tool exposed to the LAN.
mutate "backend binds 0.0.0.0" backend/main.py \
  perl -0pi -e "s|host, port = '127.0.0.1', 7788|host, port = '0.0.0.0', 7788|" backend/main.py

# 6. Port drift between dashboard config and backend.
mutate "backend port drift" data.js \
  perl -0pi -e "s|127.0.0.1:7788|127.0.0.1:7999|" data.js

# 7. Setup wizard stops backing up config.yaml before rewriting it.
mutate "config backup removed" scripts/hermes-setup.sh \
  perl -0pi -e 's|^  cp "\$CONFIG".*$|  : no backup|m' scripts/hermes-setup.sh

# 8. A script loses strict mode.
mutate "strict mode removed" scripts/hermes-launch.sh \
  perl -0pi -e 's|^set -euo pipefail$|set +e|m' scripts/hermes-launch.sh

# 9. `eval` reintroduced.
mutate "eval reintroduced" scripts/hermes-optimize.sh \
  perl -0pi -e 's|^banner$|eval "$BANNER"|m' scripts/hermes-optimize.sh

# 10. Malformed JSON.
mutate "malformed json" .claude/launch.json \
  perl -0pi -e 's|\{|\{\{|' .claude/launch.json

# 11. Empty test file — an empty suite must FAIL, not silently pass.
mutate "test suite emptied" tests/test_monitor.py \
  perl -0pi -e 's|.*|# emptied by mutation proof\n|s' tests/test_monitor.py

echo ""
echo "MUTATION PROOF: killed=$killed survived=$survived unapplied=$unapplied"
./verify.sh >/dev/null 2>&1 && echo "restore PASS" || { echo "RESTORE FAILED"; exit 1; }
[ "$survived" -eq 0 ] && [ "$unapplied" -eq 0 ] && { echo "MUTATION PROOF: PASS"; exit 0; }
echo "MUTATION PROOF: FAIL"; exit 1
