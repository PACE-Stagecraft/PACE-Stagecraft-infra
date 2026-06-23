# ── Secrets Manager ──────────────────────────────────────────────────
# Per-service secrets (api / webhook / worker / frontend). Auto-generated
# values (DATABASE_URL, SECRET_KEY, SQS_QUEUE_URL) are written by Terraform;
# GitHub OAuth + Bedrock agent fields are left empty and filled manually in
# the console (the module uses ignore_changes so applies never overwrite them).

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

# Shared secret for service-to-service calls into agora-api's /internal/*
# routes (currently: agora-mcp-github's search_remediations tool, used by
# agora-worker's Investigator Agent). Both api and mcp-github read the same
# value; rotating it means re-applying Terraform, which writes a new value
# to both secrets at once so they never drift out of sync.
resource "random_password" "internal_api_key" {
  length  = 48
  special = false
}

module "secrets" {
  source        = "../../modules/secrets"
  environment   = local.env
  service_names = ["api", "webhook", "worker", "frontend", "mcp-github"]

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
      INTERNAL_API_KEY      = random_password.internal_api_key.result
      WORKER_INTERNAL_URL   = "http://agora-worker-agora-worker.agora.svc.cluster.local:8080"
      # Pipeline Chat (Feature 3) — assume Bedrock-account Bedrock role.
      # Fill manually in AWS Secrets Manager after first apply.
      BEDROCK_CROSS_ACCOUNT_ROLE_ARN = ""
    }
    webhook = {
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      SQS_QUEUE_URL         = module.sqs.queue_url
    }
    worker = {
      DATABASE_URL     = "postgresql://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL        = "redis://redis.agora.svc.cluster.local:6379/0"
      SQS_QUEUE_URL    = module.sqs.queue_url
      SECRET_KEY       = random_password.secret_key.result
      USE_MULTI_AGENT  = "true"
      INTERNAL_API_KEY = random_password.internal_api_key.result
      FRONTEND_URL     = var.frontend_url
      # "AI suggested a fix" email notification. Off by default — the SES
      # account is in Sandbox mode and no sender identity is verified yet
      # (checked 2026-06-23: domain verification shows TemporaryFailure).
      # Flip to "true" and fill SES_FROM_EMAIL manually once a real sender
      # identity is verified and SES production access is granted.
      SES_ENABLED    = "false"
      SES_FROM_EMAIL = ""
      # Fill these manually in AWS Secrets Manager after first apply.
      # They are permanent (survive Bedrock account cleanup) so only need setting once.
      BEDROCK_CROSS_ACCOUNT_ROLE_ARN           = ""
      BEDROCK_AGENT_ID_CLASSIFIER              = ""
      BEDROCK_AGENT_ID_ROOT_CAUSE              = ""
      BEDROCK_AGENT_ID_YAML_FIXER              = ""
      BEDROCK_AGENT_ID_SECURITY_REVIEWER       = ""
      BEDROCK_AGENT_ID_PR_WRITER               = ""
      BEDROCK_AGENT_ALIAS_ID_CLASSIFIER        = ""
      BEDROCK_AGENT_ALIAS_ID_ROOT_CAUSE        = ""
      BEDROCK_AGENT_ALIAS_ID_YAML_FIXER        = ""
      BEDROCK_AGENT_ALIAS_ID_SECURITY_REVIEWER = ""
      BEDROCK_AGENT_ALIAS_ID_PR_WRITER         = ""
    }
    frontend = {
      NEXTAUTH_SECRET      = random_password.secret_key.result
      GITHUB_CLIENT_ID     = var.github_client_id
      GITHUB_CLIENT_SECRET = var.github_client_secret
    }
    "mcp-github" = {
      INTERNAL_API_KEY = random_password.internal_api_key.result
      AGORA_API_URL    = "http://agora-api-agora-api.agora.svc.cluster.local:8000"
      # Fill manually after first apply if minting GitHub App installation
      # tokens server-side is needed; today's only wired client path passes
      # github_token through from the caller (OAuth), so these can stay
      # empty.
      GITHUB_APP_ID          = ""
      GITHUB_APP_PRIVATE_KEY = ""
      ALLOWED_ORG            = ""
    }
  }
}
