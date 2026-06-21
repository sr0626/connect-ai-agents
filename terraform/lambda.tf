locals {
  # The two tools the AI agent calls, mirroring the demo (order lookup + refund).
  lambdas = {
    order_lookup   = "order_lookup"
    process_refund = "process_refund"
  }
}

data "archive_file" "tool" {
  for_each = local.lambdas

  type        = "zip"
  source_dir  = "${path.module}/../lambdas/${each.value}"
  output_path = "${path.module}/.build/${each.value}.zip"
}

resource "aws_cloudwatch_log_group" "tool" {
  for_each = local.lambdas

  name              = "/aws/lambda/${var.project}-${each.value}"
  retention_in_days = 14
  kms_key_id        = var.kms_key_arn
}

resource "aws_lambda_function" "tool" {
  for_each = local.lambdas

  function_name    = "${var.project}-${each.value}"
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.tool[each.key].output_path
  source_code_hash = data.archive_file.tool[each.key].output_base64sha256
  timeout          = 15

  # Encrypt environment variables at rest with the CMK.
  kms_key_arn = var.kms_key_arn

  environment {
    variables = {
      ORDERS_TABLE   = aws_dynamodb_table.orders.name
      PHONE_GSI_NAME = "by-phone"
    }
  }

  depends_on = [aws_cloudwatch_log_group.tool]
}

# Make the Lambdas selectable inside Amazon Connect flows / AI agent tools.
resource "aws_connect_lambda_function_association" "tool" {
  for_each = local.lambdas

  instance_id  = aws_connect_instance.this.id
  function_arn = aws_lambda_function.tool[each.key].arn
}
