{
  username,
  harness,
  packages,
}:

{ pkgs, ... }:
let
  homeDirectory = "/home/${username}";
in
{
  imports = [
    (import ../shared/opencode.nix {
      inherit homeDirectory harness;
    })
  ];

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "25.05";
  home.packages = packages pkgs;

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  home.file.".gitconfig" = {
    force = true;
    text = ''
      [user]
          name = Andy Toma
          email = andy.toma@medidrive.com

      [init]
          defaultBranch = main

      [pull]
          rebase = true

      [credential]
          helper =

      [url "ssh://git@github.com/MediDrive-Tech/"]
          insteadOf = https://github.com/MediDrive-Tech/
      [core]
          excludesfile = ${homeDirectory}/.gitignore_global
          editor = vim
    '';
  };

  home.file.".gitignore_global" = {
    force = true;
    text = "";
  };

  home.file.".ssh/config" = {
    force = true;
    text = ''
      Host github.com
        HostName github.com
        User git
        IdentitiesOnly yes
    '';
  };

  home.file.".zprofile" = {
    force = true;
    text = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      elif [ -e /etc/profile.d/nix.sh ]; then
        . /etc/profile.d/nix.sh
      fi

      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi

      export PATH="$HOME/.nix-profile/bin:$PATH"
    '';
  };

  programs.home-manager.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" ];
    };
    shellAliases = {
      hm-switch = "home-manager switch --flake ~/.config/my-setup#medidrive";
      ll = "ls -lah";
      opencode = "${pkgs.opencode}/bin/opencode";
    };
  };

  programs.bash.enable = true;
  programs.git.enable = true;
  programs.gh.enable = true;
  programs.jq.enable = true;
}
