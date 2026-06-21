# ── Secrets Manager ──────────────────────────────────────────────────
# Per-service secrets. Auto-generated values written by Terraform; GitHub
# OAuth fields filled manually in the console (module uses ignore_changes).
#
# NOTE: Unlike dev, the worker secret here does NOT yet include the
# cross-account Bedrock fields (BEDROCK_CROSS_ACCOUNT_ROLE_ARN, agent IDs,
# USE_MULTI_AGENT). Align with dev/secrets.tf before deploying prod.

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

module "secrets" {
  source        = "../../modules/secrets"
  environment   = local.env
  service_names = ["api", "webhook", "worker", "frontend"]

  secrets = {
    api = {
      DATABASE_URL          = "postgresql+asyncpg://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL             = "redis://redis.agora.svc.cluster.local:6379/0"
      GITHUB_CLIENT_ID      = var.github_client_id
      GITHUB_CLIENT_SECRET  = var.github_client_secret
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      GITHUB_REDIRECT_URI   = "${var.frontend_url}/api/auth/callback"
      FRONTEND_URL          = var.frontend_url
      SQS_QUEUE_URL         = module.sqs.queue_url
      SECRET_KEY            = random_password.secret_key.result
    }
    webhook = {
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      SQS_QUEUE_URL         = module.sqs.queue_url
    }
    worker = {
      DATABASE_URL  = "postgresql://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL     = "redis://redis.agora.svc.cluster.local:6379/0"
      SQS_QUEUE_URL = module.sqs.queue_url
      SECRET_KEY    = random_password.secret_key.result
    }
    frontend = {
      NEXTAUTH_SECRET      = random_password.secret_key.result
      GITHUB_CLIENT_ID     = var.github_client_id
      GITHUB_CLIENT_SECRET = var.github_client_secret
    }
  }
}
