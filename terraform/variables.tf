variable "region" {
  description = "AWS region. Must be a region where Amazon Connect + Nova Sonic agentic self-service is available."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "Amazon Connect + Nova Sonic agentic self-service is GA only in us-east-1 and us-west-2."
  }
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "connect-nova-sonic"
}

variable "agent_name" {
  description = "Display name for the self-service AI agent / bot."
  type        = string
  default     = "Amplifier"
}

variable "company_name" {
  description = "Company the agent represents (used in naming/tags)."
  type        = string
  default     = "Amplify Total Experience"
}

variable "connect_instance_alias" {
  description = "Unique alias for the Amazon Connect instance (becomes part of the access URL). Must be globally unique."
  type        = string
  default     = "connect-nova-sonic-demo"
}

variable "claim_phone_number" {
  description = "Whether to claim a DID phone number. Set false if no DIDs are available in the region or you want to claim manually."
  type        = bool
  default     = true
}

variable "phone_country_code" {
  description = "ISO country code for the claimed DID."
  type        = string
  default     = "US"
}

variable "lambda_runtime" {
  description = "Python runtime for the tool Lambdas."
  type        = string
  default     = "python3.12"
}

variable "admin_username" {
  description = "Login name for the default Connect admin user."
  type        = string
  default     = "demo.admin"
}

variable "admin_email" {
  description = "Email for the default Connect admin user."
  type        = string
  default     = "demo.admin@example.com"
}

variable "agent_username" {
  description = "Login name for the default Connect agent user."
  type        = string
  default     = "demo.agent"
}

variable "agent_email" {
  description = "Email for the default Connect agent user."
  type        = string
  default     = "demo.agent@example.com"
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
  default     = "arn:aws:kms:us-west-2:123456789012:key/71cf9f1f-81c0-4cc4-8534-6682359b842e"
}

variable "seed_orders" {
  description = "Sample orders to seed into the DynamoDB orders table. Mirrors the demo's order-lookup/refund flow."
  type = map(object({
    customer_name  = string
    customer_phone = string
    status         = string
    item           = string
    amount         = number
    refundable     = bool
  }))
  default = {
    "ORD-1001" = {
      customer_name  = "Jordan Lee"
      customer_phone = "+12065550101"
      status         = "shipped"
      item           = "Wireless Headphones"
      amount         = 129.99
      refundable     = true
    }
    "ORD-1002" = {
      customer_name  = "Jordan Lee"
      customer_phone = "+12065550101"
      status         = "processing"
      item           = "USB-C Charger"
      amount         = 24.50
      refundable     = true
    }
    "ORD-1003" = {
      customer_name  = "Sam Rivera"
      customer_phone = "+12065550102"
      status         = "delivered"
      item           = "Mechanical Keyboard"
      amount         = 89.00
      refundable     = false
    }
    "ORD-2001" = {
      customer_name  = "Sateesh"
      customer_phone = "+12146817675"
      status         = "shipped"
      item           = "Smart Watch"
      amount         = 199.99
      refundable     = true
    }
    "ORD-2002" = {
      customer_name  = "Sateesh"
      customer_phone = "+12146817675"
      status         = "out for delivery"
      item           = "Laptop Stand"
      amount         = 45.00
      refundable     = false
    }
    "ORD-2003" = {
      customer_name  = "Sateesh"
      customer_phone = "+12146817675"
      status         = "delivered"
      item           = "Bluetooth Speaker"
      amount         = 79.99
      refundable     = true
    }
    "ORD-2004" = {
      customer_name  = "Sateesh"
      customer_phone = "+12146817675"
      status         = "shipped"
      item           = "Wireless Mouse"
      amount         = 29.99
      refundable     = true
    }
  }
}
