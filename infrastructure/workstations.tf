# Workstation Cluster
resource "google_workstations_workstation_cluster" "default" {
  provider               = google-beta
  workstation_cluster_id = var.cluster_id
  network                = google_compute_network.default.id
  subnetwork             = google_compute_subnetwork.default.id
  location               = var.region
}

# Workstation Config
resource "google_workstations_workstation_config" "default" {
  provider               = google-beta
  workstation_config_id  = var.config_id
  workstation_cluster_id = google_workstations_workstation_cluster.default.workstation_cluster_id
  location               = var.region
  idle_timeout           = "14400s"

  container {
    image = var.container_image
  }

  host {
    gce_instance {
      machine_type                = var.machine_type
      boot_disk_size_gb           = var.boot_disk_size_gb
      disable_public_ip_addresses = true

      shielded_instance_config {
        enable_secure_boot          = var.enable_shielded_vm
        enable_vtpm                 = var.enable_shielded_vm
        enable_integrity_monitoring = var.enable_shielded_vm
      }
    }
  }

  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb        = var.persistent_disk_size_gb
      fs_type        = "ext4"
      reclaim_policy = "DELETE"
    }
  }

  lifecycle {
    ignore_changes = [
      persistent_directories,
      container,
    ]
  }
}

# Workstation
resource "google_workstations_workstation" "default" {
  provider               = google-beta
  workstation_id         = var.workstation_id
  workstation_config_id  = google_workstations_workstation_config.default.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.default.workstation_cluster_id
  location               = var.region
}
