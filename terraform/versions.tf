terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Local backend by default. To use a remote backend, uncomment and adjust:
  # backend "s3" {
  #   bucket         = "my-tf-state-bucket"
  #   key            = "connect-ai-agents/terraform.tfstate"
  #   region         = "us-west-2"
  #   dynamodb_table = "my-tf-lock-table"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
