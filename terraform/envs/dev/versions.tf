terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Remote state. Bootstrap the bucket + lock table once with
  # scripts/bootstrap-backend.sh, then `terraform init`.
  # Values are filled in via -backend-config flags or backend.hcl,
  # so the same module works for multiple environments.
  # `bucket` is a placeholder; override on init with:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    bucket       = "REPLACE_VIA_BACKEND_CONFIG"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "devops-challenge"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
