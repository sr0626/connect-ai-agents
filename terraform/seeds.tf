# Sample/demo seed data. Kept here (with defaults) rather than in tfvars so the
# demo's sample data stays committed and the app is self-contained. All other
# config variables live in variables.tf (declarations only) and are set in
# terraform.tfvars. Consumed by dynamodb.tf (orders) and customers.tf (customers).

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

variable "seed_customers" {
  description = <<-EOT
    Caller personalization profiles keyed by phone number (E.164 / ANI). Used by
    the customer_lookup Lambda to greet known callers by name. The DynamoDB table
    is schemaless, so extra personalization fields (tier, preferences, …) can be
    added later without changing this type.
  EOT
  type = map(object({
    first_name = string
    last_name  = string
  }))
  default = {
    "+12146817675" = { first_name = "Sateesh", last_name = "Rudrangi" } # placeholder last name — edit to taste
    "+12065550101" = { first_name = "Jordan", last_name = "Lee" }
    "+12065550102" = { first_name = "Sam", last_name = "Rivera" }
  }
}
