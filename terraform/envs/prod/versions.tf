terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
  }

  # Remote state in a GCS bucket so state is shared + locked.
  # Create the bucket once (see README), then run: terraform init
  backend "gcs" {
    bucket = "REPLACE_ME-tfstate"
    prefix = "gke/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
