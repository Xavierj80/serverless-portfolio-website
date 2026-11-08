# ---------------------------------------------------------------------------
# Portfolio CI role (least privilege)
#
# Run this folder from YOUR computer with your admin login. GitHub Actions
# never runs it, and the CI role can't read or write this folder's state.
#
# What the CI role CAN do:
#   - read/write its own Terraform state (frontend/ key only)
#   - upload/delete website files in the xavieraws.com bucket
#   - update the one CloudFront distribution + clear its cache
#   - update/publish the one clean-URLs function
#   - READ everything else Terraform needs to plan
#
# What it CAN'T do (apply those changes locally instead):
#   - change DNS, the bucket policy, the public-access block, or the OAC
#   - create or delete anything
#   - touch IAM, any other bucket, table, zone, or account
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "xavieraws-terraform-state"
    key          = "bootstrap/portfolio-ci-role.tfstate" # CI has no access to this key
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "github_repo" {
  description = "owner/repo allowed to use this role"
  type        = string
  default     = "Xavierj80/serverless-portfolio-website"
}

variable "domain_name" {
  type    = string
  default = "xavieraws.com"
}

variable "distribution_id" {
  description = "CloudFront distribution ID (letter O, not zero)"
  type        = string
  default     = "E8S5U6OSNVNA9"
}

variable "state_bucket" {
  type    = string
  default = "xavieraws-terraform-state"
}

variable "state_key" {
  type    = string
  default = "frontend/terraform.tfstate"
}

# --- Lookups. Each one fails loudly if the thing doesn't exist (catches typos). ---

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_cloudfront_distribution" "site" {
  id = var.distribution_id
}

data "aws_cloudfront_function" "clean_urls" {
  name  = "xavieraws-clean-urls"
  stage = "LIVE"
}

data "aws_route53_zone" "site" {
  name         = var.domain_name
  private_zone = false
}

data "aws_acm_certificate" "site" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  site_bucket  = "arn:aws:s3:::${var.domain_name}"
  state_bucket = "arn:aws:s3:::${var.state_bucket}"
  zone_arn     = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.site.zone_id}"
}

# --- Who may assume the role: only GitHub Actions, only this repo, only main ---

resource "aws_iam_role" "portfolio_ci" {
  name                 = "xavieraws-portfolio-ci"
  description          = "GitHub Actions deploy role for xavieraws.com (least privilege)"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsMainBranchOnly"
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Project   = "portfolio"
    ManagedBy = "terraform-bootstrap"
  }
}

# --- What the role may do ---

resource "aws_iam_role_policy" "portfolio_ci" {
  name = "portfolio-ci-least-privilege"
  role = aws_iam_role.portfolio_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Terraform state: this project's key only
      {
        Sid      = "StateFile"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${local.state_bucket}/${var.state_key}"
      },
      {
        Sid      = "StateLockFile"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.state_bucket}/${var.state_key}.tflock"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.state_bucket
      },

      # Website bucket: read its settings, list, upload, delete files
      {
        Sid    = "SiteBucketRead"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucket*",
          "s3:GetAccelerateConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
        ]
        Resource = local.site_bucket
      },
      {
        Sid      = "SiteFiles"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.site_bucket}/*"
      },

      # The one CloudFront distribution
      {
        Sid    = "Distribution"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution",
          "cloudfront:ListTagsForResource",
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations",
        ]
        Resource = data.aws_cloudfront_distribution.site.arn
      },

      # The one CloudFront function
      {
        Sid    = "CleanUrlsFunction"
        Effect = "Allow"
        Action = [
          "cloudfront:DescribeFunction",
          "cloudfront:GetFunction",
          "cloudfront:UpdateFunction",
          "cloudfront:PublishFunction",
        ]
        Resource = "arn:aws:cloudfront::${local.account_id}:function/xavieraws-clean-urls"
      },

      # OAC: read-only. (Get only returns a name and signing settings.)
      {
        Sid      = "OriginAccessControlRead"
        Effect   = "Allow"
        Action   = "cloudfront:GetOriginAccessControl"
        Resource = "arn:aws:cloudfront::${local.account_id}:origin-access-control/*"
      },

      # DNS: read-only, xavieraws.com zone only
      {
        Sid    = "DnsReadThisZone"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = local.zone_arn
      },
      {
        Sid      = "DnsFindZoneByName" # these two can't be scoped to one zone
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"]
        Resource = "*"
      },

      # Certificate: read-only (CloudFront may check it on distribution updates)
      {
        Sid      = "CertificateRead"
        Effect   = "Allow"
        Action   = "acm:DescribeCertificate"
        Resource = data.aws_acm_certificate.site.arn
      },
      {
        Sid      = "CertificateList"
        Effect   = "Allow"
        Action   = "acm:ListCertificates"
        Resource = "*"
      },

      # Guard rail: even if someone attaches a broad policy later,
      # this role can never change IAM (including its own permissions).
      {
        Sid      = "NeverTouchIam"
        Effect   = "Deny"
        Action   = ["iam:*", "organizations:*", "sts:AssumeRole"]
        Resource = "*"
      },
    ]
  })
}

# --- Outputs: check these after apply ---

output "role_arn" {
  description = "Paste this into deploy.yml (role-to-assume)"
  value       = aws_iam_role.portfolio_ci.arn
}

output "certificate_arn_in_acm" {
  description = "Should end in ...bd4f-16f11f41f326 (same as terraform/variables.tf)"
  value       = data.aws_acm_certificate.site.arn
}

output "hosted_zone_id" {
  value = data.aws_route53_zone.site.zone_id
}
