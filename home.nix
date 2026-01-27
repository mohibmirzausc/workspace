{ config, pkgs, lib, user, home, ... }:

{
  # Import additional modules
  imports = [
    ./programs/karabiner.nix
    ./programs/raycast/raycast.nix
    ./programs/ghostty.nix
    ./programs/ticktick-sdk/config.nix
  ];

  # Note: nixpkgs configuration is now handled by darwin.nix when using nix-darwin
  # with home-manager.useGlobalPkgs

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = user;
  home.homeDirectory = home;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello
    yq
    jujutsu
    neovim
    zellij
    claude-code
    bun
    nushell
    atuin          # Shell history tool
    carapace       # Multi-shell completion generator
    fastfetch      # System information tool
    mitmproxy

    # Development tools (previously via Homebrew)
    gh             # GitHub CLI
    kubectl        # Kubernetes CLI
    minikube       # Local Kubernetes
    nodejs         # Node.js runtime
    pre-commit     # Git pre-commit hooks
    (callPackage ./programs/beads.nix {} )
    # direnv already configured in programs.direnv

    # Python with ticktick-sdk
    (python3.withPackages (ps: with ps; [
      (callPackage ./programs/ticktick-sdk/package.nix {})
    ]))
  ] ++ [
    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ]++(if pkgs.stdenv.isDarwin then [
    raycast
    coder
    ghostty-bin
    opencode
  ] else []);

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    # Claude Code configuration
    ".claude/settings.json" = {
      source = ./programs/claude/settings.json;
      force = true;
    };
    ".claude/beep-state" = {
      source = ./programs/claude/beep-state;
      force = true;
    };
    ".claude/hooks" = {
      source = ./programs/claude/hooks;
      force = true;
    };
    ".claude/commands" = {
      source = ./programs/claude/commands;
      recursive = true;
      force = true;
    };
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/mohib/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.direnv = {
    enable = true;
    enableZshIntegration=true;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    initExtra = ''
      if [ -e $HOME/.profile ]; then . $HOME/.profile; fi
      export NIXPKGS_ALLOW_UNFREE=1
      export AUTO_ENABLE_FLAKES=true

      # Source TickTick secrets if the file exists
      if [ -f $HOME/.ticktick-secrets ]; then
        source $HOME/.ticktick-secrets
      fi

      # Function instead of alias so it works with sudo
      homeswitch() {
        sudo darwin-rebuild switch --flake ~/src/workstations/home/mohib/
      }

      alias ci='git commit -m WIP'

      # Command completion beep
      BEEP_ENABLED=1
      BEEP_THRESHOLD=5  # seconds

      preexec() {
        cmd_start=$SECONDS
      }

      precmd() {
        if [ $cmd_start ]; then
          elapsed=$((SECONDS - cmd_start))
          if [ $elapsed -gt $BEEP_THRESHOLD ] && [ $BEEP_ENABLED -eq 1 ]; then
            osascript -e 'beep 1' >/dev/null 2>&1 &
          fi
          unset cmd_start
        fi
      }

      # Mute/unmute commands
      mute-beep() {
        BEEP_ENABLED=0
        echo "Beep muted"
      }

      unmute-beep() {
        BEEP_ENABLED=1
        echo "Beep unmuted"
      }

      # Claude Code beep control
      claude-beep-mute() {
        echo "DISABLED" > ~/.claude/beep-state
        echo "Claude Code beep muted"
      }

      claude-beep-unmute() {
        echo "ENABLED" > ~/.claude/beep-state
        echo "Claude Code beep unmuted"
      }

      claude-beep-status() {
        if [ -f ~/.claude/beep-state ]; then
          state=$(cat ~/.claude/beep-state)
          echo "Claude Code beep: $state"
        else
          echo "Claude Code beep: ENABLED (default)"
        fi
      }
    '';
    history = {
      ignoreSpace = true;
      ignoreDups = true;
      save = 100000;
      size = 100000;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Mohib Mirza";
        email = "mohibmirzaswe@gmail.com";
      };
      alias = {
        ci = "commit";
      };
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.nushell = {
    enable = true;
    environmentVariables = {
      # Add any env vars if needed
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };

  # Note: macOS system preferences have been moved to darwin.nix
  # User-level macOS settings can still be configured here via targets.darwin.defaults if needed
}



