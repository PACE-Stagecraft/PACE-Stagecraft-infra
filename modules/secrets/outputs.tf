output "secret_arns" {
  description = "Map of service_key => Secrets Manager secret ARN"
  value       = { for k, v in aws_secretsmanager_secret.service : k => v.arn }
}

output "secret_names" {
  description = "Map of service_key => Secrets Manager secret name (path)"
  value       = { for k, v in aws_secretsmanager_secret.service : k => v.name }
}
