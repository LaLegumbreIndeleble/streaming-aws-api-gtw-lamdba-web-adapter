# Debugging Lambda Streaming with API Gateway REST

Lessons learned getting Spring Boot SSE streaming to work end-to-end through
API Gateway REST → Lambda Web Adapter → Spring Boot.

---

## Debugging order that matters

Always validate from the inside out. Debugging API Gateway before confirming
Lambda works wastes time chasing symptoms that originate deeper in the stack.

```
1. Lambda directly  →  2. API Gateway
```

### Step 1 — Invoke Lambda directly (bypass API Gateway)

```bash
aws lambda invoke \
  --function-name <function-name> \
  --region us-east-1 \
  --invocation-type RequestResponse \
  --payload '{
    "httpMethod": "GET",
    "path": "/search/stream",
    "queryStringParameters": {"ai": "false", "seed": "42"},
    "headers": {"Accept": "text/event-stream", "Host": "localhost"},
    "requestContext": {"httpMethod": "GET", "path": "/search/stream"}
  }' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-response.json && cat /tmp/lambda-response.json
```

Inspect the **first line** of the response. It is the streaming prelude that
API Gateway will try to parse:

```json
{"statusCode":200,"headers":{"content-type":"text/event-stream","date":"..."},"cookies":[]}
```

If the prelude looks correct, move to Step 2. If it looks wrong, fix the
Lambda function — no API Gateway change will help.

### Step 2 — Test through API Gateway

```bash
curl -N -s -w "\nHTTP_STATUS: %{http_code}\nTIME_TOTAL: %{time_total}s\n" \
  -H "Accept: text/event-stream" \
  "https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/search/stream?ai=false&seed=42" \
  --max-time 60
```

If API Gateway returns a 502, check the execution logs before changing code:

```bash
aws logs filter-log-events \
  --log-group-name "API-Gateway-Execution-Logs_<api-id>/<stage>" \
  --region us-east-1 \
  --start-time $(($(date +%s) - 300))000 \
  --query 'events[*].message' --output text | tr '\t' '\n'
```

---

## The prelude JSON schema — what API Gateway enforces

When `response_transfer_mode = "STREAM"` is set on the integration, API
Gateway parses the first bytes of the Lambda response as a JSON prelude before
forwarding the body. The schema is strict:

```json
{
  "statusCode": 200,
  "headers": {
    "headerName": "single-string-value"
  },
  "multiValueHeaders": {
    "headerName": ["value1", "value2"]
  },
  "cookies": []
}
```

**Critical rules:**

| Rule | Consequence if broken |
|---|---|
| `headers` values must be plain strings | `Failed to parse prelude JSON` (502) |
| Multi-value headers must go in `multiValueHeaders` | Same error — misleading message |
| Prelude must appear within the first 16 KB | Stream fails silently |
| Delimiter after prelude must be 8 null bytes (`\x00` × 8) | Stream body not forwarded |

---

## The Vary header trap

Spring Boot's `CorsFilter` / `CorsConfiguration` automatically adds:

```
Vary: Origin, Access-Control-Request-Method, Access-Control-Request-Headers
```

Lambda Web Adapter serializes this as an **array** in the prelude:

```json
"headers": {
  "vary": ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]
}
```

API Gateway hits the array, throws `Failed to parse prelude JSON`, and returns
a 502 — even though the JSON is syntactically valid. The error message is
misleading; the problem is a schema violation, not a syntax error.

### Fix — replace Spring's CorsFilter with a plain servlet filter

```java
@Bean
public Filter corsFilter() {
    return (req, res, chain) -> {
        HttpServletResponse r = (HttpServletResponse) res;
        r.setHeader("Access-Control-Allow-Origin", "*");
        r.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        r.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
        chain.doFilter(req, res);
    };
}
```

Setting headers directly via `HttpServletResponse.setHeader()` writes a single
string value and does not trigger Spring's automatic `Vary` injection.

Import required: `jakarta.servlet.Filter` (Jakarta EE / Spring Boot 3.x).

---

## Cold start: LWA extension init timeout

Lambda Web Adapter registers as a Lambda Extension. Extensions have a **10-second
init phase timeout**. If your JVM + framework takes longer than 10 seconds to
start on cold start, LWA times out and Lambda returns an error to the caller.

### Fix — `AWS_LWA_ASYNC_INIT=true`

Set this environment variable on the Lambda function. LWA then registers the
extension immediately and defers the readiness check to the first invoke phase,
which runs against the full function timeout (e.g. 65 seconds).

```hcl
environment {
  variables = {
    AWS_LWA_INVOKE_MODE          = "RESPONSE_STREAM"
    AWS_LWA_READINESS_CHECK_PATH = "/healthz"
    PORT                         = "8000"
    AWS_LWA_ASYNC_INIT           = "true"
  }
}
```

Spring Boot 3.x + Java 25 cold starts typically land at **6–9 seconds**. With
`ASYNC_INIT=true`, cold starts succeed reliably even when they exceed 10 seconds
on the first invocation.

---

## Terraform: force Lambda to pick up a new image

When only Java source files change (not `Dockerfile` or `pom.xml`), the Tofu
`filesha256()` triggers won't fire. Force a rebuild and Lambda update with:

```bash
# Force image rebuild and ECR push
tofu apply -replace=docker_image.app -replace=docker_registry_image.app -auto-approve

# Force Lambda to pull the new :latest digest
aws lambda update-function-code \
  --function-name <function-name> \
  --image-uri <ecr-url>:latest \
  --region us-east-1

aws lambda wait function-updated --function-name <function-name> --region us-east-1
```

To make source changes trigger automatic rebuilds, add a source directory hash
to the `triggers` block in `ecr.tf`. This can be done with a `sha256` of a
sentinel file that you touch on each meaningful change.

---

## CloudWatch log groups to check

| Log group | What it contains |
|---|---|
| `/aws/lambda/<function-name>` | LWA init events, platform.start, platform.report, Spring Boot output |
| `API-Gateway-Execution-Logs_<api-id>/<stage>` | Per-request execution trace, integration errors, prelude parse failures |
| `/aws/apigateway/<function-name>` | Access logs (request-level summary) |

The execution logs (`API-Gateway-Execution-Logs_*`) are the most useful for
diagnosing 502 errors — they show the exact error message from API Gateway's
integration processing.
