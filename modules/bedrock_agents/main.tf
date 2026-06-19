resource "aws_iam_role" "agent" {
  for_each = var.agents
  name = "${var.cluster_name}-bedrock-agent-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnLike       = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:agent/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "agent_model" {
  for_each = var.agents
  name     = "invoke-model"
  role     = aws_iam_role.agent[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = each.value.model_arn
    }]
  })
}

resource "aws_bedrockagent_agent" "this" {
  for_each = var.agents

  agent_name              = "${var.cluster_name}-${each.key}"
  agent_resource_role_arn = aws_iam_role.agent[each.key].arn
  foundation_model        = each.value.foundation_model
  instruction             = each.value.instruction
  idle_session_ttl_in_seconds = 300

  tags = {
    Project     = "agora"
    Environment = var.environment
    AgentRole   = each.key
  }
}

resource "aws_bedrockagent_agent_alias" "this" {
  for_each = var.agents

  agent_id         = aws_bedrockagent_agent.this[each.key].agent_id
  agent_alias_name = "live"
}
