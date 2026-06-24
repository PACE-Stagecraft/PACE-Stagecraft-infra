aws_region         = "us-east-1"
cluster_name       = "agora-dev"
vpc_cidr           = "10.0.0.0/16"
kubernetes_version = "1.30"
domain_name        = "ustbiteshub.online"
frontend_url       = "https://ustbiteshub.online"
log_retention_days = 14
enable_karpenter   = true # IAM only — see compute.tf. Apply, then enable the platform-layer Helm release + NodePool.

# dev owns the account-wide CloudTrail/GuardDuty/Config singletons (only one
# of dev/prod ever should — see variables.tf for why).
owns_account_security_baseline = true

# CloudFront + WAF (cdn.tf) — all three must be set to create the distribution.
nlb_hostname        = "a04dd7e84c4ba457a9eac93e61f3da25-727392277.us-east-1.elb.amazonaws.com"
hosted_zone_id      = "Z08675442UCHTHLJ1M7HV"
acm_certificate_arn = "arn:aws:acm:us-east-1:591316257673:certificate/a4945531-2e2b-462b-9b95-fac6cd59282d"
