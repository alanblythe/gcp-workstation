variable "project_id" {
  description = "The ID of the Google Cloud project"
  type        = string
}

variable "region" {
  description = "The region to deploy resources to"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The zone to deploy resources to"
  type        = string
  default     = "us-central1-a"
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "workstation-network"
}

variable "subnetwork_name" {
  description = "The name of the subnetwork"
  type        = string
  default     = "workstation-subnet"
}

variable "subnetwork_cidr" {
  description = "The CIDR range for the subnetwork"
  type        = string
  default     = "10.0.0.0/24"
}

variable "cluster_id" {
  description = "The ID of the workstation cluster"
  type        = string
  default     = "my-workstation-cluster"
}

variable "config_id" {
  description = "The ID of the workstation config"
  type        = string
  default     = "n2-standard-8-config"
}

variable "machine_type" {
  description = "The machine type for the workstation"
  type        = string
  default     = "n2-standard-8"
}

variable "boot_disk_size_gb" {
  description = "The boot disk size in GB for the workstation"
  type        = number
  default     = 50
}

variable "workstation_id" {
  description = "The ID of the workstation"
  type        = string
  default     = "my-workstation"
}

variable "enable_shielded_vm" {

  description = "Enable Shielded VM features (Secure Boot, vTPM, Integrity Monitoring)"

  type = bool

  default = true

}



variable "container_image" {
  description = "The container image to use for the workstation"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/base:latest"
}

variable "persistent_disk_size_gb" {
  description = "The size of the persistent home directory in GB"
  type        = number
  default     = 200
}

variable "shutdown_timezone" {
  description = "Time zone for the nightly shutdown schedule (e.g., America/New_York, UTC)"
  type        = string
  default     = "America/New_York"
}

# --- OS flavor switch -------------------------------------------------------
# Lets us deploy the workstation either on the current Ubuntu+startup-script
# stack or on a custom NixOS image built from infrastructure/nixos/. Default
# preserves current behavior; setting os_flavor="nixos" requires nixos_image.

variable "os_flavor" {
  description = "Boot image flavor: 'ubuntu' (default, with startup.sh + post-create.sh) or 'nixos' (custom image built from infrastructure/nixos)."
  type        = string
  default     = "ubuntu"
  validation {
    condition     = contains(["ubuntu", "nixos"], var.os_flavor)
    error_message = "os_flavor must be 'ubuntu' or 'nixos'."
  }
}

variable "nixos_image" {
  description = "Self-link or short reference of the NixOS image to boot when os_flavor='nixos'. e.g. 'projects/YOUR_PROJECT_ID/global/images/family/nixos-workstation'. Required when os_flavor='nixos'."
  type        = string
  default     = null
  validation {
    condition     = !(var.nixos_image == null && var.os_flavor == "nixos")
    error_message = "nixos_image must be set when os_flavor='nixos'."
  }
}

variable "create_nixos_sibling" {
  description = "If true, also create a parallel test VM 'workstation-vm-nix' booted from nixos_image. Lets you validate Chrome Remote Desktop and tooling on NixOS before flipping the production VM."
  type        = bool
  default     = false
}




