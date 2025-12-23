terraform {
  required_version = ">= 1.0"

  # 1. ADDED: Remote Backend for GitHub Actions State Sync
  backend "s3" {
    bucket         = "xavieraws-terraform-state" # Ensure this bucket exists!
    key            = "frontend/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"            # Manually created or via CLI
    encrypt        = true
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

# 2. S3 bucket for website (Renamed to match your domain)
resource "aws_s3_bucket" "website" {
  bucket = var.domain_name # This uses xavieraws.com
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Modern CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "s3-portfolio-oac"
  description                       = "OAC for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 4. S3 Bucket Policy for Private Access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipalReadOnly"
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.website.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
        }
      }
    }]
  })
}

# 5. Reference your existing Route 53 Zone
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# 6. CloudFront distribution
resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${var.domain_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.domain_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:897279496475:certificate/3b8e13b3-c7f3-429c-bd4f-16f11f41f326"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}

# 7. Route 53 Record
resource "aws_route53_record" "website_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}
# --- EXISTING CODE ABOVE ---
# (Terraform block, S3 Bucket, CloudFront, Route 53)

# --- ADD THE BACKEND CODE BELOW ---

# 1. DynamoDB Table for Visitor Counter
resource "aws_dynamodb_table" "stats" {
  name           = "xavieraws-stats"
  billing_mode   = "PAY_PER_REQUEST" 
  hash_key       = "stat_name"

  attribute {
    name = "stat_name"
    type = "S"
  }
}

# 2. IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "portfolio_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 3. Policy to allow Lambda to talk to DynamoDB
resource "aws_iam_role_policy" "dynamo_lambda_policy" {
  name = "lambda_dynamo_permissions"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.stats.arn
    }]
  })
}