output "region" {
  value = var.region
}

output "connect_instance_id" {
  description = "Amazon Connect instance id (used by the CLI wiring scripts)."
  value       = aws_connect_instance.this.id
}

output "connect_instance_arn" {
  value = aws_connect_instance.this.arn
}

output "connect_instance_alias" {
  value = aws_connect_instance.this.instance_alias
}

output "agent_name" {
  description = "Display name for the self-service AI agent / bot."
  value       = var.agent_name
}

output "company_name" {
  value = var.company_name
}

# Phone-number claiming is commented out in connect.tf. These outputs return
# empty so the wiring scripts skip auto-association; claim/assign a number in the
# console. Re-enable alongside the aws_connect_phone_number resource if desired.
output "phone_number" {
  description = "Claimed inbound DID (empty: phone claiming is disabled)."
  value       = ""
}

output "phone_number_id" {
  value = ""
}

output "escalation_queue_arn" {
  value = aws_connect_queue.escalation.arn
}

output "inbound_flow_id" {
  value = aws_connect_contact_flow.inbound.contact_flow_id
}

output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}

output "admin_login" {
  description = "Default Connect admin username."
  value       = aws_connect_user.admin.name
}

output "agent_login" {
  description = "Default Connect agent username."
  value       = aws_connect_user.agent.name
}

output "user_password" {
  description = "Default password for both Connect users (terraform output -raw user_password)."
  value       = var.connect_user_password
  sensitive   = true
}

output "tool_lambda_arns" {
  description = "ARNs of the order-lookup and refund tool Lambdas."
  value       = { for k, fn in aws_lambda_function.tool : k => fn.arn }
}
