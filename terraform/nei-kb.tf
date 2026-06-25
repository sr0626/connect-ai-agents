# ============================================================================
# TEMPORARY / DEMO — isolated NEI knowledge-base source.  NOT part of the core POC.
# Kept in its own file (separate from s3-kb.tf) so it can be torn down cleanly
# without touching the main demo:
#     delete this file, then `terraform -chdir=terraform apply`
#   or: terraform -chdir=terraform destroy \
#         -target=aws_s3_object.nei_doc -target=aws_s3_bucket_policy.nei_kb \
#         -target=aws_s3_bucket_server_side_encryption_configuration.nei_kb \
#         -target=aws_s3_bucket_public_access_block.nei_kb -target=aws_s3_bucket.nei_kb
# Then also remove (console): the NEI KB integration + the second Retrieve tool.
# Do not commit — this is a throwaway test of "website content as an isolated KB".
# ============================================================================

resource "aws_s3_bucket" "nei_kb" {
  bucket        = "${var.connect_instance_alias}-nei-kb-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "nei_kb" {
  bucket = aws_s3_bucket.nei_kb.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "nei_kb" {
  bucket = aws_s3_bucket.nei_kb.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Q in Connect ingests S3 via AppIntegrations — same read grant as s3-kb.tf.
resource "aws_s3_bucket_policy" "nei_kb" {
  bucket     = aws_s3_bucket.nei_kb.id
  depends_on = [aws_s3_bucket_public_access_block.nei_kb]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowQinConnectAppIntegrationsRead"
      Effect    = "Allow"
      Principal = { Service = "app-integrations.amazonaws.com" }
      Action    = ["s3:GetObject", "s3:GetBucketLocation", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.nei_kb.arn,
        "${aws_s3_bucket.nei_kb.arn}/*",
      ]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# The crawled neirelo.com snapshot (~460 KB plain text, under the 1 MB KB limit).
resource "aws_s3_object" "nei_doc" {
  bucket       = aws_s3_bucket.nei_kb.id
  key          = "nei-services.txt"
  source       = "${path.module}/../docs/nei-services.txt"
  etag         = filemd5("${path.module}/../docs/nei-services.txt")
  content_type = "text/plain"
}

output "nei_kb_bucket_name" {
  description = "Isolated S3 bucket holding the NEI website snapshot (temporary)."
  value       = aws_s3_bucket.nei_kb.bucket
}

output "nei_kb_s3_uri" {
  description = "Give this bucket URI to the new (NEI) Q-in-Connect S3 integration."
  value       = "s3://${aws_s3_bucket.nei_kb.bucket}"
}
