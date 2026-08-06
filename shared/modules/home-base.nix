{
  homeDirectory,
  gitEmail,
  extraGitConfig ? "",
}:

{
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.gh.enable = true;
  programs.jq.enable = true;

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
  };

  home.file.".gitignore_global" = {
    force = true;
    text = "";
  };

  home.file.".gitconfig" = {
    force = true;
    text = ''
      [user]
          name = Andy Toma
          email = ${gitEmail}

      [init]
          defaultBranch = main

      [pull]
          rebase = true

      [credential]
          helper =

      ${extraGitConfig}
      [core]
          excludesfile = ${homeDirectory}/.gitignore_global
          editor = vim
    '';
  };
}
