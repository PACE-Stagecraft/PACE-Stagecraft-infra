
module "api_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-stagecraft-api"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.kubernetes_namespace}:stagecraft-api"]
    }
  }

  role_policy_arns = {
    bedrock = aws_iam_policy.bedrock.arn
    secrets = aws_iam_policy.secrets_read.arn
  }
}


module "webhook_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-stagecraft-webhook"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.kubernetes_namespace}:stagecraft-webhook"]
    }
  }

}

module "worker_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-stagecraft-worker"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.kubernetes_namespace}:stagecraft-worker"]
    }
  }

  role_policy_arns = {
    bedrock = aws_iam_policy.bedrock.arn
  }
}

module "external_secrets_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    secrets_read = aws_iam_policy.secrets_read.arn
  }
}

resource "aws_iam_policy" "bedrock" {
  name = "${var.cluster_name}-bedrock-invoke"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = var.bedrock_model_arn
      }
    ]
  })
}

resource "aws_iam_policy" "secrets_read" {
  name = "${var.cluster_name}-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:stagecraft/*"
    }]
  })
}
