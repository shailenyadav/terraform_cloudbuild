# Variables
variable "project_id" {
  type        = string
  description = "The ID of the Google Cloud project"
  default     = "nc-ev-test" 
}
variable "region" {
  type        = string
  description = "The region for the resources"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "The zone for the resources"
  default     = "us-central1-a"
}

variable "subnet_cidr" {
  type        = string
  description = "The CIDR block for the VPC subnet"
  default     = "10.0.0.0/24"
}