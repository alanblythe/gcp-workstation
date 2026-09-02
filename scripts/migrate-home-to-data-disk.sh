#!/usr/bin/env bash
#
# One-time prep step: move user home onto the persistent data disk and
# bind-mount it back at /home/<user> via /etc/fstab.
#
# After this runs and the VM reboots cleanly, the boot disk contains no
# user state — so a boot-disk swap (Ubuntu reinstall, NixOS image, anything)
# preserves the user's home directory automatically.
#
# Idempotent: if /home/<user> is already a bind mount of the data-disk
# location, the script is a no-op.
#
# Modes:
#   (default)        Interactive. Prompts before the cutover so you can stop
#                    GUI sessions / long-running processes.
#   --unattended     No prompts. Used by the GCE startup-script flow where
#                    no user session is active during early boot.
#   --user <name>    Target username (defaults to WORKSTATION_USER, SUDO_USER, USER, or developer).
#
# Run as root.  Recommend logging in via SSH (gcloud compute ssh / IAP) so
# the desktop session isn't holding open file handles in /home/<user>.
#
# NOTE: The same migration logic is inlined into
#       infrastructure/scripts/startup.sh so a fresh `terraform apply` (or any
#       reboot) of an Ubuntu workstation handles this automatically. This
#       standalone script is for manual / testing / out-of-band runs.

set -euo pipefail

USER_NAME="${WORKSTATION_USER:-${SUDO_USER:-${USER:-developer}}}"
UNATTENDED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USER_NAME="$2"
      shift 2
      ;;
    --unattended)
      UNATTENDED=1
      shift
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \?//' | head -25
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

SRC="/home/${USER_NAME}"
DST_PARENT="/mnt/data/home"
DST="${DST_PARENT}/${USER_NAME}"
FSTAB_LINE="${DST} ${SRC} none bind 0 0"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Must run as root (try: sudo $0)" >&2
    exit 1
  fi
}

is_bind_mounted() {
  mount | grep -qE "^${DST} on ${SRC} type none \(.*bind"
}

ensure_persistent_disk_mounted() {
  if ! mountpoint -q /mnt/data; then
    echo "ERROR: /mnt/data is not mounted. Aborting." >&2
    exit 2
  fi
}

main() {
  require_root
  ensure_persistent_disk_mounted

  if is_bind_mounted; then
    echo "Already bind-mounted. Nothing to do."
    exit 0
  fi

  mkdir -p "${DST_PARENT}"

  echo "==> Initial rsync (will be re-run as a delta below) ..."
  rsync -aHAX --delete --info=stats2 "${SRC}/" "${DST}/"

  if [[ ${UNATTENDED} -eq 0 ]]; then
    echo
    echo "==> User session must be quiet for the cutover."
    echo "    Stop any GUI session or long-running processes owned by ${USER_NAME}, then press Enter."
    read -r _
  fi

  echo "==> Final delta rsync (catch any writes since the initial copy) ..."
  rsync -aHAX --delete --info=stats2 "${SRC}/" "${DST}/"

  # Quiesce anything that's holding files open in /home — CRD daemon is the
  # main one. We restart it after the swap so it reopens its config via the
  # bind mount.
  HOLDERS=(
    "chrome-remote-desktop@${USER_NAME}.service"
    "chrome-remote-desktop.service"
  )
  STOPPED=()
  for unit in "${HOLDERS[@]}"; do
    if systemctl is-active --quiet "${unit}"; then
      echo "==> Stopping ${unit} for the swap ..."
      systemctl stop "${unit}" || true
      STOPPED+=("${unit}")
    fi
  done

  echo "==> Swap the directory ..."
  mv "${SRC}" "${SRC}.OLD-$(date +%Y%m%d-%H%M%S)"
  mkdir "${SRC}"
  chown "${USER_NAME}:${USER_NAME}" "${SRC}"

  if ! grep -qF "${FSTAB_LINE}" /etc/fstab; then
    echo "==> Append fstab entry ..."
    cp /etc/fstab "/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
    printf '\n# Bind-mount user home from persistent data disk (added by migrate-home-to-data-disk.sh)\n%s\n' \
      "${FSTAB_LINE}" >> /etc/fstab
  fi

  echo "==> Activate the bind mount via systemd ..."
  systemctl daemon-reload
  mount "${SRC}"

  for unit in "${STOPPED[@]}"; do
    echo "==> Restarting ${unit} ..."
    systemctl start "${unit}" || true
  done

  echo
  echo "Mount table:"
  mount | grep "${SRC}" || true

  echo
  echo "Done. Recommended next step: reboot, log back in, verify everything"
  echo "works, then remove ${SRC}.OLD-* to reclaim boot-disk space."
}

main "$@"
