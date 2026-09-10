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

killed=0; survived=0; unapplied=0; misattributed=0

# Every mutant declares the check that OWNS its invariant, and the kill is only
# believed when THAT check is among the failure lines (pitfall 23). Without this
# a mutant killed by unrelated collateral is indistinguishable from a real kill,
# and the next agent gets sent to debug a check that was never wrong.
#
# Six mutants are caught by the python unit suite, whose roll-up line is the
# coarse `FAIL  unit suite exited 1`. verify.sh dumps `tail -30` of the suite on
# failure, so the per-test node ids DO reach stdout and can be asserted on.
# Owners below were derived EMPIRICALLY (each mutant run in isolation, failure
# lines read) — never guessed. The two config-regex mutants share a test name and
# are distinguished by the subtest's `script=` parameter.
mutate() { # name file owner-regex mutation-command
  local name="$1" file="$2" owner="$3"; shift 3
  cp -p "$file" "$TMP/.orig"
  "$@"
  if cmp -s "$TMP/.orig" "$file"; then
    echo "  UNAPPLIED  $name   (broken rig, not a passing gate)"
    unapplied=$((unapplied+1))
  else
    local out rc fails
    out=$(./verify.sh 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then
      # Search ALL failure lines, not head -1: one mutation trips several checks
      # and the owning one is frequently not the first printed.
      fails=$(echo "$out" | grep -E '  FAIL|^FAIL:|^ERROR:')
      if echo "$fails" | grep -qE "$owner"; then
        echo "  KILLED     $name  ->  $(echo "$fails" | grep -E "$owner" | head -1 | sed 's/^ *//')"
        killed=$((killed+1))
      else
        echo "  MISATTRIBUTED  $name  (died, but not on its owning check)"
        echo "    expected owner /$owner/ did not fire; failures were:"
        echo "$fails" | sed 's/^/      /'
        misattributed=$((misattributed+1))
      fi
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
  'test_empty_value_does_not_swallow_next_line.*hermes-setup\.sh' \
  perl -0pi -e 's|\Q  default_model:)[ \t]*\E|  default_model:)\\s*|' scripts/hermes-setup.sh

# 2. Same defect in a different script — coverage must span all three.
mutate "config regex eats next line (launch)" scripts/hermes-launch.sh \
  'test_empty_value_does_not_swallow_next_line.*hermes-launch\.sh' \
  perl -0pi -e 's|\Q  default_model:)[ \t]*\E|  default_model:)\\s*|' scripts/hermes-launch.sh

# 3. Shell parse error.
mutate "shell parse error" scripts/hermes-optimize.sh \
  'syntax scripts/hermes-optimize\.sh' \
  perl -0pi -e 's|^banner\(\) \{|banner() { fi|m' scripts/hermes-optimize.sh

# 4. Python syntax error in the backend.
mutate "python syntax error" backend/main.py \
  'syntax backend/main\.py' \
  perl -0pi -e 's|^def system_stats\(\):|def system_stats(:|m' backend/main.py

# 5. Backend binds all interfaces — a localhost tool exposed to the LAN.
mutate "backend binds 0.0.0.0" backend/main.py \
  'test_backend_binds_loopback' \
  perl -0pi -e "s|host, port = '127.0.0.1', 7788|host, port = '0.0.0.0', 7788|" backend/main.py

# 6. Port drift between dashboard config and backend.
mutate "backend port drift" data.js \
  'backend port drift' \
  perl -0pi -e "s|127.0.0.1:7788|127.0.0.1:7999|" data.js

# 7. Setup wizard stops backing up config.yaml before rewriting it.
mutate "config backup removed" scripts/hermes-setup.sh \
  'test_backs_up_config_before_writing' \
  perl -0pi -e 's|^  cp "\$CONFIG".*$|  : no backup|m' scripts/hermes-setup.sh

# 8. A script loses strict mode.
mutate "strict mode removed" scripts/hermes-launch.sh \
  'test_scripts_are_strict.*hermes-launch\.sh' \
  perl -0pi -e 's|^set -euo pipefail$|set +e|m' scripts/hermes-launch.sh

# 9. `eval` reintroduced.
mutate "eval reintroduced" scripts/hermes-optimize.sh \
  "test_no_dangerous_constructs.*pattern='eval'" \
  perl -0pi -e 's|^banner$|eval "$BANNER"|m' scripts/hermes-optimize.sh

# 10. Malformed JSON.
mutate "malformed json" .claude/launch.json \
  'json \.claude/launch\.json' \
  perl -0pi -e 's|\{|\{\{|' .claude/launch.json

# 11. Empty test file — an empty suite must FAIL, not silently pass.
mutate "test suite emptied" tests/test_monitor.py \
  'tests defined \(suite was gutted' \
  perl -0pi -e 's|.*|# emptied by mutation proof\n|s' tests/test_monitor.py

echo ""
echo "MUTATION PROOF: killed=$killed survived=$survived unapplied=$unapplied misattributed=$misattributed"
./verify.sh >/dev/null 2>&1 && echo "restore PASS" || { echo "RESTORE FAILED"; exit 1; }
[ "$survived" -eq 0 ] && [ "$unapplied" -eq 0 ] && [ "$misattributed" -eq 0 ] && \
  { echo "MUTATION PROOF: PASS — every mutant killed by the check that OWNS its invariant"; exit 0; }
echo "MUTATION PROOF: FAIL — survivors, unapplied mutants, and/or misattributed kills above"; exit 1
