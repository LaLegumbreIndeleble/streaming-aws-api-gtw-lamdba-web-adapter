#!/usr/bin/env bash
# Usage:
#   ./test-local.sh          # flights only (no AI)
#   ./test-local.sh --ai     # flights held until scored, arrive with ★ score
#
# Visual UI (requires container running on port 8000):
#   cd .. && python3 -m http.server 3000 --directory scripts/
#   open http://localhost:3000/flight-search.html
#
# Opening flight-search.html directly as a file:// may be blocked by Chrome CORS.
# Serving it via python3 http.server on any port avoids this.
set -euo pipefail

AI="false"
if [[ "${1:-}" == "--ai" ]]; then AI="true"; fi
BASE_URL="http://localhost:8000"
SEED=42

python3 - "$BASE_URL" "$AI" "$SEED" <<'EOF'
import sys, json, time, urllib.request

base_url, ai, seed = sys.argv[1], sys.argv[2], sys.argv[3]
url = f"{base_url}/search/stream?ai={ai}&seed={seed}"

print(f"  Endpoint : {url}")
if ai == "true":
    print("  Mode     : AI on — backend holds each flight until scored, then streams")
    print("             JetBlue scored ~6.5-8s, Delta ~11.5-13s, ..., AirChina ~31.5-33s")
else:
    print("  Mode     : AI off — flights stream immediately as providers respond")
    print("             JetBlue@5s  Delta@10s  United@15s  American@22s  AirChina@30s")
print("─" * 72)

start   = time.time()
ranking = {}   # flightId -> score, rebuilt after each arrival

try:
    with urllib.request.urlopen(url) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            elapsed = time.time() - start
            ts = f"[+{elapsed:5.1f}s]"

            if data == "[DONE]":
                print(f"\n{ts}  ✓  Stream complete")
                break

            try:
                d = json.loads(data)
            except Exception:
                continue

            kind = d.get("type")

            if kind == "meta":
                print(f"{ts}  ℹ  Expecting {d['totalFlights']} flights\n")

            elif kind == "flight":
                score = d.get("score")
                stops = "nonstop" if d["stops"] == 0 else f"{d['stops']} stop(s)"
                score_col = f"  ★{score:3}" if score is not None else "      "
                print(
                    f"{ts}  ✈  {d['airline']:<11}"
                    f"  {d['from']} → {d['to']}"
                    f"  {d['departure']:<10} → {d['arrival']:<10}"
                    f"  {d['duration']:<8}"
                    f"  {stops:<12}"
                    f"  {d['price']}"
                    f"{score_col}"
                )
                if score is not None:
                    ranking[d["flightId"]] = score
                    top3 = sorted(ranking.items(), key=lambda x: -x[1])[:3]
                    row  = "  ".join(f"{fid.split('-')[0]}({s})" for fid, s in top3)
                    print(f"{'':>14}  top: {row}")

            sys.stdout.flush()

except KeyboardInterrupt:
    print("\nAborted.")
except Exception as e:
    print(f"\nError: {e}")
    sys.exit(1)
EOF
