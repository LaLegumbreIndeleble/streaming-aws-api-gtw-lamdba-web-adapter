output "stream_endpoint" {
  description = "Full URL for the SSE streaming GET endpoint"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/search/stream"
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.streaming.function_name
}

output "curl_test_command" {
  description = "Quick curl to test the SSE streaming endpoint (flights only)"
  value       = <<-EOT
    curl -N \
      -H "Accept: text/event-stream" \
      "${aws_api_gateway_stage.prod.invoke_url}/search/stream?ai=false&seed=42"
  EOT
}

output "curl_test_ai_command" {
  description = "Quick curl to test with AI ranking enabled"
  value       = <<-EOT
    curl -N \
      -H "Accept: text/event-stream" \
      "${aws_api_gateway_stage.prod.invoke_url}/search/stream?ai=true&seed=42"
  EOT
}
