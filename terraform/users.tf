# Default admin + agent users for the Connect instance.
#
# Security-profile note: the AI agent itself is NOT a Connect user and needs no
# security profile. These are HUMAN users:
#   - admin -> built-in "Admin" profile (can build/manage AI agents).
#   - agent -> built-in "Agent" profile (handles escalated calls). For
#     Q-in-Connect agent-assist in the workspace, add the "Amazon Q" permission
#     to the Agent profile in the console.
# We reference the instance's built-in security profiles rather than authoring
# permission strings, so this always matches what the instance ships with.

data "aws_connect_security_profile" "admin" {
  instance_id = aws_connect_instance.this.id
  name        = "Admin"
}

data "aws_connect_security_profile" "agent" {
  instance_id = aws_connect_instance.this.id
  name        = "Agent"
}

# Routing profile so the agent can receive voice contacts from the escalation queue.
resource "aws_connect_routing_profile" "default" {
  instance_id               = aws_connect_instance.this.id
  name                      = "${var.project}-routing"
  description               = "Default voice routing profile for the demo"
  default_outbound_queue_id = aws_connect_queue.escalation.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.escalation.queue_id
  }
}

# Connect-managed users use a fixed default password (var.connect_user_password).
# No first-login reset is forced for API/Terraform-created users.
resource "aws_connect_user" "admin" {
  instance_id          = aws_connect_instance.this.id
  name                 = var.admin_username
  password             = var.connect_user_password
  routing_profile_id   = aws_connect_routing_profile.default.routing_profile_id
  security_profile_ids = [data.aws_connect_security_profile.admin.security_profile_id]

  identity_info {
    first_name = "Demo"
    last_name  = "Admin"
    email      = var.admin_email
  }

  phone_config {
    phone_type                    = "SOFT_PHONE"
    auto_accept                   = false
    after_contact_work_time_limit = 0
  }
}

resource "aws_connect_user" "agent" {
  instance_id          = aws_connect_instance.this.id
  name                 = var.agent_username
  password             = var.connect_user_password
  routing_profile_id   = aws_connect_routing_profile.default.routing_profile_id
  security_profile_ids = [data.aws_connect_security_profile.agent.security_profile_id]

  identity_info {
    first_name = "Demo"
    last_name  = "Agent"
    email      = var.agent_email
  }

  phone_config {
    phone_type                    = "SOFT_PHONE"
    auto_accept                   = false
    after_contact_work_time_limit = 0
  }
}
