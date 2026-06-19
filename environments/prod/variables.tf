variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "agora-dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "domain_name" {
  description = "Root domain name (e.g. agora.example.com)"
  type        = string
  default     = ""
}

variable "github_client_id" {
  description = "GitHub OAuth App client ID"
  type        = string
  sensitive   = true
}

variable "github_client_secret" {
  description = "GitHub OAuth App client secret"
  type        = string
  sensitive   = true
}

variable "github_webhook_secret" {
  description = "Shared secret for verifying GitHub webhook HMAC signatures"
  type        = string
  sensitive   = true
}

variable "frontend_url" {
  description = "Public URL of the frontend (used for OAuth redirects and CORS)"
  type        = string
  default     = "https://agora.example.com"
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications (DLQ depth, etc.)"
  type        = string
}

