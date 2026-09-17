# ─────────────────────────────────────────────
#  CloudWatch log group
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
}

# ─────────────────────────────────────────────
#  Lambda function — Docker image packaging
#
#  Key differences vs zip-based Lambda:
#    • package_type = "Image"          (not Zip)
#    • image_uri    = ECR image URL    (not filename/handler/runtime)
#    • No handler or runtime fields
# ─────────────────────────────────────────────

resource "aws_lambda_function" "streaming" {
  function_name = "${var.project_name}-${var.environment}"
  description   = "Spring Boot SSE flight search streaming via Lambda Web Adapter + Docker"

  # Docker image packaging
  package_type = "Image"
  image_uri    = docker_registry_image.app.name

  # Resources — JVM needs headroom above 512 MB
  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  # Execution role
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      # Lambda Web Adapter reads these at startup (already baked into image,
      # but explicit here makes them visible in Terraform state)
      AWS_LWA_INVOKE_MODE          = "RESPONSE_STREAM"
      AWS_LWA_READINESS_CHECK_PATH = "/healthz"
      PORT                         = "8000"

      # Spring Boot + JVM cold start can exceed the 10-second extension init
      # phase timeout that Lambda enforces for extensions. ASYNC_INIT=true tells
      # LWA to register the extension immediately and defer the readiness check
      # to the first invoke phase, which has the full function timeout (65 s).
      AWS_LWA_ASYNC_INIT = "true"
    }
  }

  # CloudWatch logging
  logging_config {
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
    log_format = "JSON"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_ecr_readonly,
    aws_cloudwatch_log_group.lambda_logs,
    docker_registry_image.app,   # image must exist in ECR before Lambda is created
  ]
}

# ─────────────────────────────────────────────
#  Permission — API Gateway → Lambda
# ─────────────────────────────────────────────

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.streaming.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
