# Optional NixOS sibling VM.
#
# Stand up a parallel VM booted from a freshly built NixOS image so we can
# validate Chrome Remote Desktop, gcloud, docker, and other tools before
# flipping the production VM (`google_compute_instance.vm`) over to NixOS.
#
# Enable with:  terraform apply \
#                 -var='create_nixos_sibling=true' \
#                 -var='nixos_image=projects/YOUR_PROJECT_ID/global/images/family/nixos-workstation'
#
# Disable (and tear it down) by setting create_nixos_sibling=false (the default).
#
# This sibling does NOT attach the persistent data disk; mount it manually
# during testing if you want to validate the bind-mount layout.

resource "google_compute_instance" "vm_nix_sibling" {
  count = var.create_nixos_sibling ? 1 : 0

  name         = "workstation-vm-nix"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.nixos_image
      size  = var.boot_disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
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
  }

  allow_stopping_for_update = true
}
