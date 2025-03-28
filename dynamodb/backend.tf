terraform {
  backend "s3" {
    bucket         = "zoochacha-permanent-store"
    key            = "terraform/state/dynamodb/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
  }
} 