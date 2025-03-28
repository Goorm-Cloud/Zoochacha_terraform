provider "aws" {
  region = "ap-northeast-2"
}

# Terraform state lock을 위한 DynamoDB 테이블
resource "aws_dynamodb_table" "terraform_lock" {
  name           = "terraform-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform Lock Table"
    Environment = "All"
    Purpose     = "Terraform State Lock"
    ManagedBy   = "DynamoDB Module"
  }

  # 실수로 테이블이 삭제되는 것을 방지
  lifecycle {
    prevent_destroy = true
  }
} 