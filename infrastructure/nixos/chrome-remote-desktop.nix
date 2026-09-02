# Chrome Remote Desktop, repackaged from Google's .deb.
#
# nixpkgs has no module or package for CRD (issue #34084, open since 2018).
# We extract Google's .deb, autoPatchelf the ELFs against nix-store libs, and
# rewrite the Python shebangs to a python3 with the runtime deps the .deb
# expects (dbus-python, packaging, psutil, pyxdg).
#
# CRD's binaries hardcode /opt/google/chrome-remote-desktop/* — chrome-remote-
# desktop (the Python orchestrator) execs sibling binaries by absolute path,
# and chrome-remote-desktop-host dlopens libremoting_core.so by name. The
# NixOS module side (configuration.nix) creates an /opt/google/chrome-remote-
# desktop symlink to this derivation's output so those paths resolve.
#
# `version` is informational; Google only ships chrome-remote-desktop_current
# _amd64.deb. Re-pin `hash` whenever you bump (and update the comment).

{ stdenv, lib, fetchurl
, dpkg, autoPatchelfHook, makeWrapper
, python3
, alsa-lib, atk, cairo, cups, dbus, expat, fontconfig
, gdk-pixbuf, glib, gtk3
, libdrm, libgbm, libnotify, libuuid, libxkbcommon
, nspr, nss, pam, pango, systemd
, mesa, libGL
, xorg
}:

let
  pythonEnv = python3.withPackages (ps: with ps; [
    dbus-python
    packaging
    psutil
    pyxdg
  ]);
in
stdenv.mkDerivation rec {
  pname = "chrome-remote-desktop";
  version = "148.0.7778.58";

  src = fetchurl {
    url = "https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb";
    hash = "sha256-KqIV1NTAzkL7J343DWMehaWjvS8oX34oGbKqpLmYIJg=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper ];

  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib atk cairo cups dbus expat fontconfig
    gdk-pixbuf glib gtk3
    libdrm libgbm libnotify libuuid libxkbcommon
    nspr nss pam pango systemd
    mesa libGL
  ] ++ (with xorg; [
    libX11 libxcb libXcomposite libXdamage libXext libXfixes
    libXrandr libXtst libXi libXcursor libXrender libXScrnSaver
  ]);

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src ./extracted
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r extracted/opt $out/opt
    cp -r extracted/lib $out/lib
    [ -d extracted/etc ] && cp -r extracted/etc $out/etc || true

    # Drop the auto-update cron — on NixOS we update by rebuilding the image.
    rm -rf $out/etc/cron.daily

    # Drop browser native-messaging hosts. These let a *local* Chrome control
    # CRD on this machine; we only act as a host, the controlling browser
    # lives on the user's Chromebook.
    rm -rf $out/usr 2>/dev/null || true
    rm -rf $out/etc/opt 2>/dev/null || true

    # The Debian sysvinit/multi-user unit conflicts with the templated unit
    # we actually want, and references binary update flows. Strip and keep
    # only the templated per-user unit.
    rm -f $out/lib/systemd/system/chrome-remote-desktop.service

    runHook postInstall
  '';

  postFixup = ''
    # Pin Python script shebangs to a python3 with the runtime deps the
    # CRD scripts import (dbus, packaging, psutil, xdg). The .deb mixes
    # forms — chrome-remote-desktop and configure-url-forwarder use
    # #!/usr/bin/python3, setup-session-environment uses #!/usr/bin/env
    # python3 — so the substitute calls have to match each variant.
    for f in chrome-remote-desktop configure-url-forwarder; do
      substituteInPlace $out/opt/google/chrome-remote-desktop/$f \
        --replace-fail '#!/usr/bin/python3' '#!${pythonEnv}/bin/python3'
    done
    substituteInPlace $out/opt/google/chrome-remote-desktop/setup-session-environment \
      --replace-fail '#!/usr/bin/env python3' '#!${pythonEnv}/bin/python3'

    # libremoting_core.so lives next to the binaries that link it; put that
    # directory on autoPatchelfHook's search path so RPATH resolution finds it.
    addAutoPatchelfSearchPath $out/opt/google/chrome-remote-desktop
  '';

  meta = with lib; {
    description = "Chrome Remote Desktop host (repackaged from Google's .deb)";
    homepage = "https://chrome.google.com/remotedesktop";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "chrome-remote-desktop";
  };
}
