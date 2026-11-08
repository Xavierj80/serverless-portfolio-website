variable "domain_name" {
  description = "Your domain name"
  type        = string
  default     = "xavieraws.com"
}

# Must be the certificate CloudFront is using right now.
# (The old default here had a typo: "bdbf" instead of "bd4f".)
variable "certificate_arn" {
  description = "ARN of your existing ACM certificate (must be in us-east-1 for CloudFront)"
  type        = string
  default     = "arn:aws:acm:us-east-1:897279496475:certificate/3b8e13b3-c7f3-429c-bd4f-16f11f41f326"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}