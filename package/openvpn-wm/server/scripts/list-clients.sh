#!/bin/bash
# list-clients.sh - 输出所有证书/账号 JSON
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

EASYRSA="$EASYRSA_DIR"
INDEX="$EASYRSA/pki/index.txt"
[[ -f "$INDEX" ]] || { echo "[]"; exit 0; }

python3 - "$INDEX" "$CCD_DIR" <<'PY'
import json, os, sys, datetime
index, ccd = sys.argv[1], sys.argv[2]
out = []
for line in open(index, encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 6:
        continue
    status, _, _, _, _, subj = parts[:6]
    cn = subj.split("/CN=")[-1] if "CN=" in subj else ""
    if not cn or cn == "server":
        continue
    profile = "unknown"
    ccd_file = os.path.join(ccd, cn)
    if os.path.isfile(ccd_file):
        with open(ccd_file, encoding="utf-8", errors="replace") as f:
            for l in f:
                if l.startswith("# profile="):
                    profile = l[len("# profile="):].strip().split()[0]
                    break
    out.append({"username": cn, "cert_status": "revoked" if status == "R" else "valid", "profile": profile})
print(json.dumps(out, ensure_ascii=False, indent=2))
PY
