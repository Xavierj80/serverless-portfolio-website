variable "domain_name" {
  description = "Your domain name"
  type        = string
  default     = "xavieraws.com"
}

variable "certificate_arn" {
  description = "ARN of your existing ACM certificate"
  type        = string
  default     = "arn:aws:acm:us-east-1:897279496475:certificate/3b8e13b3-c7f3-429c-bdbf-16f11f41f326"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}