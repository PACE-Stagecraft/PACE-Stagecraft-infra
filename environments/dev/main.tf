locals {
  name   = var.cluster_name
  region = var.aws_region
  env    = "dev"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  create_database_subnet_group = true

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    app = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
      labels         = { role = "app" }
    }
    worker = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      labels         = { role = "worker" }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_irsa = true
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  db_name  = "agora"
  username = "agora"
  password = random_password.db_password.result

  allocated_storage = 20
  storage_type      = "gp2"

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.eks.node_security_group_id]

  skip_final_snapshot        = false
  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  publicly_accessible        = false
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.2"

  for_each = toset(["agora-api", "agora-webhook", "agora-worker", "agora-frontend", "agora-mcp-aws", "agora-mcp-github"])

  repository_name                 = each.key
  repository_image_tag_mutability = "IMMUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

module "iam" {
  source = "../../modules/iam"

  cluster_name         = local.name
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider
  aws_region           = var.aws_region
  account_id           = data.aws_caller_identity.current.account_id
  kubernetes_namespace = "agora"
  bedrock_model_arn    = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0"
}

locals {
  nova_pro_arn   = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0"
  nova_lite_arn  = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-lite-v1:0"
  nova_micro_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-micro-v1:0"
}

module "bedrock_agents" {
  source       = "../../modules/bedrock_agents"
  cluster_name = local.name
  environment  = local.env
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id

  agents = {
    classifier = {
      foundation_model = "amazon.nova-micro-v1:0"
      model_arn        = local.nova_micro_arn
      instruction      = "You are a CI/CD failure classifier. Given workflow logs and YAML, respond with exactly one category: DEPENDENCY_VERSION | AUTH_FAILURE | NETWORK_TIMEOUT | CONFIG_ERROR | TEST_FAILURE | BUILD_ERROR | LINT_ERROR | PERMISSION_ERROR | UNKNOWN. No explanation, just the category."
    }
    root_cause = {
      foundation_model = "amazon.nova-pro-v1:0"
      model_arn        = local.nova_pro_arn
      instruction      = "You are a DevOps root cause analyst. Given a GitHub Actions failure category, workflow YAML, and logs, identify the specific root cause. Always respond in JSON: {\"root_cause\": \"...\", \"severity\": \"low|medium|high|critical\"}."
    }
    yaml_fixer = {
      foundation_model = "amazon.nova-pro-v1:0"
      model_arn        = local.nova_pro_arn
      instruction      = "You are a GitHub Actions workflow YAML expert. Given a root cause and the original workflow YAML, generate the corrected workflow YAML. Return ONLY valid YAML — no markdown fences, no commentary."
    }
    security_reviewer = {
      foundation_model = "amazon.nova-pro-v1:0"
      model_arn        = local.nova_pro_arn
      instruction      = "You are a DevSecOps expert. Review a proposed GitHub Actions YAML fix for security issues: hardcoded secrets, unpinned action SHAs, overbroad permissions, dangerous shell commands. Respond in JSON: {\"risk_score\": 0-10, \"findings\": [\"...\", ...]}."
    }
    pr_writer = {
      foundation_model = "amazon.nova-lite-v1:0"
      model_arn        = local.nova_lite_arn
      instruction      = "You write clear GitHub pull request titles and descriptions for AI-suggested CI/CD fixes. Given root cause, failure category, and security findings, respond in JSON: {\"title\": \"fix: ...\", \"body\": \"## Root Cause\\n...\"}."
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn

  depends_on = [module.eks, module.ebs_csi_irsa]
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "amazon-cloudwatch-observability"
  service_account_role_arn = module.iam.cloudwatch_observability_role_arn

  depends_on = [module.eks, module.iam]
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

module "sqs" {
  source = "../../modules/sqs"

  name               = "agora-webhooks"
  environment        = local.env
  max_receive_count  = 3
  sender_role_arn    = module.iam.webhook_role_arn
  consumer_role_arn  = module.iam.worker_role_arn
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}

resource "aws_iam_policy" "sqs_send" {
  name = "${local.name}-sqs-send"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
      Resource = module.sqs.queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "webhook_sqs_send" {
  role       = module.iam.webhook_role_name
  policy_arn = aws_iam_policy.sqs_send.arn
}

resource "aws_iam_policy" "sqs_consume" {
  name = "${local.name}-sqs-consume"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = module.sqs.queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_sqs_consume" {
  role       = module.iam.worker_role_name
  policy_arn = aws_iam_policy.sqs_consume.arn
}

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

module "secrets" {
  source         = "../../modules/secrets"
  environment    = local.env
  service_names  = ["api", "webhook", "worker", "frontend"]

  secrets = {
    api = {
      DATABASE_URL           = "postgresql+asyncpg://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL               = "redis://redis.agora.svc.cluster.local:6379/0"
      GITHUB_CLIENT_ID        = var.github_client_id
      GITHUB_CLIENT_SECRET    = var.github_client_secret
      GITHUB_WEBHOOK_SECRET   = var.github_webhook_secret
      GITHUB_REDIRECT_URI     = "${var.frontend_url}/api/auth/callback"
      FRONTEND_URL            = var.frontend_url
      SQS_QUEUE_URL           = module.sqs.queue_url
      SECRET_KEY              = random_password.secret_key.result
    }
    webhook = {
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      SQS_QUEUE_URL         = module.sqs.queue_url
    }
    worker = {
      DATABASE_URL             = "postgresql://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL                = "redis://redis.agora.svc.cluster.local:6379/0"
      SQS_QUEUE_URL            = module.sqs.queue_url
      SECRET_KEY               = random_password.secret_key.result
      USE_MULTI_AGENT          = "true"
      BEDROCK_AGENT_ID_CLASSIFIER       = module.bedrock_agents.agent_ids["classifier"]
      BEDROCK_AGENT_ID_ROOT_CAUSE       = module.bedrock_agents.agent_ids["root_cause"]
      BEDROCK_AGENT_ID_YAML_FIXER       = module.bedrock_agents.agent_ids["yaml_fixer"]
      BEDROCK_AGENT_ID_SECURITY_REVIEWER = module.bedrock_agents.agent_ids["security_reviewer"]
      BEDROCK_AGENT_ID_PR_WRITER        = module.bedrock_agents.agent_ids["pr_writer"]
      BEDROCK_AGENT_ALIAS_ID_CLASSIFIER        = module.bedrock_agents.agent_alias_ids["classifier"]
      BEDROCK_AGENT_ALIAS_ID_ROOT_CAUSE        = module.bedrock_agents.agent_alias_ids["root_cause"]
      BEDROCK_AGENT_ALIAS_ID_YAML_FIXER        = module.bedrock_agents.agent_alias_ids["yaml_fixer"]
      BEDROCK_AGENT_ALIAS_ID_SECURITY_REVIEWER = module.bedrock_agents.agent_alias_ids["security_reviewer"]
      BEDROCK_AGENT_ALIAS_ID_PR_WRITER         = module.bedrock_agents.agent_alias_ids["pr_writer"]
    }
    frontend = {
      NEXTAUTH_SECRET       = random_password.secret_key.result
      GITHUB_CLIENT_ID      = var.github_client_id
      GITHUB_CLIENT_SECRET  = var.github_client_secret
    }
  }
}

resource "aws_security_group" "bedrock_vpce" {
  name        = "${local.name}-bedrock-vpce"
  description = "Allow HTTPS from within the VPC to Bedrock interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_vpc_endpoint" "bedrock" {
  for_each = toset(["bedrock", "bedrock-runtime", "bedrock-agent-runtime"])

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.bedrock_vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name}-${each.key}-vpce"
  }
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.3"

  count = var.domain_name != "" ? 1 : 0

  domain_name = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]

  create_route53_records = true
  validation_method       = "DNS"
  wait_for_validation      = true
}

resource "aws_wafv2_web_acl" "main" {
  name  = "${local.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU above 80% for 15 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648
  alarm_description   = "RDS free storage below 2 GiB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}


resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "RDS CPU & Connections"
          region  = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.identifier],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "SQS Queue Depth (main + DLQ)"
          region  = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "agora-webhooks"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "agora-webhooks-dlq"],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "EKS Cluster CPU & Memory (Container Insights)"
          region  = var.aws_region
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", local.name],
            ["ContainerInsights", "node_memory_utilization", "ClusterName", local.name],
          ]
        }
      },
    ]
  })
}

