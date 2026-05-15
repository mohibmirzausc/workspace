{ config, pkgs, lib, user, home, ... }:

{
  # Import additional modules
  imports = [
    ./programs/karabiner.nix
    ./programs/raycast/raycast.nix
    ./programs/ghostty.nix
    ./programs/zellij.nix
    ./programs/tmux.nix
    ./programs/ticktick-sdk/config.nix
    ./programs/sops
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
    age
    cachix
    sops
    yq
    jujutsu
    neovim
    zellij
    # claude-code managed by Homebrew cask in darwin.nix
    bun
    nushell
    atuin          # Shell history tool
    carapace       # Multi-shell completion generator
    fastfetch      # System information tool
    uv
    mitmproxy
    # tmux is managed by programs.tmux in tmux.nix

    # Development tools (previously via Homebrew)
    gh             # GitHub CLI
    git-lfs        # Git Large File Storage
    graphite-cli   # Graphite stacked diffs
    kubectl        # Kubernetes CLI
    k9s            # Kubernetes TUI
    minikube       # Local Kubernetes
    nodejs         # Node.js runtime
    shopify-cli    # Shopify CLI
    teleport       # tsh - Teleport CLI
    google-cloud-sdk # gcloud CLI
    # Fly.io CLI is installed via Homebrew (see darwin.nix homebrew.brews) for
    # faster release cadence than nixpkgs. The `fly` symlink is stripped by
    # home.activation.removeBrewFlyLink below so Concourse's `/usr/local/bin/fly`
    # remains the binary `fly` resolves to.
    go             # Go programming language
    just           # Command runner
    pre-commit     # Git pre-commit hooks
    (callPackage ./programs/beads.nix {} )
    (callPackage ./programs/yaks.nix {} )
    (callPackage ./programs/git-worktree-switcher.nix {} )
    (callPackage ./programs/claude-session.nix {} )
    (callPackage ./programs/claude-code-tools/aichat-search.nix {} )
    (callPackage ./programs/claude-code-tools/package.nix {} )
    (callPackage ./programs/pi-agent {} )
    # Pi shells out to rg/fd; providing them on PATH skips the runtime download.
    ripgrep
    fd
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

    # LinearMouse config is installed via home.activation below as a mutable
    # copy (not a symlink) so the LinearMouse UI can save changes back to it.
    # See home.activation.installLinearMouseConfig.

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
    # Symlink all skills from workspace
    ".claude/skills" = {
      source = ./programs/claude/skills;
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

  # Clone agentic practice logs repository if it doesn't exist
  home.activation.cloneLogsRepo = lib.hm.dag.entryAfter ["writeBoundary"] ''
    LOGS_DIR="$HOME/.claude/claude_accessible/agentic-practice-logs"

    if [ ! -d "$LOGS_DIR/.git" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.claude/claude_accessible"
      if ! $DRY_RUN_CMD ${pkgs.git}/bin/git clone git@github.com:mohibmirzausc/agentic-practice-logs.git "$LOGS_DIR" 2>&1; then
        echo "Warning: Failed to clone agentic-practice-logs repository."
        echo "This is expected if you don't have SSH keys set up for GitHub."
        echo "You can manually clone it later or set up SSH keys."
      fi
    fi
  '';

  # Install LinearMouse config as a writable copy (not a symlink) so the
  # LinearMouse UI can save edits. The repo's programs/linearmouse.json is
  # the seed: it's copied on first install and whenever the seed changes,
  # but local UI edits between seed updates are preserved.
  home.activation.installLinearMouseConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    LM_DIR="$HOME/.config/linearmouse"
    LM_FILE="$LM_DIR/linearmouse.json"
    LM_SEED="${./programs/linearmouse.json}"
    LM_STAMP="$LM_DIR/.seed-hash"

    $DRY_RUN_CMD mkdir -p "$LM_DIR"

    # If the existing file is a symlink (legacy from when this was managed
    # via home.file), replace it with a writable copy of the seed.
    if [ -L "$LM_FILE" ]; then
      $DRY_RUN_CMD rm "$LM_FILE"
    fi

    SEED_HASH="$(${pkgs.coreutils}/bin/sha256sum "$LM_SEED" | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
    PREV_HASH=""
    if [ -f "$LM_STAMP" ]; then
      PREV_HASH="$(${pkgs.coreutils}/bin/cat "$LM_STAMP")"
    fi

    if [ ! -f "$LM_FILE" ] || [ "$SEED_HASH" != "$PREV_HASH" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 "$LM_SEED" "$LM_FILE"
      if [ -z "$DRY_RUN_CMD" ]; then
        printf '%s\n' "$SEED_HASH" > "$LM_STAMP"
      else
        echo "would write $LM_STAMP"
      fi
    fi
  '';

  # Clone yakthang repository if it doesn't exist
  home.activation.cloneYakthang = lib.hm.dag.entryAfter ["writeBoundary"] ''
    YAKTHANG_DIR="$HOME/src/yakthang"

    if [ ! -d "$YAKTHANG_DIR/.git" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/src"
      if $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/wellmaintained/yakthang.git "$YAKTHANG_DIR" 2>&1; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$YAKTHANG_DIR" submodule update --init --recursive 2>&1
      else
        echo "Warning: Failed to clone yakthang repository."
        echo "You can manually clone it later or set up SSH keys."
      fi
    fi
  '';

  # Homebrew's flyctl formula installs both `flyctl` and `fly` into
  # /opt/homebrew/bin. We keep `flyctl` but strip the `fly` symlink so it
  # doesn't shadow Concourse's `fly` CLI at /usr/local/bin/fly.
  home.activation.removeBrewFlyLink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    BREW_FLY="/opt/homebrew/bin/fly"
    if [ -e "$BREW_FLY" ] || [ -L "$BREW_FLY" ]; then
      $DRY_RUN_CMD rm -f "$BREW_FLY"
    fi
  '';

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
      # Add Nix profile to PATH (needed on Linux)
      if [ -d ~/.nix-profile/bin ]; then
        export PATH="$HOME/.nix-profile/bin:$PATH"
      fi

      # Add home-manager packages to PATH (home-manager uses a separate profile)
      HM_PROFILE="$HOME/.local/state/nix/profiles/home-manager/home-path"
      if [ -d "$HM_PROFILE/bin" ]; then
        export PATH="$HM_PROFILE/bin:$PATH"
      fi

      # Source home-manager session vars (check both profile locations)
      if [ -f ~/.nix-profile/etc/profile.d/hm-session-vars.sh ]; then
        source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
      elif [ -f "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh" ]; then
        source "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh"
      fi

      # Homebrew on PATH. /opt/homebrew on Apple Silicon, /usr/local on Intel.
      # Without this, brew-installed CLIs like flyctl aren't found.
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi

      if [ -e $HOME/.profile ]; then . $HOME/.profile; fi
      export NIXPKGS_ALLOW_UNFREE=1
      export AUTO_ENABLE_FLAKES=true

      # Source TickTick secrets if the file exists
      if [ -f $HOME/.ticktick-secrets ]; then
        source $HOME/.ticktick-secrets
      fi

      # Function instead of alias so it works with sudo
      homeswitch() {
        sudo darwin-rebuild switch --flake ~/src/workspace
      }

      alias ci='git commit -m WIP'

      # Ghostty keybind switcher (swap in current instance)
      tmux-keys() {
        ln -sf keys-tmux.conf ~/.config/ghostty/keys.conf
        pkill -SIGUSR2 ghostty 2>/dev/null
        echo "Switched to tmux keybinds"
      }
      zellij-keys() {
        ln -sf keys-zellij.conf ~/.config/ghostty/keys.conf
        pkill -SIGUSR2 ghostty 2>/dev/null
        echo "Switched to zellij keybinds"
      }

      # Launch separate Ghostty instances with their own keybinds + icons
      ghostty-tmux() {
        open -na Ghostty.app --args --config-default-files=false --config-file="$HOME/.config/ghostty/config-tmux" -e tmux new -As main
      }
      ghostty-zellij() {
        open -na Ghostty.app --args --config-default-files=false --config-file="$HOME/.config/ghostty/config-zellij" -e zellij
      }
      alias am='cd ~/src/mcp_agent_mail && uv run python -m mcp_agent_mail.http --host 127.0.0.1 --port 8765'

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
    extraEnv = ''
      # Add home-manager packages to PATH (home-manager uses a separate profile)
      let hm_bin = ($env.HOME | path join ".local/state/nix/profiles/home-manager/home-path/bin")
      if ($hm_bin | path exists) {
        $env.PATH = ($env.PATH | prepend $hm_bin)
      }
    '';
    extraConfig = ''
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };

  # Note: macOS system preferences have been moved to darwin.nix
  # User-level macOS settings can still be configured here via targets.darwin.defaults if needed
}



