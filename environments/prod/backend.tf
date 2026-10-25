terraform {
  required_version = ">= 1.11.0" # write-only arguments (DB password never hits state)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "s3" {
    bucket       = "REPLACE_ME_STATE_BUCKET"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = local.name
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

data "terraform_remote_state" "global" {
  backend = "s3"
  config = {
    bucket = "REPLACE_ME_STATE_BUCKET"
    key    = "global/terraform.tfstate"
    region = "us-east-1"
  }
}
