{ config, pkgs, lib, ... }:

let
  # CRD is repackaged in-tree from Google's .deb. nixpkgs doesn't have it
  # (issue #34084). See chrome-remote-desktop.nix for the gory details.
  chrome-remote-desktop = pkgs.callPackage ./chrome-remote-desktop.nix { };

  # Primary workstation username (override or adjust as needed)
  workstationUser = "developer";
in
{
  # The 'gce' format from nixos-generators wires up the GCE-specific bits
  # (serial console, oslogin, metadata-driven SSH keys, etc.). We only
  # express the workstation-specific layer here.

  nixpkgs.config.allowUnfree = true;  # google-chrome, chrome-remote-desktop

  networking.hostName = "gcp-workstation";
  time.timeZone = "America/New_York";

  # ---- Users -----------------------------------------------------------------
  # GCE oslogin will create users dynamically; we still declare workstationUser so the
  # bind-mount target exists and group memberships are deterministic. Match
  # the UID (1001) to keep file ownership stable when the home dir
  # bind-mounts in from the persistent disk.
  users.users."${workstationUser}" = {
    isNormalUser = true;
    uid          = 1001;
    extraGroups  = [ "wheel" "docker" "chrome-remote-desktop" "video" ];
    home         = "/home/${workstationUser}";
    shell        = pkgs.bash;
  };
  security.sudo.wheelNeedsPassword = false;

  # CRD's network process runs sandboxed under a Debian-policy underscore-
  # prefixed system user. The Debian postinst creates this with adduser; we
  # declare it directly.
  users.users."_crd_network" = {
    isSystemUser = true;
    group        = "_crd_network";
    description  = "Chrome Remote Desktop network sandbox";
  };
  users.groups."_crd_network" = { };
  users.groups.chrome-remote-desktop = { };

  # ---- Persistent data disk + bind-mounted home -----------------------------
  # The 200GB pd-ssd attached as /dev/sdb1 holds /mnt/data and /home/${workstationUser}.
  # 'nofail' so the system still boots if the disk is detached (e.g. during
  # the sibling-VM testing flow).
  fileSystems."/mnt/data" = {
    device  = "/dev/disk/by-uuid/baae8b02-9405-43eb-acbe-0c159941ba24";
    fsType  = "ext4";
    options = [ "defaults" "nofail" "x-systemd.device-timeout=10s" ];
  };

  fileSystems."/home/${workstationUser}" = {
    device  = "/mnt/data/home/${workstationUser}";
    fsType  = "none";
    options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/data" ];
  };

  # ---- SSH (used by gcloud / IAP tunnel) ------------------------------------
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # ---- Desktop + Chrome Remote Desktop --------------------------------------
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.displayManager.defaultSession = "xfce";

  # CRD's binaries hardcode /opt/google/chrome-remote-desktop/* — Python
  # scripts exec sibling binaries by absolute path, the host binary
  # dlopens libremoting_core.so by SONAME from its own directory. Symlink
  # /opt/google/chrome-remote-desktop into the package output so those
  # absolute paths resolve, and /opt/google itself is a directory (some
  # Google software writes adjacent files there).
  systemd.tmpfiles.rules = [
    "d /opt/google 0755 root root - -"
    "L+ /opt/google/chrome-remote-desktop - - - - ${chrome-remote-desktop}/opt/google/chrome-remote-desktop"
  ];

  # The .deb's PAM file references Debian's common-* includes, which don't
  # exist on NixOS. Use NixOS's PAM defaults — they cover the auth/account/
  # session stack CRD needs.
  security.pam.services.chrome-remote-desktop = { };

  # Install the templated unit (chrome-remote-desktop@.service) from the
  # package, then enable the per-user instance for workstationUser. The unit's
  # ExecStart= references /opt/google/chrome-remote-desktop/... — the
  # tmpfiles symlink above makes that work. `path` puts the X tooling CRD
  # spawns (Xvfb, xrandr, xkbcomp, xauth, etc.) on the service PATH.
  systemd.packages = [ chrome-remote-desktop ];
  systemd.services."chrome-remote-desktop@${workstationUser}" = {
    overrideStrategy = "asDropin";
    wantedBy         = [ "multi-user.target" ];
    path = with pkgs; [
      xorg.xorgserver  # provides Xvfb
      xorg.xkbcomp xorg.xauth xorg.xrandr xorg.xset xorg.xdpyinfo
      xorg.xf86videodummy
      xfce.xfce4-session xfce.xfce4-panel xfce.xfdesktop xfce.thunar
      bash coreutils util-linux psmisc procps xdg-utils
    ];
  };

  # ---- Docker ---------------------------------------------------------------
  # Match current data-root so existing images/containers on the persistent
  # disk are picked up after the boot-disk swap.
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/data/docker";
    };
  };

  # ---- Workstation tooling --------------------------------------------------
  # This list intentionally mirrors what scripts/post-create.sh installs
  # imperatively today. Add new tools here, not via curl|sh.
  environment.systemPackages = [
    chrome-remote-desktop  # so `start-host --code=...` is on $PATH
  ] ++ (with pkgs; [
    google-chrome
    google-cloud-sdk
    opentofu
    pack            # Cloud-Native Buildpacks 'pack' CLI
    nodejs_22
    python3
    python3Packages.pip
    python3Packages.ipykernel
    python3Packages.jupyter
    python3Packages.notebook

    git
    curl
    wget
    jq
    rsync
    unzip
    tree
    htop
    tmux
    file
    ripgrep
  ]);

  # ---- Misc -----------------------------------------------------------------
  # Keep nix-store from filling up over time.
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 14d";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Pin the state version to the nixpkgs branch we're tracking. Don't bump
  # this casually; it controls compatibility behavior of stateful services.
  system.stateVersion = "25.11";
}
