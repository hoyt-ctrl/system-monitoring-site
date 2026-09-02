#!/usr/bin/env python3
"""
Offline gate for system-monitoring-site.

Why this suite exists
---------------------
Two of the three shell scripts in this repo REWRITE `~/.hermes/config.yaml`
in place — the same file whose corruption is a logged AICP-CRITICAL incident
(a desktop model switch rewrote the model block and broke routing).  The
rewriters are Python heredocs embedded inside zsh scripts, so nothing could
import or exercise them and the repo had no runner at all.

This suite extracts the REAL embedded rewriters out of the REAL scripts (never
a copy pasted into the test) and runs them against fixture configs, asserting
the only thing that actually matters: the intended key changes and EVERY other
byte of the config survives.

Deliberately EXCLUDED (runtime questions, not tree soundness):
  * live Ollama calls / benchmarks (network + model-backed)
  * the interactive `read -r` wizard flow (needs a TTY)
  * `hermes` binary presence
All checks below are offline and hermetic.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import HTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPTS = REPO / "scripts"

# A config shaped like the real ~/.hermes/config.yaml: the model block plus a
# lot of unrelated state that MUST survive a rewrite untouched.
FIXTURE_CONFIG = """\
primary_provider: ollama
primary_model: hermes-qwen-64k-fixed:latest
context_window: 32768
temperature: 0.7
max_turns: 40
memory_enabled: true

ollama:
  default_model: hermes-qwen-64k-fixed:latest
  host: http://127.0.0.1:11435

display:
  interface: cli
  theme: dark

mcp_servers:
  aicp-router:
    command: python3
    args: ["-m", "aicp.router"]

delegation:
  default_lane: local
"""


def embedded_python_blocks(script: Path):
    """Pull every `python3 ... <<'PYEOF' ... PYEOF` body out of a shell script.

    Derived from the file, never hardcoded: if a rewriter is added or removed
    the counts below move with it.
    """
    text = script.read_text()
    return re.findall(r"<<'PYEOF'\n(.*?)\nPYEOF", text, re.DOTALL)


def model_rewriters():
    """Every embedded block that rewrites primary_model, with its source file."""
    found = []
    for script in sorted(SCRIPTS.glob("*.sh")):
        for body in embedded_python_blocks(script):
            if "primary_model" in body and "re.sub" in body:
                found.append((script.name, body))
    return found


def run_block(body, args):
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(body)
        path = fh.name
    try:
        return subprocess.run(
            [sys.executable, path, *args],
            capture_output=True, text=True, timeout=30,
        )
    finally:
        os.unlink(path)


def write_config(text):
    fh = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False)
    fh.write(text)
    fh.close()
    return fh.name


class TestRewriterDiscovery(unittest.TestCase):
    def test_scripts_present(self):
        names = {p.name for p in SCRIPTS.glob("*.sh")}
        self.assertEqual(
            names,
            {"hermes-launch.sh", "hermes-optimize.sh", "hermes-setup.sh"},
            "script set changed — update the gate deliberately",
        )

    def test_model_rewriters_found(self):
        # Empty set must FAIL, not silently pass: a refactor that moves the
        # rewriters out of heredocs would otherwise make every test below
        # assert nothing.
        self.assertGreaterEqual(
            len(model_rewriters()), 3,
            "expected the primary_model rewriters in setup/optimize/launch",
        )


class TestConfigRewriteSafety(unittest.TestCase):
    """The AICP-critical control: rewrite the model, keep everything else."""

    def setUp(self):
        self.rewriters = model_rewriters()
        self.assertTrue(self.rewriters, "no rewriters discovered")

    def _invoke(self, body, cfg_path, model):
        # setup.sh's block takes (config, model, profile); the others take
        # (config, model). Passing a third arg is harmless to a 2-arg block.
        return run_block(body, [cfg_path, model, "default"])

    def test_sets_primary_model(self):
        for name, body in self.rewriters:
            with self.subTest(script=name):
                cfg = write_config(FIXTURE_CONFIG)
                r = self._invoke(body, cfg, "llama3.3:70b")
                self.assertEqual(r.returncode, 0, r.stderr)
                out = Path(cfg).read_text()
                os.unlink(cfg)
                self.assertIn("primary_model: llama3.3:70b\n", out)
                self.assertNotIn("hermes-qwen-64k-fixed:latest\nprimary", out)

    def test_every_unrelated_line_survives(self):
        """No collateral damage anywhere else in the file."""
        untouched = [
            "primary_provider: ollama",
            "context_window: 32768",
            "temperature: 0.7",
            "max_turns: 40",
            "memory_enabled: true",
            "  host: http://127.0.0.1:11435",
            "display:",
            "  interface: cli",
            "  theme: dark",
            "mcp_servers:",
            "  aicp-router:",
            "    command: python3",
            '    args: ["-m", "aicp.router"]',
            "delegation:",
            "  default_lane: local",
        ]
        for name, body in self.rewriters:
            with self.subTest(script=name):
                cfg = write_config(FIXTURE_CONFIG)
                r = self._invoke(body, cfg, "llama3.3:70b")
                self.assertEqual(r.returncode, 0, r.stderr)
                out = Path(cfg).read_text()
                os.unlink(cfg)
                for line in untouched:
                    self.assertIn(line + "\n", out, f"{name} destroyed: {line!r}")
                self.assertEqual(
                    len(out.splitlines()), len(FIXTURE_CONFIG.splitlines()),
                    f"{name} changed the line count of the config",
                )

    def test_empty_value_does_not_swallow_next_line(self):
        """A key with no value must not eat the line beneath it.

        `\\s*` spans newlines, so a greedy trailing-value match on an empty
        `default_model:` can consume the following line entirely. That is
        silent config destruction, so it is pinned here.
        """
        cfg_text = FIXTURE_CONFIG.replace(
            "  default_model: hermes-qwen-64k-fixed:latest\n", "  default_model:\n"
        )
        for name, body in self.rewriters:
            with self.subTest(script=name):
                cfg = write_config(cfg_text)
                r = self._invoke(body, cfg, "llama3.3:70b")
                self.assertEqual(r.returncode, 0, r.stderr)
                out = Path(cfg).read_text()
                os.unlink(cfg)
                self.assertIn("  host: http://127.0.0.1:11435\n", out,
                              f"{name} swallowed the line after an empty key")

    def test_idempotent(self):
        for name, body in self.rewriters:
            with self.subTest(script=name):
                cfg = write_config(FIXTURE_CONFIG)
                self._invoke(body, cfg, "llama3.3:70b")
                once = Path(cfg).read_text()
                self._invoke(body, cfg, "llama3.3:70b")
                twice = Path(cfg).read_text()
                os.unlink(cfg)
                self.assertEqual(once, twice, f"{name} is not idempotent")

    def test_config_without_the_key_is_untouched(self):
        text = "some_other: value\nanother: 3\n"
        for name, body in self.rewriters:
            with self.subTest(script=name):
                cfg = write_config(text)
                r = self._invoke(body, cfg, "llama3.3:70b")
                self.assertEqual(r.returncode, 0, r.stderr)
                out = Path(cfg).read_text()
                os.unlink(cfg)
                self.assertEqual(out, text,
                                 f"{name} mutated a config that lacks the key")

    def test_model_name_with_regex_metacharacters(self):
        """Model tags contain `.` and `:`; a name must never be a live pattern."""
        for name, body in self.rewriters:
            with self.subTest(script=name):
                cfg = write_config(FIXTURE_CONFIG)
                r = self._invoke(body, cfg, "qwen2.5-coder:14b-q4_K_M")
                self.assertEqual(r.returncode, 0, r.stderr)
                out = Path(cfg).read_text()
                os.unlink(cfg)
                self.assertIn("primary_model: qwen2.5-coder:14b-q4_K_M\n", out)


class TestSetupWizardInvariants(unittest.TestCase):
    def test_backs_up_config_before_writing(self):
        body = (SCRIPTS / "hermes-setup.sh").read_text()
        self.assertRegex(
            body, r'cp "\$CONFIG" "\$CONFIG\.bak\.',
            "setup wizard must snapshot config.yaml before rewriting it",
        )
        self.assertLess(
            body.index('cp "$CONFIG" "$CONFIG.bak.'),
            body.index("<<'PYEOF'"),
            "the backup must happen BEFORE the first rewrite, not after",
        )

    def test_interface_rewrite_is_scoped(self):
        blocks = [b for b in embedded_python_blocks(SCRIPTS / "hermes-setup.sh")
                  if "interface" in b]
        self.assertEqual(len(blocks), 1)
        cfg = write_config(FIXTURE_CONFIG)
        r = run_block(blocks[0], [cfg])
        self.assertEqual(r.returncode, 0, r.stderr)
        out = Path(cfg).read_text()
        os.unlink(cfg)
        self.assertIn("  interface: dashboard\n", out)
        self.assertIn("  theme: dark\n", out)
        self.assertEqual(len(out.splitlines()), len(FIXTURE_CONFIG.splitlines()))


class TestShellHygiene(unittest.TestCase):
    def test_scripts_are_strict(self):
        scripts = sorted(SCRIPTS.glob("*.sh"))
        self.assertTrue(scripts, "no scripts examined")
        for s in scripts:
            with self.subTest(script=s.name):
                self.assertIn("set -euo pipefail", s.read_text())

    def test_no_dangerous_constructs(self):
        banned = [
            (r"rm\s+-rf\s+", "unguarded rm -rf"),
            (r"\beval\b", "eval"),
            (r"curl[^\n|]*\|\s*(ba)?sh", "curl | sh"),
            (r"sudo\b", "sudo"),
        ]
        scripts = sorted(SCRIPTS.glob("*.sh"))
        self.assertTrue(scripts, "no scripts examined")
        for s in scripts:
            text = s.read_text()
            for pat, label in banned:
                with self.subTest(script=s.name, pattern=label):
                    self.assertIsNone(re.search(pat, text), f"{label} in {s.name}")


class TestLocalOnlyNetworking(unittest.TestCase):
    """This is a localhost tool. Nothing here may listen on or call out to a
    non-loopback address."""

    def test_backend_binds_loopback(self):
        text = (REPO / "backend" / "main.py").read_text()
        self.assertIn("host, port = '127.0.0.1', 7788", text)
        self.assertNotIn("0.0.0.0", text)

    def test_client_hosts_are_loopback(self):
        urls = []
        for f in [REPO / "data.js", REPO / "index.html"]:
            urls += re.findall(r"https?://[A-Za-z0-9_.:\-]+", f.read_text())
        self.assertTrue(urls, "no URLs examined")
        for u in urls:
            with self.subTest(url=u):
                self.assertRegex(u, r"^http://(127\.0\.0\.1|localhost)(:\d+)?$")

    def test_ollama_port_is_the_portfolio_port(self):
        # The portfolio runs Ollama on 11435, not the 11434 default.
        for f in [REPO / "data.js", REPO / "index.html",
                  SCRIPTS / "hermes-launch.sh", SCRIPTS / "hermes-optimize.sh",
                  SCRIPTS / "hermes-setup.sh"]:
            text = f.read_text()
            with self.subTest(file=f.name):
                self.assertNotIn("11434", text)


class TestBackend(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(REPO / "backend"))
        import importlib
        cls.main = importlib.import_module("main")
        cls.server = HTTPServer(("127.0.0.1", 0), cls.main.Handler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path):
        url = f"http://127.0.0.1:{self.port}{path}"
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                return r.status, json.loads(r.read()), dict(r.headers)
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read()), dict(e.headers)

    def test_system_stats_contract(self):
        stats = self.main.system_stats()
        for key in ("cpu_cores", "cpu_pct", "ram_total_gb",
                    "ram_used_gb", "ram_used_pct", "platform"):
            self.assertIn(key, stats)
        self.assertGreater(stats["cpu_cores"], 0)
        self.assertGreater(stats["ram_total_gb"], 0)

    def test_health(self):
        code, body, _ = self.get("/health")
        self.assertEqual(code, 200)
        self.assertTrue(body["ok"])

    def test_system_endpoint(self):
        code, body, headers = self.get("/system")
        self.assertEqual(code, 200)
        self.assertIn("cpu_cores", body)
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "*")

    def test_unknown_path_404s(self):
        code, body, _ = self.get("/etc/passwd")
        self.assertEqual(code, 404)
        self.assertEqual(body["error"], "not found")

    def test_fallback_path_returns_same_contract(self):
        """psutil is optional; the sysctl fallback must not drop keys."""
        saved = self.main.HAS_PSUTIL
        self.main.HAS_PSUTIL = False
        try:
            stats = self.main.system_stats()
        finally:
            self.main.HAS_PSUTIL = saved
        for key in ("cpu_cores", "cpu_pct", "ram_total_gb",
                    "ram_used_gb", "ram_used_pct", "platform"):
            self.assertIn(key, stats)
        self.assertGreater(stats["cpu_cores"], 0)


class TestRepoHygiene(unittest.TestCase):
    def test_env_is_ignored(self):
        gi = (REPO / ".gitignore").read_text()
        self.assertIn(".env", gi)

    def test_no_tracked_secrets(self):
        out = subprocess.run(["git", "ls-files"], cwd=REPO,
                             capture_output=True, text=True).stdout.split()
        self.assertTrue(out, "no tracked files examined")
        pat = re.compile(
            r"(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_\-]{30,}"
            r"|BEGIN [A-Z ]*PRIVATE KEY)")
        for rel in out:
            p = REPO / rel
            if not p.is_file():
                continue
            with self.subTest(file=rel):
                self.assertIsNone(pat.search(p.read_text(errors="ignore")))

    def test_launch_json_port_is_free_of_the_backend(self):
        cfg = json.loads((REPO / ".claude" / "launch.json").read_text())
        port = cfg["configurations"][0]["port"]
        self.assertNotEqual(port, 7788, "static server would collide with backend")


if __name__ == "__main__":
    unittest.main(verbosity=2)
