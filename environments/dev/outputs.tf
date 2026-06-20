output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "app_secrets_arns" {
  description = "ARNs of the per-service Secrets Manager entries (agora/dev/*)"
  value       = module.secrets.secret_arns
}

output "sqs_queue_url" {
  description = "SQS queue URL for webhook events"
  value       = module.sqs.queue_url
}

output "ecr_urls" {
  description = "ECR repository URLs"
  value       = { for k, v in module.ecr : k => v.repository_url }
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI Driver"
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the EKS cluster (used by platform layer)"
  value       = module.eks.cluster_certificate_authority_data
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator (used by platform layer)"
  value       = module.iam.external_secrets_role_arn
}

output "waf_web_acl_arn" {
  description = "WAFv2 Web ACL ARN — set as the alb.ingress.kubernetes.io/wafv2-acl-arn annotation on each public Ingress (agora-helm) to actually protect the ALBs"
  value       = aws_wafv2_web_acl.main.arn
}
