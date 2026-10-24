#!/usr/bin/env python3
"""Render fixed source assets into deterministic EC2 UserData; no credentials."""
import argparse
import base64
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument("--output", type=Path, required=True)
a = p.parse_args()
text = (ROOT / "deploy/user-data.sh.tpl").read_text()
for token, path in {"INDEX": "app/index.html", "NGINX": "deploy/nginx.conf", "COMPOSE": "deploy/compose.yaml"}.items():
    text = text.replace("@@" + token + "_B64@@", base64.b64encode((ROOT / path).read_bytes()).decode())
assert "@@" not in text, "Unresolved template marker"
payload = text.encode()
assert len(payload) <= 16384, "EC2 UserData exceeds 16 KiB"
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_bytes(payload)
