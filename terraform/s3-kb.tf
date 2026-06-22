# --- Knowledge-base source bucket (policy Q&A enhancement) -------------------
# Holds the return/refund policy document that Amazon Q in Connect ingests into
# a knowledge base. The Amplifier agent's built-in `Retrieve` tool then answers
# free-form policy questions ("what's your return window?", "are opened items
# refundable?"). See docs/RUNBOOK.md "Knowledge base (policy Q&A)" for the
# console wiring (create KB from this bucket, re-add Retrieve, grant access).
#
# NOTE on encryption: this bucket uses SSE-S3 (AES256), NOT the project CMK, on
# purpose. The document is a non-sensitive, public-facing policy, and SSE-S3
# avoids having to grant the Q-in-Connect ingestion role kms:Decrypt on the CMK
# (a common cause of failed S3 knowledge-base syncs). Switch to the CMK only if
# you also extend the key policy to the Wisdom/Q-in-Connect service.

resource "aws_s3_bucket" "kb" {
  # Bucket names are globally unique; suffix with the account id to keep it so.
  bucket = "${var.connect_instance_alias}-kb-${data.aws_caller_identity.current.account_id}"

  # POC convenience: let `terraform destroy` / destroy.sh empty + remove the
  # bucket (including all object versions) without a manual empty step.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "kb" {
  bucket = aws_s3_bucket.kb.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb" {
  bucket = aws_s3_bucket.kb.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "kb" {
  bucket = aws_s3_bucket.kb.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Amazon Q in Connect ingests S3 content through AWS AppIntegrations, so the
# bucket must let the app-integrations service principal read it. Without this,
# the knowledge-base sync fails with AccessDenied. (Docs: adminguide
# setup-knowledgebase / enable-q "Create an Amazon S3 integration".) This policy
# names a specific service principal (not public), so the public-access-block's
# block_public_policy does not reject it.
resource "aws_s3_bucket_policy" "kb" {
  bucket     = aws_s3_bucket.kb.id
  depends_on = [aws_s3_bucket_public_access_block.kb]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowQinConnectAppIntegrationsRead"
      Effect    = "Allow"
      Principal = { Service = "app-integrations.amazonaws.com" }
      Action    = ["s3:GetObject", "s3:GetBucketLocation", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.kb.arn,
        "${aws_s3_bucket.kb.arn}/*",
      ]
      # Confused-deputy guard: only this account's Connect can use the principal.
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# The policy document Q in Connect ingests. etag tracks edits so re-uploading a
# changed PDF triggers a new object version (then re-sync the KB in the console).
resource "aws_s3_object" "policy_doc" {
  bucket       = aws_s3_bucket.kb.id
  key          = "policies/return-refund-policy.pdf"
  source       = "${path.module}/../docs/return-refund-policy.pdf"
  etag         = filemd5("${path.module}/../docs/return-refund-policy.pdf")
  content_type = "application/pdf"
}
