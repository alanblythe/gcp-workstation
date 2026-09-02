# Service Account for VM
resource "google_service_account" "vm_sa" {
  account_id   = "workstation-vm-sa"
  display_name = "Service Account for Workstation VM"
}

# IAM bindings for Logging and Monitoring
resource "google_project_iam_member" "vm_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "vm_sa_metric" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Secondary Persistent Disk
resource "google_compute_disk" "data_disk" {
  name = "workstation-mirror-data"
  type = "pd-ssd"
  zone = var.zone
  size = var.persistent_disk_size_gb
}

# Nightly Shutdown Schedule
resource "google_compute_resource_policy" "nightly_shutdown" {
  name   = "nightly-shutdown"
  region = var.region
  instance_schedule_policy {
    vm_stop_schedule {
      schedule = "0 22 * * *"
    }
    time_zone = var.shutdown_timezone
  }
}

# Boot image varies by os_flavor. Ubuntu keeps the existing startup
# script that bootstraps Xfce/Chrome/CRD; NixOS bakes all of that into the
# image and skips the startup script entirely.
locals {
  ubuntu_image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  boot_image   = var.os_flavor == "nixos" ? var.nixos_image : local.ubuntu_image
}

# GCE Instance
resource "google_compute_instance" "vm" {
  resource_policies = [google_compute_resource_policy.nightly_shutdown.id]
  name              = "workstation-vm"
  machine_type      = var.machine_type
  zone              = var.zone

  boot_disk {
    initialize_params {
      image = local.boot_image
      size  = var.boot_disk_size_gb
      type  = "pd-ssd"
    }
  }

  attached_disk {
    source = google_compute_disk.data_disk.id
  }

  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
    # No access_config block ensures no public IP
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = var.enable_shielded_vm
    enable_vtpm                 = var.enable_shielded_vm
    enable_integrity_monitoring = var.enable_shielded_vm
  }

  metadata = {
    enable-osconfig        = "TRUE"
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    startup-script         = var.os_flavor == "nixos" ? null : file("${path.module}/scripts/startup.sh")
  }

  allow_stopping_for_update = true
}

# OS Patch Deployment (Ubuntu only; on NixOS, "patching" means rebuilding the
# image from the flake and rolling the boot disk).
resource "google_os_config_patch_deployment" "daily_patch" {
  count = var.os_flavor == "ubuntu" ? 1 : 0

  patch_deployment_id = "daily-security-patch"

  instance_filter {
    zones     = [var.zone]
    instances = ["projects/${var.project_id}/zones/${var.zone}/instances/${google_compute_instance.vm.name}"]
  }

  patch_config {
    apt {
      type = "DIST"
    }
  }

  recurring_schedule {
    time_zone {
      id = "UTC"
    }

    time_of_day {
      hours   = 2
      minutes = 0
      seconds = 0
      nanos   = 0
    }

    weekly {
      day_of_week = "TUESDAY"
    }
  }
}
