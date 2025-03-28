terraform {
  backend "s3" {
    bucket         = "zoochacha-permanent-store"
    key            = "terraform/state/zoochacha-basic-infra/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    profile        = "zoochacha"
    dynamodb_table = "terraform-lock"
  }
} 