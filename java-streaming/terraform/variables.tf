variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "springboot-streaming"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB (1024 MB recommended for JVM warmup)"
  type        = number
  default     = 1024
}

variable "lambda_timeout_seconds" {
  description = "Lambda execution timeout in seconds. Must exceed the slowest provider (30 s) + AI scoring delay."
  type        = number
  default     = 65
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}
