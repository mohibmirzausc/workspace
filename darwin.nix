{ config, pkgs, lib, user, home, system, ... }:

{
  imports = [
    ./programs/shottr.nix
  ];

  # Disable nix-darwin's Nix management (using Determinate Nix)
  nix.enable = false;

  # Necessary for using flakes on this system
  nix.settings.experimental-features = "nix-command flakes";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Apply overlays for package overrides
  nixpkgs.overlays = [
    # (import ./overlays/claude-code-overlay.nix)  # Using Homebrew cask instead
    (import ./overlays/shopify-cli-overlay.nix)
    (import ./overlays/zellij-overlay.nix { mouseScrollLines = 1; })
  ];

  # Primary user for system operations
  system.primaryUser = user;

  # User configuration
  users.users.${user} = {
    name = user;
    home = home;
  };

  # System-wide packages (optional - most can stay in home.nix)
  environment.systemPackages = with pkgs; [
    vim
  ];

  # macOS system defaults
  system.defaults = {
    # Configure dock at bottom (accessible on all monitors) with speed improvements
    dock = {
      orientation = "bottom";
      autohide = true;
      show-process-indicators = true;
      show-recents = false;
      # Speed up dock autohide animation
      autohide-time-modifier = 0.5;
      autohide-delay = 0.0;
      # Speed up expose animation
      expose-animation-duration = 0.1;
      # Minimize windows into application icon
      minimize-to-application = true;
      # Don't rearrange spaces based on most recent use
      mru-spaces = false;
      # Scroll up on dock icon to show all windows or open stack
      scroll-to-open = true;
      # Show only open applications in the dock
      static-only = true;
    };

    # Speed up animations by 2x (reduce animation duration by half)
    NSGlobalDomain = {
      # Reduce window resize time
      NSWindowResizeTime = 0.1;
      # Set icon and widget style to dark mode
      AppleInterfaceStyle = "Dark";
      # Automatically switch between light and dark mode
      AppleInterfaceStyleSwitchesAutomatically = true;
      # Speed up key repeat rate (lower = faster, range 2-120, default 6)
      KeyRepeat = 2;
      # Reduce initial delay before key repeat (lower = faster, range 15-120, default 68)
      InitialKeyRepeat = 15;
    };

    # Spotlight settings - disable the default Command+Space shortcut
    # This disables the Spotlight search keyboard shortcut
    CustomUserPreferences = {
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Disable Spotlight search (Command+Space)
          "64" = {
            enabled = false;
            value = {
              parameters = [ 32 49 1048576 ];
              type = "standard";
            };
          };
          # Disable "Show Desktop" gesture (clicking desktop to hide windows)
          "36" = {
            enabled = false;
          };
          "37" = {
            enabled = false;
          };
        };
      };
      # Disable Stage Manager if on macOS Ventura or later
      "com.apple.WindowManager" = {
        GloballyEnabled = false;
        AutoHide = false;
        StageManagerHideWidgets = false;
      };
      # Note: com.apple.universalaccess is applied via system.activationScripts
      # below because it's a protected domain that may fail silently
    };
  };

  # Apply protected accessibility defaults (best-effort, may fail without Full Disk Access)
  system.activationScripts.postActivation.text = ''
    defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true 2>/dev/null || true
    defaults write com.apple.universalaccess closeViewScrollWheelModifiersInt -int 1048576 2>/dev/null || true
  '';

  # Enable Touch ID for sudo (including inside tmux sessions)
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation = {
      # "uninstall" removes Homebrew packages not listed here but, unlike "zap",
      # respects dependencies. "zap" tried to remove ca-certificates/openssl@3/etc.
      # that gcloud-cli depends on, producing a "Refusing to uninstall ... required
      # by gcloud-cli" error on every run. "uninstall" is dependency-aware and quiet.
      cleanup = "uninstall";
      autoUpdate = true;
      upgrade = true;
    };
    # Fly.io CLI. Homebrew ships the formula with daily updates, well ahead of
    # nixpkgs. The formula drops both `flyctl` and `fly` into /opt/homebrew/bin;
    # home.nix removes the `fly` symlink on activation so it doesn't shadow
    # Concourse's `fly` CLI at /usr/local/bin/fly. See home.activation.removeBrewFlyLink.
    brews = [
      "flyctl"
    ];
    casks = [
      "1password-cli"
      "calibre"
      "claude-code@latest"  # Auto-updating Claude Code CLI (v2.1.140)
      "flycut"
      "fossa"
      "gcloud-cli"
      "karabiner-elements"
      "linearmouse"   # Fast-scroll when holding modifier key (configured in home.nix)
      "superwhisper"
      "raycast"
      "thaw"          # Menu bar manager (Ice fork) for macOS 26+
      "ticktick"
      "finetune"
    ];
  };

  # Always-on local gallery server for the `html-page` Claude skill. Runs at
  # login, restarts on crash, serves ~/html-pages at http://localhost:7777.
  # Managed here (nix-darwin launchd.user.agents) rather than home-manager's
  # launchd.agents, which is not activated when HM runs as a nix-darwin module.
  launchd.user.agents.html-pages-server = {
    serviceConfig = {
      ProgramArguments = [ "${pkgs.callPackage ./programs/html-pages-server { }}/bin/html-pages-server" ];
      EnvironmentVariables = {
        PORT = "7777";
        HTML_PAGES_DIR = "${home}/html-pages";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${home}/Library/Logs/html-pages-server.log";
      StandardErrorPath = "${home}/Library/Logs/html-pages-server.log";
    };
  };

  # Used for backwards compatibility, please read the changelog before changing
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on. Provided by flake.nix
  # specialArgs so the same config works on both Apple Silicon and Intel Macs.
  nixpkgs.hostPlatform = system;
}
