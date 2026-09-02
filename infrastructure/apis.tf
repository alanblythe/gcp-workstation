resource "google_project_service" "osconfig" {
  project = var.project_id
  service = "osconfig.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}
