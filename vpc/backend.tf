terraform {
  backend "s3" {
    bucket         = "zoochacha-permanent-store"
    key            = "terraform/state/vpc/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
} 