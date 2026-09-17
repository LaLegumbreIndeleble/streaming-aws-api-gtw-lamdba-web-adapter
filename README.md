# Lambda Streaming — API Gateway REST + Lambda Web Adapter

Streams responses through **API Gateway REST → Lambda (Docker image) → Lambda Web Adapter**.
No SAM. No zip files. Pure OpenTofu.

Two self-contained implementations, same architecture pattern:

| Version | Language / Framework | Stream type | Folder |
|---|---|---|---|
| Python | FastAPI + uvicorn | LLM token stream (fake/Bedrock) | `python-streaming/` |
| Java | Spring Boot 3.5 + Java 25 | SSE flight search (multi-provider, AI ranking) | `java-streaming/` |

Each folder contains its own app code **and** a `terraform/` subfolder — no shared infrastructure.

---

## Architecture

```
Browser / curl
  │
  ▼
API Gateway REST  (REGIONAL, response_transfer_mode=STREAM)
  │
  ▼
Lambda  (Docker image, package_type=Image)
  │  Lambda Web Adapter v1.0.1  (AWS_LWA_INVOKE_MODE=RESPONSE_STREAM)
  │  translates HTTP ↔ Lambda runtime streaming protocol
  ▼
App (FastAPI or Spring Boot)
  │  yields SSE / chunked response
  ▼
Client receives streamed events as they are produced
```

---

## Project structure

```
streaming-aws-api-gtw-lambda-web-adapter/
├── docs/
│   └── lambda-streaming-debugging.md   ← header schema, cold start fixes, debug order
├── python-streaming/
│   ├── Dockerfile                      ← Python 3.12 + Lambda Web Adapter
│   ├── main.py                         ← FastAPI app with fake_stream() / Bedrock
│   ├── requirements.txt
│   └── terraform/                      ← ECR, Lambda, API Gateway (POST /stream)
└── java-streaming/
    ├── Dockerfile                      ← Eclipse Temurin 25 + Lambda Web Adapter
    ├── pom.xml                         ← Spring Boot 3.5.4, Java 25
    ├── src/
    ├── test-local.sh
    └── terraform/                      ← ECR, Lambda, API Gateway (GET /search/stream)
```

---

## Quick start

### Python version

```bash
cd python-streaming/terraform
tofu init
tofu apply
# output: stream_endpoint
curl -N -X POST \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Tell me something"}' \
  https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/stream
```

### Java version

```bash
cd java-streaming/terraform
tofu init
tofu apply
# output: stream_endpoint
curl -N \
  -H "Accept: text/event-stream" \
  "https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/search/stream?ai=false&seed=42"
```

---

## Prerequisites

- OpenTofu >= 1.9 + AWS provider >= 6.41
- **Docker Desktop running locally** (kreuzwerker/docker provider builds the image on your machine)
- AWS credentials with ECR, Lambda, API Gateway, IAM permissions

---

## Debugging

See [`docs/lambda-streaming-debugging.md`](docs/lambda-streaming-debugging.md) for hard-won lessons:
- Always invoke Lambda directly first, then test through API Gateway
- The API Gateway streaming prelude schema and the `Vary` header trap
- `AWS_LWA_ASYNC_INIT=true` for JVM cold start beyond the 10 s extension limit
- Which CloudWatch log groups to check for each layer
