# Migrating `workstation-vm` to NixOS

The VM today is provisioned by Terraform from `ubuntu-os-cloud/ubuntu-2404-lts-amd64` plus an imperative chain of shell scripts (`scripts/startup.sh`, `scripts/post-create.sh`). This document covers the path to making it fully rebuildable from a Nix flake while keeping the option to fall back to the Ubuntu build.

## Architecture after migration

| Layer | Today | After |
| --- | --- | --- |
| Boot disk image | `ubuntu-os-cloud/ubuntu-2404-lts-amd64` | Custom NixOS image in `YOUR_PROJECT_ID`, built from `infrastructure/nixos/` |
| OS bootstrap | `scripts/startup.sh` (Xfce, Chrome, CRD) | Baked into the image via `configuration.nix` |
| Tooling | `scripts/post-create.sh` (gcloud, opentofu, pack, jupyter, antigravity-cli) | `environment.systemPackages` in `configuration.nix` |
| Patching | `google_os_config_patch_deployment` (weekly `apt dist-upgrade`) | Image rebuild from flake; `nix.gc` set to weekly |
| `/home/<user>` | On boot disk (lost on reimage) | Bind-mounted from `/mnt/data/home/<user>` (survives boot-disk swap) |
| `/var/lib/docker` | Already on `/mnt/data/docker` | Unchanged |
| Persistent disk `workstation-mirror-data` | 200 GB pd-ssd at `/mnt/data` | Unchanged |
| Nightly shutdown / Shielded VM / no public IP | Unchanged | Unchanged |

## TL;DR sequence

```bash
# 0. Snapshot the persistent disk (once, manually).
gcloud compute disks snapshot workstation-mirror-data \
  --snapshot-names=workstation-mirror-data-pre-nix-$(date +%Y%m%d) \
  --zone=us-central1-a \
  --project=YOUR_PROJECT_ID

# 1. Push the updated startup script (which now bind-mounts /home from the
#    data disk), then reboot. The migration runs automatically at boot.
cd infrastructure
terraform apply        # pushes new metadata.startup-script to the VM
gcloud compute ssh workstation-vm \
  --zone=us-central1-a --tunnel-through-iap \
  --command='sudo reboot'

# 2. Build & publish the NixOS image.
cd nixos
make publish

# 3. Validate on a sibling VM before touching production.
cd ..
terraform apply \
  -var='create_nixos_sibling=true' \
  -var='nixos_image=projects/YOUR_PROJECT_ID/global/images/family/nixos-workstation'
# Connect to workstation-vm-nix, set up CRD, verify gcloud + docker + tools.

# 4. When confident, flip the production VM. This DESTROYS AND RECREATES
#    the boot disk; the persistent disk and bind-mounted /home survive.
terraform apply \
  -var='os_flavor=nixos' \
  -var='nixos_image=projects/YOUR_PROJECT_ID/global/images/family/nixos-workstation' \
  -var='create_nixos_sibling=false'
```

## Pre-flight (do once, regardless of OS choice)

### Snapshot the persistent disk

```bash
gcloud compute disks snapshot workstation-mirror-data \
  --snapshot-names=workstation-mirror-data-pre-nix-$(date +%Y%m%d) \
  --zone=us-central1-a \
  --project=YOUR_PROJECT_ID
```

### Move `/home/<user>` to the persistent disk

The boot disk today holds `/home/<user>` (~36 GB). For "rebuildable" to mean anything, the home directory must survive a boot-disk swap.

**Recommended path: do it via the GCE startup script.** `infrastructure/scripts/startup.sh` now inlines the migration logic ahead of the desktop install, gated by an idempotency check (no-op once the bind mount is in fstab). After `terraform apply` pushes the updated metadata to the VM, the next reboot performs the migration automatically:

```bash
cd infrastructure
terraform apply
gcloud compute ssh workstation-vm \
  --zone=us-central1-a --tunnel-through-iap \
  --command='sudo reboot'
```

After the reboot, **reconnect via Chrome Remote Desktop** (the previous session was terminated by the reboot — that's expected). Then verify from a terminal:

```bash
mount | grep "/home/$USER"
# expect: /mnt/data/home/<user> on /home/<user> type none (rw,bind,...)

systemctl is-active chrome-remote-desktop@$USER.service
# expect: active

ls /home/$USER.OLD-*  # the old contents on the boot disk, parked for cleanup
df -h /               # boot disk should drop once .OLD-* is removed
```

If the bind is in place and CRD reconnected cleanly, reclaim the boot-disk space:

```bash
sudo rm -rf /home/$USER.OLD-*
```

### Why this is safe for CRD

`google-startup-scripts.service` is `After=multi-user.target`, so by the time `startup.sh` runs at boot, `chrome-remote-desktop@<user>.service` has already started and is holding `~/.config/chrome-remote-desktop/host#*.json` open. To avoid swapping `/home/<user>` out from under a running daemon, the migration block in `startup.sh`:

1. Stops `chrome-remote-desktop@<user>.service` (and any sibling instances).
2. Performs the rsync / mv / mkdir / mount-bind / fstab edit.
3. Restarts the service so it reopens its config through the new bind-mount path.

This works because the user's xfce session is *not* active at this point — the user-side CRD client was disconnected by the reboot they just initiated, and they reconnect manually after the migration completes. The CRD daemon's brief downtime (sub-second) is invisible from the browser side.

If you skip the reboot and try to push these changes onto a system with an active xfce session attached to CRD, the migration will kick that session and the user has to reconnect.

**Alternative: run the standalone script manually.** Useful if you want to do a test run before relying on the startup-script flow, or to migrate an out-of-band machine. From a fresh SSH session (so the desktop session isn't holding `/home` files open):

```bash
sudo /mnt/data/repos/gcp-workstation/scripts/migrate-home-to-data-disk.sh
# or, no prompt:
sudo /mnt/data/repos/gcp-workstation/scripts/migrate-home-to-data-disk.sh --unattended
```

Both paths produce the same end state. Both are idempotent — if the bind mount is already active, the run is a no-op.

## OS flavor switch

`infrastructure/variables.tf` exposes:

| Variable | Type | Default | Effect |
| --- | --- | --- | --- |
| `os_flavor` | `"ubuntu" \| "nixos"` | `"ubuntu"` | Selects boot image and whether `startup.sh` runs |
| `nixos_image` | `string` | `null` | NixOS image self-link. Required when `os_flavor="nixos"` |
| `create_nixos_sibling` | `bool` | `false` | Stand up `workstation-vm-nix` alongside production for testing |

Default behavior is unchanged: `terraform apply` with no overrides keeps the Ubuntu build exactly as it was.

## Building the NixOS image

```bash
cd infrastructure/nixos
make publish      # builds, uploads to gs://, registers as a custom image
```

Variables (override on the command line):

| Variable | Default |
| --- | --- |
| `PROJECT` | `$(gcloud config get-value project)` |
| `REGION` | `us-central1` |
| `GCS_BUCKET` | `$(PROJECT)-nixos-images` |
| `FAMILY` | `nixos-workstation` |
| `IMAGE_NAME` | `nixos-workstation-<UTC timestamp>` |

The `family` reference (`projects/<PROJECT>/global/images/family/nixos-workstation`) always resolves to the latest image in the family, so re-publishing a new image and re-running `terraform apply` will roll the boot disk to the new build.

## Validating on a sibling VM

```bash
cd infrastructure
terraform apply \
  -var='create_nixos_sibling=true' \
  -var='nixos_image=projects/YOUR_PROJECT_ID/global/images/family/nixos-workstation'
```

This brings up `workstation-vm-nix` from the NixOS image. It does **not** attach the persistent data disk, so `/home/<user>` is empty — that's deliberate, the goal here is to verify CRD, the desktop, gcloud, and the tooling list. Things to check:

- [ ] `gcloud compute ssh workstation-vm-nix --tunnel-through-iap` succeeds
- [ ] `xfce4-session --version` runs
- [ ] `chrome-remote-desktop` service is active and `start-host --code=...` registers the host
- [ ] `gcloud --version`, `tofu version`, `pack version`, `node --version`, `docker version` all return
- [ ] `google-chrome --version` runs (need `--no-sandbox` only when running as root)

When done, set `create_nixos_sibling=false` and `terraform apply` to tear it down.

## Production cutover

```bash
terraform apply \
  -var='os_flavor=nixos' \
  -var='nixos_image=projects/YOUR_PROJECT_ID/global/images/family/nixos-workstation' \
  -var='create_nixos_sibling=false'
```

What Terraform does:

1. `google_compute_instance.vm.boot_disk.initialize_params.image` changes → boot disk replaced (the VM is destroyed and recreated, but the **persistent disk is detached and reattached**, so `/mnt/data` and the bind-mounted `/home/<user>` survive).
2. `metadata.startup-script` is removed.
3. `google_os_config_patch_deployment.daily_patch` is destroyed (replaced by image rebuilds going forward).

What you'll lose vs. keep:

| Lost | Kept |
| --- | --- |
| Anything written outside `/home/<user>`, `/mnt/data`, `/var/lib/docker` (already on `/mnt/data`) | Repos in `/mnt/data/repos`, dotfiles, gcloud auth, SSH keys (in `~/.ssh`), Docker images |
| `/etc/ssh/ssh_host_*_key` (regenerated on first boot) | n/a |

The host-key change will trigger a "REMOTE HOST IDENTIFICATION HAS CHANGED" warning on the next `gcloud compute ssh` — clear it with `ssh-keygen -R <host>` or `gcloud compute config-ssh --remove`. CRD reconnects fine; it doesn't pin SSH host keys.

## Reverting

If anything is wrong after cutover, drop back to Ubuntu:

```bash
terraform apply -var='os_flavor=ubuntu'
```

This recreates the boot disk from the Ubuntu image and re-runs `startup.sh`. Same persistent-disk preservation as above. Plan on rerunning `scripts/post-create.sh` manually afterwards (the parts that aren't already idempotent).

## What's next

Items deliberately out of scope for this PR:

- **home-manager** — porting `~/.gemini/settings.json`, `~/.bashrc`, `~/.gitconfig`, `~/.config/gcloud/configurations/` into the flake. Worth doing in a follow-up; for now those live on the persistent disk and survive cutover.
- **Secrets** — SSH host keys via Secret Manager, gcloud auth via service-account-level setup. Skipped for now; the persistent disk is the secret store.
- **Image hardening** — Shielded VM secure boot requires images signed for it. The default `nixos-generators` GCE image is not Secure-Boot signed. We may need to either disable secure boot for the NixOS sibling (`enable_shielded_vm = false` for that resource) or sign the image. Sibling VM stage is the place to discover this; the `shielded_instance_config` block on the sibling matches production for now, so we'll see if it boots.
