# --- Customer-profile table (caller personalization) -------------------------
# Maps the caller's phone number (ANI) to their name (and any future
# personalization fields — tier, preferences, …). Used by the customer_lookup
# Lambda to greet a known caller by name at the start of a call. Decoupled from
# the orders table on purpose, so it can grow into a general profile store.
resource "aws_dynamodb_table" "customers" {
  name         = "${var.project}-customers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "phone"

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  attribute {
    name = "phone"
    type = "S"
  }
}

# --- Seed sample customers ---------------------------------------------------
resource "aws_dynamodb_table_item" "customers" {
  for_each = var.seed_customers

  table_name = aws_dynamodb_table.customers.name
  hash_key   = aws_dynamodb_table.customers.hash_key

  item = jsonencode({
    phone      = { S = each.key }
    first_name = { S = each.value.first_name }
    last_name  = { S = each.value.last_name }
  })

  # Don't fight out-of-band edits (future personalization fields, etc.).
  lifecycle {
    ignore_changes = [item]
  }
}
