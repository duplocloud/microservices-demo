# Terraform for provisioning the Amazon ECR repository used by the
# build-and-deploy.yml workflow to store the `demo` container image.
#
# Usage:
#   cd deploy/infra/ecr
#   terraform init
#   terraform apply \
#     -var="aws_region=<AWS_REGION>" \
#     -var="account_id=<AWS_ACCOUNT_ID>"

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Recommended: configure a remote backend (S3 + DynamoDB lock table) for
  # team use. Left as local backend here since no backend details were
  # provided.
  # backend "s3" {
  #   bucket         = "<TERRAFORM_STATE_BUCKET>"
  #   key            = "microservices-demo/ecr/terraform.tfstate"
  #   region         = "<AWS_REGION>"
  #   dynamodb_table = "<TERRAFORM_LOCK_TABLE>"
  # }
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the ECR repository into"
}

variable "account_id" {
  type        = string
  description = "AWS account ID that owns the ECR repository"
}

variable "repository_name" {
  type        = string
  description = "Name of the ECR repository"
  default     = "demo"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "demo" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    app       = "demo"
    managed-by = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "demo" {
  repository = aws_ecr_repository.demo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "repository_url" {
  value = aws_ecr_repository.demo.repository_url
}
