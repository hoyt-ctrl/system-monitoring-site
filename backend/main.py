#!/usr/bin/env python3
"""
Hermes Monitor backend — serves system stats to the dashboard.
Usage: python3 backend/main.py
Listens on http://127.0.0.1:7788
"""
import json, platform, time
from http.server import BaseHTTPRequestHandler, HTTPServer

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

def system_stats():
    if HAS_PSUTIL:
        vm = psutil.virtual_memory()
        return {
            "cpu_cores":    psutil.cpu_count(logical=True),
            "cpu_pct":      psutil.cpu_percent(interval=0.2),
            "ram_total_gb": vm.total / 1073741824,
            "ram_used_gb":  vm.used  / 1073741824,
            "ram_used_pct": vm.percent,
            "platform":     platform.mac_ver()[0] or platform.system(),
        }
    # fallback without psutil (macOS sysctl)
    import subprocess, re
    try:
        cores = int(subprocess.check_output(['sysctl','-n','hw.ncpu']).strip())
        mem   = int(subprocess.check_output(['sysctl','-n','hw.memsize']).strip())
    except Exception:
        cores, mem = 1, 8 * 1073741824
    return {
        "cpu_cores":    cores,
        "cpu_pct":      0,
        "ram_total_gb": mem / 1073741824,
        "ram_used_gb":  0,
        "ram_used_pct": 0,
        "platform":     platform.mac_ver()[0] or platform.system(),
        "note":         "install psutil for live RAM usage: pip3 install psutil"
    }

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silence default access log

    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,OPTIONS')
        self.end_headers()

    def do_GET(self):
        if self.path == '/system':
            self.send_json(200, system_stats())
        elif self.path == '/health':
            self.send_json(200, {"ok": True, "ts": time.time()})
        else:
            self.send_json(404, {"error": "not found"})

if __name__ == '__main__':
    host, port = '127.0.0.1', 7788
    print(f'Hermes Monitor backend → http://{host}:{port}')
    if not HAS_PSUTIL:
        print('  tip: pip3 install psutil   (for live CPU/RAM stats)')
    HTTPServer((host, port), Handler).serve_forever()
