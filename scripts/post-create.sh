#!/bin/bash
#
# Post-create bootstrap, run once after first connecting to a
# fresh VM. Idempotent: re-running on a configured machine is a no-op.
#
# What this does:
#   1. Installs Nix (Determinate, multi-user) if not already present.
#   2. Installs the workstation toolchain via a pinned Nix profile flake at
#      infrastructure/nix-profile/. Tools (gcloud, opentofu, pack, jupyter,
#      gemini-cli, etc.) land in ~/.nix-profile/bin and shadow apt versions.
#   3. Drops ~/.gemini/settings.json with the IDE+vertex-ai defaults.
#
# What this *doesn't* do:
#   - Install Docker, Chrome Remote Desktop, the X server, xfce — those are
#     handled by infrastructure/scripts/startup.sh (apt-driven, system-level).
#   - Install gemini-cli via npm — superseded by the Nix profile entry.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Installing Nix (idempotent) ..."
if [ ! -e /nix/var/nix/profiles/default ]; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sudo sh -s -- install linux --no-confirm --determinate
else
  echo "    Nix already present at /nix; skipping installer."
fi

# Source Nix env into this shell so the next steps can see `nix`.
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Installing workstation tooling via Nix profile ..."
# `nix profile install` errors if the same package is already installed, so
# detect and upgrade instead of reinstalling on a re-run.
if nix profile list 2>/dev/null | grep -qF "infrastructure/nix-profile"; then
  echo "    Profile entry exists; upgrading."
  nix profile upgrade --all
else
  nix profile install "${REPO_DIR}/infrastructure/nix-profile"
fi

echo "==> Writing ~/.gemini/settings.json ..."
mkdir -p ~/.gemini
cat > ~/.gemini/settings.json <<'EOF'
{
  "ide": {
    "enabled": true,
    "hasSeenNudge": true
  },
  "security": {
    "auth": {
      "selectedType": "vertex-ai"
    }
  }
}
EOF

echo "==> Configuring VS Code keyring (gnome-libsecret) ..."
mkdir -p ~/.local/share/keyrings ~/.vscode
if [ -f ~/.vscode/argv.json ]; then
    if grep -q '"password-store"' ~/.vscode/argv.json; then
        sed -i 's/"password-store": ".*"/"password-store": "gnome-libsecret"/' ~/.vscode/argv.json
    else
        sed -i 's/{/{\n  "password-store": "gnome-libsecret",/' ~/.vscode/argv.json
    fi
else
    printf '{\n  "password-store": "gnome-libsecret"\n}\n' > ~/.vscode/argv.json
fi

echo "==> Done. Open a new shell or 'exec bash' to pick up ~/.nix-profile/bin on PATH."
