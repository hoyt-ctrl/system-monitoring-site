#!/usr/bin/env bash
# Canonical offline gate for system-monitoring-site.
#
# Scope: tree soundness only. Deliberately EXCLUDED because they are runtime
# questions, not repo questions:
#   * live Ollama reachability / model benchmarks (network + model-backed)
#   * the interactive setup wizard flow (needs a TTY)
#   * a running backend on :7788 or a served dashboard
#
# Every set-examining leg FAILS on zero files examined, so a coverage gap can
# never read as a silent pass.
set -uo pipefail
cd "$(dirname "$0")"

rc=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; rc=1; }

echo "== shell syntax =="
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1))
  if zsh -n "$f" 2>/dev/null || bash -n "$f" 2>/dev/null; then
    pass "syntax $f"
  else
    fail "syntax $f"
  fi
done < <(git ls-files '*.sh')
if [ "$n" -eq 0 ]; then fail "no shell files examined (coverage gap)"; else echo "  ($n shell files)"; fi

echo "== python syntax =="
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1))
  if python3 -m py_compile "$f" 2>/dev/null; then pass "syntax $f"; else fail "syntax $f"; fi
done < <(git ls-files '*.py')
if [ "$n" -eq 0 ]; then fail "no python files examined (coverage gap)"; else echo "  ($n python files)"; fi

echo "== json syntax =="
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1))
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    pass "json $f"
  else
    fail "json $f"
  fi
done < <(git ls-files '*.json')
if [ "$n" -eq 0 ]; then fail "no json files examined (coverage gap)"; else echo "  ($n json files)"; fi

echo "== dashboard/config coherence =="
# data.js declares the backend port; backend/main.py binds it. A drift here
# means a dashboard that silently shows nothing.
port_js=$(grep -oE "backend:[^,]*" data.js | grep -oE '127\.0\.0\.1:[0-9]+' | grep -oE '[0-9]+$' || true)
# Host-agnostic on purpose: pinning this to 127.0.0.1 would make a
# bind-to-0.0.0.0 change fail HERE ("could not read the port") instead of on
# the loopback test that actually owns that invariant — a misattributed FAIL.
port_py=$(grep -oE "port = '[0-9.]+', [0-9]+" backend/main.py | grep -oE '[0-9]+$' || true)
if [ -z "$port_js" ] || [ -z "$port_py" ]; then
  fail "could not read backend port from both data.js and backend/main.py"
elif [ "$port_js" = "$port_py" ]; then
  pass "backend port agrees ($port_js)"
else
  fail "backend port drift: data.js=$port_js backend/main.py=$port_py"
fi

echo "== test suite =="
out=$(python3 tests/test_monitor.py 2>&1)
status=$?
ran=$(echo "$out" | grep -oE '^Ran [0-9]+ test' | grep -oE '[0-9]+' || echo 0)
# Expected count DERIVED from the file, so a collection gap (a test file that
# stops being run) fails instead of passing quietly.
expected=$(grep -cE '^\s+def test_' tests/test_monitor.py)
skipped=$(echo "$out" | grep -oE 'skipped=[0-9]+' | grep -oE '[0-9]+' || echo 0)
# Floor of 20: an emptied test file makes BOTH `ran` and `expected` zero, so
# `ran < expected` is false and the gate would report a green suite that
# asserted nothing. Found by tools/mutation_proof.sh — the mutant survived.
if [ "$expected" -lt 20 ]; then
  fail "only $expected tests defined (suite was gutted; expected >= 20)"
elif [ "$status" -ne 0 ]; then
  fail "unit suite exited $status"
  echo "$out" | tail -30
elif [ "$ran" -lt "$expected" ]; then
  fail "unit suite ran $ran of $expected defined tests (collection gap)"
elif [ "${skipped:-0}" -ne 0 ]; then
  fail "unit suite skipped $skipped tests — a skip is not a pass"
else
  pass "unit suite $ran/$expected, 0 skipped"
fi

echo ""
if [ "$rc" -eq 0 ]; then echo "VERIFY: PASS"; else echo "VERIFY: FAIL"; fi
exit "$rc"
