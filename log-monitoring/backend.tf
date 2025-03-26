terraform {
  backend "s3" {
    bucket         = "zoochacha-permanent-store"
    key            = "terraform/state/log-monitoring/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    profile        = "zoochacha"
    dynamodb_table = "terraform-lock"
  }
} 