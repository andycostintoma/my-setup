{ username, packages }:

{ pkgs, lib, ... }:
let
  # Wireshark (and other pcap tooling) needs read/write access to /dev/bpf*.
  # macOS resets these device permissions on boot, so keep a small LaunchDaemon
  # that re-applies a safe admin-only setting.
  chmodBpf = pkgs.writeShellScript "chmod-bpf" ''
    #!/bin/sh
    set -eu

    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

    # If there are no bpf devices yet, do nothing.
    found=0
    for dev in /dev/bpf*; do
      if [ -e "$dev" ]; then
        found=1
        /usr/bin/chgrp admin "$dev" || true
        /bin/chmod 0660 "$dev" || true
      fi
    done

    if [ "$found" -eq 0 ]; then
      exit 0
    fi
  '';
in
{
  nixpkgs.config = {
    allowUnfree = true;
  };
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 3;
      Minute = 15;
    };
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  users.users.${username}.home = "/Users/${username}";
  security.sudo.extraConfig = ''
    ${username} ALL=(root) NOPASSWD:SETENV: ${pkgs.opencode}/bin/opencode
  '';
  launchd.user.envVariables.T3CODE_HOME = "/Users/${username}/.t3";
  environment.systemPackages = packages pkgs;

  launchd.daemons.chmod-bpf = {
    command = "${chmodBpf}";
    serviceConfig = {
      RunAtLoad = true;
      # Re-apply periodically (sleep/wake and macOS updates can reset perms).
      StartInterval = 60;
    };
  };

  system.activationScripts.applications.text = lib.mkAfter ''
    echo "setting up /Applications/WhatsApp.app..." >&2
    ${lib.getExe pkgs.rsync} \
      --checksum \
      --copy-unsafe-links \
      --archive \
      --delete \
      --chmod=-w \
      --no-group \
      --no-owner \
      ${pkgs.whatsapp-for-mac}/Applications/WhatsApp.app/ \
      /Applications/WhatsApp.app
  '';

  services.tailscale.enable = true;

  programs.zsh.enable = true;

  system.primaryUser = username;
  system.stateVersion = 5;
}
