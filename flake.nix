{
  description = "Andy Toma's minimal Nix, Home Manager, nix-darwin, and direnv setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, nix-darwin, home-manager, ... }:
    let
      username = "andytoma";
      host = "Andys-Mac-mini";

      mkPkgs = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      globalPackages = pkgs: with pkgs; [
        bat
        curl
        delta
        direnv
        eza
        fd
        fzf
        gh
        git
        jq
        opencode
        ripgrep
        shellcheck
        shfmt
        tmux
        tree
        wget
        yq
        zoxide
      ];

      # Transitional Brew parity: packages that were previously installed as
      # Homebrew leaves and are available in nixpkgs. Split project-specific
      # tools into per-repo flakes after Brew is removed.
      brewFormulaParityPackages = pkgs: with pkgs; [
        ffmpeg
        graphviz
        mermaid-cli
        mkcert
        msmtp
        mutt
        nextdns
        ollama
        pandoc
        pgcli
        poppler-utils
        rtk
        p7zip
        stripe-cli
        tesseract
        uv
        watch
      ];

      darwinCliPackages = pkgs: with pkgs; [
        claude-code
      ];

      darwinAppPackages = pkgs: with pkgs; [
        discord
        ghostty-bin
        google-chrome
        jetbrains-toolbox
        libreoffice-bin
        obsidian
        orbstack
        postman
        qbittorrent
        rectangle
        slack
        tailscale
        telegram-desktop
        vscode
        whatsapp-for-mac
        zoom-us
      ];

      homeModule = { pkgs, lib, ... }: {
        home.username = username;
        home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
        home.stateVersion = "25.05";
        home.packages =
          globalPackages pkgs
          ++ lib.optionals pkgs.stdenv.isDarwin (brewFormulaParityPackages pkgs)
          ++ lib.optionals pkgs.stdenv.isDarwin (darwinCliPackages pkgs);

        home.file.".zprofile".text = ''
          export LANG=en_US.UTF-8
          export LC_ALL=en_US.UTF-8
        '';

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
          oh-my-zsh.enable = true;
          shellAliases = {
            medidrive = "ssh -i ~/.ssh/medidrive_key -o IdentitiesOnly=yes -t andy@35.243.44.225 'cd ~/medidrive && exec $SHELL -l'";
            medidrive-sync = "rsync -az --delete -e 'ssh -i ~/.ssh/medidrive_key -o IdentitiesOnly=yes' andy@35.243.44.225:~/medidrive/ ~/medidrive-local/";
            hm-switch = "home-manager switch --flake ~/.config/nix-darwin";
            nix-switch = "sudo darwin-rebuild switch --flake ~/.config/nix-darwin";
          };
        };

        programs.git = {
          enable = true;
        };

        programs.delta = {
          enable = true;
          enableGitIntegration = true;
        };

        programs.fzf = {
          enable = true;
          enableZshIntegration = true;
        };

        programs.zoxide = {
          enable = true;
          enableZshIntegration = true;
        };

        programs.bat.enable = true;
        programs.eza.enable = true;
        programs.gh.enable = true;
        programs.jq.enable = true;
        programs.neovim = {
          enable = true;
          withPython3 = false;
          withRuby = false;
        };
      };

      mkHome = system: home-manager.lib.homeManagerConfiguration {
        pkgs = mkPkgs system;
        modules = [ homeModule ];
      };
    in {
      darwinConfigurations.${host} = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ({ pkgs, ... }: {
            nixpkgs.config.allowUnfree = true;
            nix.settings.experimental-features = "nix-command flakes";
            nix.gc = {
              automatic = true;
              interval = { Weekday = 0; Hour = 3; Minute = 15; };
              options = "--delete-older-than 14d";
            };
            nix.optimise.automatic = true;

            users.users.${username}.home = "/Users/${username}";
            environment.systemPackages = [
              home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
            ] ++ darwinAppPackages pkgs;

            programs.zsh.enable = true;

            system.primaryUser = username;
            system.stateVersion = 5;
          })
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-nix-darwin";
            home-manager.users.${username} = homeModule;
          }
        ];
      };

      homeConfigurations.${username} = mkHome "aarch64-darwin";
      homeConfigurations."${username}@linux" = mkHome "x86_64-linux";

    };
}
