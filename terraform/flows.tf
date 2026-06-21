# --- Inbound contact flow ----------------------------------------------------
# Terraform creates a MINIMAL, valid flow (greeting -> disconnect). It does not
# reference the AI-agent bot, because Connect validates the bot ARN at create
# time and the bot doesn't exist until the CLI steps run.
#
# scripts/40-wire-flow.sh later replaces this flow's content with the full
# AI-agent flow (flows/inbound-ai-agent.json.tpl) once the real bot alias ARN
# exists. ignore_changes=[content] keeps Terraform from reverting that patch.
resource "aws_connect_contact_flow" "inbound" {
  instance_id = aws_connect_instance.this.id
  name        = "${var.project}-inbound-ai-agent"
  description = "Inbound Nova Sonic self-service agent (skeleton until wired by scripts/40)"
  type        = "CONTACT_FLOW"

  content = templatefile("${path.module}/../flows/inbound-skeleton.json.tpl", {
    company_name = var.company_name
  })

  lifecycle {
    ignore_changes = [content]
  }
}
