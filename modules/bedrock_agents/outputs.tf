output "agent_ids" {
  value = { for k, v in aws_bedrockagent_agent.this : k => v.agent_id }
}

output "agent_alias_ids" {
  value = { for k, v in aws_bedrockagent_agent_alias.this : k => v.agent_alias_id }
}
