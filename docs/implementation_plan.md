# Implementation Plan: GCE Mirror VM with Patch Management

## Goal
Provision a Google Compute Engine (GCE) VM that mirrors the specifications of the Cloud Workstation, running Ubuntu 24.04, with a secondary persistent disk and automated patch management.

## Proposed Architecture

### 1. GCE Instance (`vm.tf`)
*   **OS**: Ubuntu 24.04 LTS (`ubuntu-os-cloud/ubuntu-2404-lts-amd64`).
*   **Machine Type**: Re-use `var.machine_type` (default: `n2-standard-8`) to match the workstation.
*   **Network**: Connect to the existing `workstation-network` and `workstation-subnet`.
*   **Security**:
    *   No public IP (Private only).
    *   Shielded VM enabled (Secure Boot, vTPM, Integrity Monitoring).
    *   Service Account: Dedicated user-managed service account.

### 2. Persistent Disk Strategy
The user requested a "copy" of the workstation's persistent disk.
*   **Challenge**: Cloud Workstations manages the lifecycle and naming of its underlying Persistent Volume Claims (PVCs) / Compute Disks dynamically. Terraform does not output the specific Disk ID of the workstation's home directory, making a direct "snapshot and restore" within the same Terraform lifecycle impossible without external data lookups.
*   **Implementation**: We will create a **new independent Persistent Disk** that matches the *specifications* (Size: `var.persistent_disk_size_gb`, Type: **`pd-ssd`** to match workstation) of the workstation disk.
    *   *Note*: If a literal data clone is strictly required, it would need to be performed as a "Day 2" operation (Snapshot Workstation Disk -> Create Disk from Snapshot -> Attach to VM).

### 3. Patch Management (OS Config)
To ensure the VM stays patched, we will utilize **Google Cloud VM Manager (OS Config)**.
*   **Enable API**: `osconfig.googleapis.com`.
*   **Instance Configuration**: Set metadata `enable-osconfig = "TRUE"`.
*   **Patch Deployment**: Create a `google_os_config_patch_deployment` resource.
    *   **Schedule**: **Daily** (e.g., 2 AM).
    *   **Action**: Update and Reboot if necessary.

### 4. Desktop Environment & Remote Access
To facilitate Chrome Remote Desktop usage:
*   **Desktop Environment**: Install **Xfce4** (Lightweight, robust, recommended for remote access).
*   **Remote Access**: Install **Chrome Remote Desktop** headless package.
*   **Browser**: Install **Google Chrome**.
*   **Configuration**: Configure Chrome Remote Desktop to use Xfce4 by default.
*   **Note**: The final registration (linking the VM to the user's Google Account) requires a manual step to generate and run the authentication command, as tokens are short-lived.

### 5. Power Management
To save costs, the VM will automatically shut down at night.
*   **Schedule**: Daily at **10:00 PM EST** (America/New_York).
*   **Implementation**: Google Compute Resource Policy (Instance Schedule).
*   **Cost Impact**:
    *   **Compute (vCPU/RAM)**: **$0.00** while stopped.
    *   **Storage (Disks)**: Charges **continue** while stopped (~$42.50/month total).
    *   *Result*: Significant savings (approx. 50-60% reduction if used 10-12 hours/day).

## Resources to Add/Modify

### `infrastructure/apis.tf` (New)
*   Enable `osconfig.googleapis.com` (VM Manager).
*   Enable `compute.googleapis.com` (Compute Engine) - likely implicitly enabled but good to be explicit.

### `infrastructure/scripts/startup.sh` (New)
*   Shell script to:
    *   Update repositories.
    *   Install Xfce4 and Xfce4-goodies.
    *   Download and install Chrome Remote Desktop.
    *   Download and install Google Chrome Stable.
    *   Set the Chrome Remote Desktop session to use Xfce.
    *   Disable the display manager (LightDM) service to prevent conflicts (optional but often cleaner for pure CRD usage, though keeping it allows VNC/local console access).

### `infrastructure/vm.tf` (New)
*   `google_service_account`: `vm-sa` for the GCE instance.
*   `google_project_iam_member`: Grant `roles/logging.logWriter` and `roles/monitoring.metricWriter` to the SA.
*   `google_compute_resource_policy`: **Nightly shutdown schedule**.
*   `google_compute_disk`: The secondary data disk (`workstation-mirror-disk`) using **`pd-ssd`**.
*   `google_compute_instance`:
    *   Boot disk: Ubuntu 24.04 (`pd-ssd`).
    *   Attached disk: The secondary disk created above.
    *   **Resource Policies**: Attach the shutdown schedule.
    *   Metadata: `enable-osconfig = "TRUE"`.
    *   **Metadata Startup Script**: Embed content of `infrastructure/scripts/startup.sh`.
*   `google_os_config_patch_deployment`: Configuration for automatic patching.

### `infrastructure/variables.tf`
*   Reuse existing `machine_type`, `region`, `zone`, `network_name`, `persistent_disk_size_gb`.
*   Add `ubuntu_image_family` (optional, can hardcode `ubuntu-2404-lts-amd64` or `ubuntu-2404-noble-amd64-v...` logic).

## Cost Estimate (Monthly)

Estimates based on `us-central1` pricing (approximate):

*   **Compute Engine (`n2-standard-8`)**:
    *   8 vCPUs, 32 GB RAM
    *   Approx. $0.39/hour * 730 hours = **~$285.00**
*   **Boot Disk (50GB pd-ssd)**:
    *   $0.17/GB * 50 = **$8.50**
*   **Persistent Data Disk (200GB pd-ssd)**:
    *   $0.17/GB * 200 = **$34.00**
*   **VM Manager (OS Config)**:
    *   Free tier applies for the first 100 VMs in the billing account.
    *   **$0.00** (assuming <100 VMs).

**Total Estimated Monthly Cost: ~$327.50**

## Storage Analysis (Boot Disk)
*   **Total Size:** 50 GB (`pd-ssd`)
*   **OS Install (Ubuntu 24.04):** ~4 GB
*   **Desktop Environment (Xfce4) & Tools:** ~2 GB
*   **Estimated Used Space:** ~6 GB
*   **Estimated Free Space:** **~44 GB** (available for applications and logs)
*   *Note: The 200 GB secondary disk is dedicated entirely to data.*

## Execution Steps
1.  Create `infrastructure/apis.tf`.
2.  Create `infrastructure/vm.tf`.
3.  Run `terraform init` (for new providers if any).
4.  Run `terraform plan` to verify.
5.  Run `terraform apply`.