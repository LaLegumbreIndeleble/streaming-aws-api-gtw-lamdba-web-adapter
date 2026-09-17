"""
Streaming Lambda — FastAPI + Lambda Web Adapter
Simplified version: streams a repeated phrase word-by-word via SSE.
Swap bedrock_stream() for a real Bedrock call when ready.
"""

import asyncio
import json
import os

import uvicorn
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional

app = FastAPI(title="Streaming Lambda")


# ── Request schema ────────────────────────────────────────────────────────────

class PromptRequest(BaseModel):
    prompt: Optional[str] = "Hello from Lambda"


# ── Fake token stream (replace with Bedrock later) ────────────────────────────

async def fake_stream(prompt: str):
    """
    Yields SSE-formatted chunks word by word with a short delay.
    Mimics the shape of a real Bedrock streaming response so the
    bash client and the wire format don't need to change.
    """
    reply = (
        f'You said: "{prompt}". '
        "This is a streaming response from AWS Lambda via FastAPI and "
        "Lambda Web Adapter. Each word arrives as a separate SSE event. "
        "Replace this function with a real Bedrock call when you are ready."
    )

    for word in reply.split(" "):
        token = word + " "
        # SSE format: data: <json>\n\n
        yield f"data: {json.dumps({'token': token})}\n\n"
        await asyncio.sleep(0.06)   # ~16 tokens/sec — feels natural

    yield f"data: {json.dumps({'done': True})}\n\n"


# ── Optional: real Bedrock stream (commented out) ─────────────────────────────
#
# import boto3
#
# bedrock = boto3.client("bedrock-runtime")
#
# async def bedrock_stream(prompt: str):
#     body = json.dumps({
#         "anthropic_version": "bedrock-2023-05-31",
#         "max_tokens": 1024,
#         "messages": [{"role": "user", "content": prompt}],
#     })
#     response = bedrock.invoke_model_with_response_stream(
#         modelId="anthropic.claude-3-haiku-20240307-v1:0",
#         body=body,
#     )
#     for event in response["body"]:
#         chunk = event.get("chunk")
#         if chunk:
#             msg = json.loads(chunk["bytes"].decode())
#             if msg["type"] == "content_block_delta":
#                 yield f"data: {json.dumps({'token': msg['delta']['text']})}\n\n"
#             elif msg["type"] == "message_stop":
#                 yield f"data: {json.dumps({'done': True})}\n\n"


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/stream")
async def stream(req: PromptRequest):
    """
    POST /stream  {"prompt": "your text"}
    Returns a text/event-stream response streamed token by token.
    """
    return StreamingResponse(
        fake_stream(req.prompt or "Hello"),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Access-Control-Allow-Origin": "*",
        },
    )


@app.options("/stream")
async def stream_options():
    """CORS preflight"""
    from fastapi.responses import Response
    return Response(
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        }
    )


# ── Entrypoint (Lambda Web Adapter uses this port) ────────────────────────────

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8080")),
    )
