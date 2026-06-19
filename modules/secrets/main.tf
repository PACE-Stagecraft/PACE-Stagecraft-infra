
resource "aws_secretsmanager_secret" "service" {
  for_each = toset(var.service_names)

  name        = "agora/${var.environment}/${each.key}"
  description = "aGorA ${var.environment} secrets for ${each.key}"

  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Project     = "agora"
    Environment = var.environment
    Service     = each.key
  }
}

resource "aws_secretsmanager_secret_version" "service" {
  for_each = toset(var.service_names)

  secret_id     = aws_secretsmanager_secret.service[each.key].id
  secret_string = jsonencode(var.secrets[each.key])
}
