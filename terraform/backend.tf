# backend.tf

terraform {
  backend "gcs" {
    bucket  = "ncorium-bucket"
    prefix  = "terraform/state"
  }
}