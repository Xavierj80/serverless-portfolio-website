## Serverless Portfolio & CI/CD Pipeline
https://xavieraws.com

## Why I built it this way
I built this website because I want to standout and prove to myself that I could build everything from scratch. I chose a serverless architecture (S3 + CloudFront + Lamdba) so I can upload the changes and update the website with commands instead of uploading the changes through S3.

## Tech Stack
-IaC: Terraform (S3 Remote State & DynamoDB Locking)
-CDN: CloudFront (Secured with Origin Access Counter)
-Backend: Python + DynamoDB (Visitor Counter)
-Automation: Github Actions (CI/CD)
