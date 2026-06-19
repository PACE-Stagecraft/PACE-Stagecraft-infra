terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "agora-terraform-state-353284253443"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "agora-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "agora"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}
