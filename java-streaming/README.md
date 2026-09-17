# java-streaming

Spring Boot 3.5 / Java 25 application that streams flight search results over **Server-Sent Events (SSE)** using the [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) pattern. Deployable as a Docker-based Lambda function or run locally as a standard container.

---

## What was built

### Problem
Traditional REST APIs return all results in one blocking response. When multiple upstream providers have different response times (5 s, 10 s, 30 s…), the user waits for the slowest one before seeing anything.

### Solution
A single persistent SSE connection streams each provider's results the moment they are ready. When AI ranking is enabled, the backend holds each flight record until its score is computed, then sends one combined event — the client never renders an unscored result.

```
Client ──── GET /search/stream?ai=true ────► Spring Boot
            ◄── data: meta (12 flights expected)
            ◄── data: JetBlue-0 {flight + score: 89}    (+6.5 s)
            ◄── data: JetBlue-1 {flight + score: 72}    (+7.1 s)
            ◄── data: JetBlue-2 {flight + score: 58}    (+7.8 s)
            ◄── data: Delta-0   {flight + score: 94}    (+11.6 s)
            ...
            ◄── data: [DONE]                            (+33 s)
```

### Key implementation decisions

| Decision | Why |
|---|---|
| **Hold flight until scored** | Client sees only ready-to-display records; no "Scoring…" loading state needed |
| **Plain `jakarta.servlet.Filter` for CORS** | Spring's `CorsFilter` injects a multi-value `Vary` header that violates the API Gateway streaming prelude schema. A raw servlet filter sets `Access-Control-Allow-*` headers directly without triggering `Vary` injection |
| **`EventSource` in the browser** | Native SSE API; handles buffering and the SSE framing protocol correctly. `fetch()+ReadableStream` is fragile across origins |
| **FLIP animation** | When a new scored card ranks higher than existing ones, all cards physically slide to their new positions using the browser's GPU layer (`will-change: transform`) |
| **Deterministic `seededScore()`** | Same seed → same scores on every run, so demos are reproducible. Port of the original Node.js hash |

---

## Project structure

```
java-streaming/
├── Dockerfile                          # Multi-stage build: Eclipse Temurin 25 → JRE 25 + Lambda Adapter
├── pom.xml                             # Spring Boot 3.5.4, Java 25
├── test-local.sh                       # Terminal test script
├── terraform/                          # OpenTofu — ECR, Lambda, API Gateway
└── src/main/
    ├── java/com/amazonaws/demo/
    │   ├── Application.java            # Boot entry point + plain servlet CORS filter
    │   └── controller/
    │       └── SearchController.java   # SSE endpoint, provider data, scoring logic
    └── resources/
        ├── application.properties      # banner off, async timeout 65 s
        ├── logback.xml
        └── static/index.html           # Minimal "API only" page (UI lives in scripts/)
```

The standalone UI lives at `../scripts/flight-search.html` — it is intentionally outside this folder so it is not baked into the Docker image.

---

## Endpoint

```
GET /search/stream?ai=false&seed=0
```

| Parameter | Default | Description |
|---|---|---|
| `ai` | `false` | When `true`, backend scores each flight before emitting it |
| `seed` | `0` | Integer seed for deterministic score generation (0–99 999) |

### Event types

```jsonc
// Always sent first
{ "type": "meta", "totalFlights": 12 }

// One per flight (score field present only when ai=true)
{ "type": "flight", "flightId": "Delta-0", "airline": "Delta", "code": "DL",
  "from": "JFK", "to": "LAX", "departure": "06:00 AM", "arrival": "09:32 AM",
  "duration": "5h 32m", "stops": 0, "price": "C$534",
  "providerResponseTime": 10000, "score": 94 }

// Stream end marker
[DONE]
```

### Provider schedule

| Airline | Response delay | Flights |
|---|---|---|
| JetBlue | 5 s | 3 |
| Delta | 10 s | 3 |
| United | 15 s | 2 |
| American | 22 s | 2 |
| Air China | 30 s | 2 |

With `ai=true` each flight is held an additional 1.5–3 s for scoring before being sent.

---

## Run locally

### Prerequisites
- Docker
- Python 3 (for the browser UI)

### 1 — Build

```bash
cd java-streaming
docker build -t java-streaming .
```

> First build downloads Eclipse Temurin 25 + Maven dependencies (~5 min). Subsequent builds use the layer cache and take ~30 s.

### 2 — Run

```bash
docker run --rm -p 8000:8000 java-streaming
```

Health check:
```bash
curl http://localhost:8000/healthz
# → healthy
```

---

## Test locally

### Option A — Terminal (no browser needed)

```bash
# Flights only — providers respond at 5 s, 10 s, 15 s, 22 s, 30 s
./test-local.sh

# With AI ranking — same delays + 1.5-3 s scoring hold per flight
./test-local.sh --ai
```

Expected output with `--ai`:

```
  Endpoint : http://localhost:8000/search/stream?ai=true&seed=42
  Mode     : AI on — backend holds each flight until scored, then streams
─────────────────────────────────────────────────────────────────────────
[+ 0.0s]  ℹ  Expecting 12 flights

[+ 6.8s]  ✈  JetBlue      JFK → LAX  08:15 AM   → 11:28 AM   5h 13m   nonstop       C$489  ★ 89
              top: JetBlue(89)
[+ 7.3s]  ✈  JetBlue      JFK → LAX  01:00 PM   → 04:19 PM   5h 19m   nonstop       C$521  ★ 72
              top: JetBlue(89)  >  JetBlue(72)
...
[+11.8s]  ✈  Delta        JFK → LAX  06:00 AM   → 09:32 AM   5h 32m   nonstop       C$534  ★ 94
              top: Delta(94)  >  JetBlue(89)  >  JetBlue(72)
...
[+33.2s]  ✓  Stream complete
```

### Option B — Browser UI

The UI in `scripts/flight-search.html` uses `EventSource` (native SSE) and must be served over HTTP — opening it as `file://` is blocked by Chrome's CORS policy for localhost fetches.

```bash
# From the repo root (not inside springboot-streaming/)
python3 -m http.server 3000 --directory scripts/
```

Then open **http://localhost:3000/flight-search.html**.

Click **Search Flights**, toggle **AI Ranking** on, and watch:
1. Cards arrive progressively as providers respond
2. Each card shows its AI score badge (★ 94) the moment it appears
3. When a higher-scored card arrives, all existing cards FLIP-animate to their new positions
4. The **"Better deal found"** banner slides in above the new top result

---

## AWS deployment

The `Dockerfile` includes the Lambda Web Adapter sidecar (v1.0.1):

```dockerfile
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.0.1 \
     /lambda-adapter /opt/extensions/lambda-adapter
ENV AWS_LWA_INVOKE_MODE=response_stream
```

Deploy with OpenTofu from the `terraform/` folder inside this directory. The stack creates:
- ECR repository (builds and pushes the Docker image locally)
- Lambda function (Docker image, 1024 MB, 65 s timeout)
- API Gateway REST with `response_transfer_mode = STREAM`

```bash
cd java-streaming/terraform
tofu init
tofu apply
```

### Key Lambda environment variables

| Variable | Value | Why |
|---|---|---|
| `AWS_LWA_INVOKE_MODE` | `RESPONSE_STREAM` | Enables streaming through LWA |
| `AWS_LWA_READINESS_CHECK_PATH` | `/healthz` | LWA polls this until Spring Boot is ready |
| `AWS_LWA_ASYNC_INIT` | `true` | Prevents 10 s extension init timeout on cold start |
| `PORT` | `8000` | Matches Spring Boot's listen port |

### Test the deployed endpoint

```bash
# Flights only (30 s stream)
curl -N \
  -H "Accept: text/event-stream" \
  "https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/search/stream?ai=false&seed=42"

# With AI ranking (~33 s stream)
curl -N \
  -H "Accept: text/event-stream" \
  "https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/search/stream?ai=true&seed=42"
```

### Debugging

See `../../docs/lambda-streaming-debugging.md` (repo root) for:
- How to invoke Lambda directly to isolate issues from API Gateway
- The API Gateway streaming prelude schema and the Vary header trap
- How to read the right CloudWatch log groups
