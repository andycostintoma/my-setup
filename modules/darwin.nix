{ username, packages }:

{ pkgs, lib, ... }:
{
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "openclaw-2026.5.7"
    ];
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
  environment.systemPackages = packages pkgs;
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
