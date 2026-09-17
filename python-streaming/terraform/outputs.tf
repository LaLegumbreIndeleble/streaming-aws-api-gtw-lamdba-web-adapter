output "stream_endpoint" {
  description = "Full URL for the streaming POST endpoint"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/stream"
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
  description = "Quick curl to test the streaming endpoint"
  value       = <<-EOT
    curl -N -X POST \
      -H "Content-Type: application/json" \
      -d '{"prompt":"Tell me something interesting"}' \
      ${aws_api_gateway_stage.prod.invoke_url}/stream
  EOT
}
