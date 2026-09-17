# ─────────────────────────────────────────────────────────────────────────────
#  Lambda Web Adapter — streaming FastAPI image
#
#  Lambda Web Adapter sits as a Lambda extension and proxies HTTP between
#  the Lambda runtime and our FastAPI/uvicorn process.
#  Setting AWS_LWA_INVOKE_MODE=RESPONSE_STREAM enables streaming passthrough.
# ─────────────────────────────────────────────────────────────────────────────

FROM public.ecr.aws/docker/library/python:3.12-slim

# Install Lambda Web Adapter extension binary
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.8.4 \
     /lambda-adapter /opt/extensions/lambda-adapter

WORKDIR /app

# Install Python deps first (layer cache-friendly)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Tell Lambda Web Adapter which port our app listens on (default 8080)
ENV PORT=8080

# Tell Lambda Web Adapter to use streaming mode
ENV AWS_LWA_INVOKE_MODE=RESPONSE_STREAM

# Lambda Web Adapter health-check path (called before traffic is sent)
ENV AWS_LWA_READINESS_CHECK_PATH=/health

CMD ["python", "main.py"]
