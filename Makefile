# system-monitoring-site — canonical entry points.
# `test:` MUST be a standalone rule: the verification-evidence recorder parses
# for a `^test:` header, and a combined `test verify:` header records nothing.
.PHONY: test verify check serve backend

test:
	./verify.sh

verify: test

check: test

backend:
	python3 backend/main.py

serve:
	python3 -m http.server 7799

# Prove the gate can fail. Minutes-long; kept OFF the commit path but on disk
# and reachable — a rig only a transcript knows how to launch is ephemeral
# evidence (portfolio-kickoff-sweep pitfall 26).
mutation-proof:
	./tools/mutation_proof.sh
