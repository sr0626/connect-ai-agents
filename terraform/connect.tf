data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# --- Amazon Connect instance -------------------------------------------------
resource "aws_connect_instance" "this" {
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = true
  instance_alias           = var.connect_instance_alias

  # Contact flow logging ON (requested). Contact Lens OFF: it relies on call
  # recording, which we are intentionally NOT enabling. No Kinesis Data Streams
  # or Data Firehose (ADF) streaming is configured anywhere (no
  # aws_connect_instance_storage_config for AGENT_EVENTS / CONTACT_TRACE_RECORDS),
  # and no call-recording storage config exists, so recording stays disabled.
  contact_flow_logs_enabled = true
  contact_lens_enabled      = false
}

# --- Hours of operation (24/7) ----------------------------------------------
resource "aws_connect_hours_of_operation" "always_open" {
  instance_id = aws_connect_instance.this.id
  name        = "${var.project}-always-open"
  description = "24/7 hours for the Nova Sonic self-service demo"
  time_zone   = "UTC"

  dynamic "config" {
    for_each = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
    content {
      day = config.value
      start_time {
        hours   = 0
        minutes = 0
      }
      end_time {
        hours   = 23
        minutes = 59
      }
    }
  }
}

# --- Escalation queue (transfer-to-human target) -----------------------------
resource "aws_connect_queue" "escalation" {
  instance_id           = aws_connect_instance.this.id
  name                  = "${var.project}-escalation"
  description           = "Live-agent escalation queue for the AI self-service agent"
  hours_of_operation_id = aws_connect_hours_of_operation.always_open.hours_of_operation_id
}

# --- Claimed DID phone number (DISABLED) -------------------------------------
# Phone-number claiming is intentionally commented out. Claim/assign a number
# manually in the Connect console and associate it with the inbound flow (or
# uncomment this block, and the phone_number outputs in outputs.tf, to claim one
# via Terraform). scripts/40-wire-flow.sh already handles an empty number id.
#
# resource "aws_connect_phone_number" "did" {
#   count = var.claim_phone_number ? 1 : 0
#
#   target_arn   = aws_connect_instance.this.arn
#   country_code = var.phone_country_code
#   type         = "DID"
#   description  = "Inbound number for the Nova Sonic self-service demo"
# }
