variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "python-streaming"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB (512 MB minimum recommended for Docker images)"
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda execution timeout in seconds. Raise to 300–900 for real LLM calls."
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}
