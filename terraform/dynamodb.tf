# --- Orders table backing the order-lookup / refund tools --------------------
resource "aws_dynamodb_table" "orders" {
  name         = "${var.project}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  attribute {
    name = "order_id"
    type = "S"
  }

  # GSI to let the order-lookup tool find a caller's orders by phone number.
  global_secondary_index {
    name            = "by-phone"
    hash_key        = "customer_phone"
    projection_type = "ALL"
  }

  attribute {
    name = "customer_phone"
    type = "S"
  }
}

# --- Seed sample data --------------------------------------------------------
resource "aws_dynamodb_table_item" "orders" {
  for_each = var.seed_orders

  table_name = aws_dynamodb_table.orders.name
  hash_key   = aws_dynamodb_table.orders.hash_key

  item = jsonencode({
    order_id       = { S = each.key }
    customer_name  = { S = each.value.customer_name }
    customer_phone = { S = each.value.customer_phone }
    status         = { S = each.value.status }
    item           = { S = each.value.item }
    amount         = { N = tostring(each.value.amount) }
    refundable     = { BOOL = each.value.refundable }
  })

  # Don't fight the Lambda's status/refund updates after seeding.
  lifecycle {
    ignore_changes = [item]
  }
}
