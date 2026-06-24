variable "region" {
  description = "AWS region. Must be a region where Amazon Connect + Nova Sonic agentic self-service is available."
  type        = string

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "Amazon Connect + Nova Sonic agentic self-service is GA only in us-east-1 and us-west-2."
  }
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
}

variable "agent_name" {
  description = "Display name for the self-service AI agent / bot."
  type        = string
}

variable "company_name" {
  description = "Company the agent represents (used in greetings, naming/tags)."
  type        = string
}

variable "connect_instance_alias" {
  description = "Unique alias for the Amazon Connect instance (becomes part of the access URL). Must be globally unique."
  type        = string
}

variable "claim_phone_number" {
  description = "Whether to claim a DID phone number. Set false if no DIDs are available in the region or you want to claim manually."
  type        = bool
}

variable "phone_country_code" {
  description = "ISO country code for the claimed DID."
  type        = string
}

variable "lambda_runtime" {
  description = "Python runtime for the tool Lambdas."
  type        = string
}

variable "admin_username" {
  description = "Login name for the default Connect admin user."
  type        = string
}

variable "admin_email" {
  description = "Email for the default Connect admin user."
  type        = string
}

variable "agent_username" {
  description = "Login name for the default Connect agent user."
  type        = string
}

variable "agent_email" {
  description = "Email for the default Connect agent user."
  type        = string
}

variable "connect_user_password" {
  description = <<-EOT
    Password for the Connect admin and agent users. Must meet Connect's policy:
    8-64 chars with at least one uppercase, one lowercase, and one number.
    REQUIRED — set it in terraform.tfvars (gitignored) so no credential is committed.
  EOT
  type        = string
  sensitive   = true
  # No default on purpose: never commit a working password to the repo.

  validation {
    condition = (
      length(var.connect_user_password) >= 8 &&
      length(var.connect_user_password) <= 64 &&
      can(regex("[A-Z]", var.connect_user_password)) &&
      can(regex("[a-z]", var.connect_user_password)) &&
      can(regex("[0-9]", var.connect_user_password))
    )
    error_message = "Password must be 8-64 chars with an uppercase, a lowercase, and a number."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    Customer-managed KMS key (CMK) ARN used for all encryption at rest
    (DynamoDB, Lambda env vars, CloudWatch Logs). The key policy must allow:
      - logs.<region>.amazonaws.com  (for encrypted CloudWatch log groups)
      - dynamodb.amazonaws.com / the table's grants
      - the Terraform deploy principal: kms:CreateGrant, Encrypt, Decrypt,
        GenerateDataKey* (Lambda creates a grant for env-var encryption)
  EOT
  type        = string
}

# Sample/demo seed data lives in seeds.tf (kept with defaults so it stays
# committed). Everything above is config — set via terraform.tfvars.
