#!/bin/bash
set -e

# Logging
exec > >(tee /var/log/startup-script.log|logger -t startup-script -s 2>/dev/console) 2>&1

echo "Ensuring hostname is resolvable..."
if ! grep -q "127.0.0.1 $(hostname)" /etc/hosts; then
    echo "127.0.0.1 $(hostname)" >> /etc/hosts
fi

echo "Cleaning up stale X11 lock files..."
rm -f /tmp/.X*-lock
rm -rf /tmp/.X11-unix
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# ---------------------------------------------------------------------------
# Step A: bind-mount user home from the persistent data disk.
#
# Makes /home survive a boot-disk swap. Runs every boot; once the bind is in
# fstab + mounted, the rest of this block is a no-op. The standalone version
# of this logic lives in scripts/migrate-home-to-data-disk.sh and supports
# --unattended for manual / out-of-band runs.
# ---------------------------------------------------------------------------
METADATA_USER="$(curl -s -f -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/workstation-user" 2>/dev/null || true)"
USER_NAME="${METADATA_USER:-${WORKSTATION_USER:-${SUDO_USER:-developer}}}"
HOME_SRC="/home/${USER_NAME}"
HOME_DST="/mnt/data/home/${USER_NAME}"
FSTAB_LINE="${HOME_DST} ${HOME_SRC} none bind 0 0"

if mount | grep -qE "^${HOME_DST} on ${HOME_SRC} type none \(.*bind"; then
    echo "[home-migrate] /home/${USER_NAME} already bind-mounted from data disk; skipping."
elif ! mountpoint -q /mnt/data; then
    echo "[home-migrate] WARNING: /mnt/data not mounted; cannot migrate /home this boot." >&2
else
    echo "[home-migrate] Bind-mounting /home/${USER_NAME} → ${HOME_DST} ..."

    # google-startup-scripts.service is After=multi-user.target, so by the
    # time we run, chrome-remote-desktop@${USER_NAME}.service is already
    # holding ${HOME_SRC}/.config/chrome-remote-desktop/host#*.json open.
    # Stop it around the swap so the bind mount becomes the canonical source
    # before any user session attaches. The user is reconnecting via CRD
    # after their reboot anyway, so the brief downtime is invisible.
    HOLDERS=(
        "chrome-remote-desktop@${USER_NAME}.service"
        "chrome-remote-desktop.service"
    )
    STOPPED=()
    for unit in "${HOLDERS[@]}"; do
        if systemctl is-active --quiet "${unit}"; then
            echo "[home-migrate] Stopping ${unit} ..."
            systemctl stop "${unit}" || true
            STOPPED+=("${unit}")
        fi
    done

    mkdir -p "$(dirname "${HOME_DST}")"

    # Copy current /home contents to the destination. Idempotent: rsync only
    # ships changed files. Fresh box → full copy; re-run after the standalone
    # script's prior rsync → tiny delta.
    rsync -aHAX --delete --info=stats0 "${HOME_SRC}/" "${HOME_DST}/"

    # Swap the directory in place. The .OLD-* dir is left behind for one
    # cycle so the operator can verify and reclaim space manually.
    mv "${HOME_SRC}" "${HOME_SRC}.OLD-$(date +%Y%m%d-%H%M%S)"
    mkdir "${HOME_SRC}"
    chown "${USER_NAME}:${USER_NAME}" "${HOME_SRC}"

    if ! grep -qF "${FSTAB_LINE}" /etc/fstab; then
        cp /etc/fstab "/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
        printf '\n# Bind-mount user home from persistent data disk (added by startup.sh)\n%s\n' \
          "${FSTAB_LINE}" >> /etc/fstab
    fi

    systemctl daemon-reload || true
    mount "${HOME_SRC}"

    for unit in "${STOPPED[@]}"; do
        echo "[home-migrate] Starting ${unit} ..."
        systemctl start "${unit}" || true
    done

    echo "[home-migrate] Done."
fi

# ---------------------------------------------------------------------------
# Step B: install the desktop + Chrome + Chrome Remote Desktop.
#
# Idempotent via the /etc/chrome_remote_desktop_installed sentinel.
# ---------------------------------------------------------------------------
if [ -f /etc/chrome_remote_desktop_installed ]; then
    echo "Chrome Remote Desktop already installed. Skipping installation steps."
else
    export DEBIAN_FRONTEND=noninteractive

    echo "Updating repositories..."
    apt-get update

    echo "Installing Desktop Environment (Xfce4) and Keyring..."
    apt-get install -y xfce4 xfce4-goodies desktop-base dbus-x11 xscreensaver gnome-keyring libsecret-1-0 libsecret-tools

    echo "Installing Google Chrome..."
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt-get install -y ./google-chrome-stable_current_amd64.deb
    rm google-chrome-stable_current_amd64.deb

    echo "Installing Chrome Remote Desktop..."
    wget -q https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    apt-get install -y ./chrome-remote-desktop_current_amd64.deb
    rm chrome-remote-desktop_current_amd64.deb

    echo "Configuring Chrome Remote Desktop session..."
    if [ ! -f /etc/chrome-remote-desktop-session ]; then
        bash -c 'echo "exec /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session'
    fi

    touch /etc/chrome_remote_desktop_installed
fi

echo "Installation complete/checked."
