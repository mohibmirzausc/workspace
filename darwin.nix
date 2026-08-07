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
  # No overlays currently. Both previous ones were removed in the nixpkgs
  # 26.11 upgrade:
  #
  #   shopify-cli  existed only to bump the package to 3.90.1, and nixpkgs now
  #                ships 4.6.0 (upstream's latest). It also pinned
  #                fetchPnpmDeps fetcherVersion = 2, which 26.11 removed
  #                outright, so it broke evaluation.
  #   zellij       patched a hardcoded 3-line mouse-wheel scroll down to 1.
  #                Any overrideAttrs changes the derivation hash, so this cost
  #                a full from-source Rust rebuild of zellij on every nixpkgs
  #                bump -- a large, slow build for a one-line cosmetic tweak,
  #                and the version/src/cargoDeps it also pinned had been
  #                overtaken by nixpkgs anyway. Dropped in favour of the cached
  #                build; mouse wheel now scrolls zellij's default 3 lines.
  #                Upstream still has no config option for this (checked
  #                against the 0.44.x release notes), so restoring the patch
  #                means reinstating the overlay and accepting the rebuild.
  nixpkgs.overlays = [
    # (import ./overlays/claude-code-overlay.nix)  # Using Homebrew cask instead
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
      # cmux settings that its cmux.json schema does NOT cover. Everything
      # expressible in the schema is pinned declaratively in programs/cmux.nix
      # instead (cmux imports that JSON into this same defaults domain); these
      # keys exist only here, so without this block they silently drift back to
      # cmux's defaults on a fresh machine.
      "com.cmuxterm.app" = {
        # Compact sidebar rows: show only the last path segment rather than the
        # full workspace path.
        sidebarPathLastSegmentOnly = false;
        # Chrome-less workspace presentation ("minimal" hides the tab bar).
        workspacePresentationMode = "minimal";
        # Global show/hide hotkey.
        "systemWideHotkey.enabled" = true;
        # Idle-screen mascot/glow/theme, all set to the cmux branding.
        "sleepyMode.mascot" = "cmux";
        "sleepyMode.glow" = "cmux";
        "sleepyMode.theme" = "cmux";
        # Render custom sidebars in-process (the alternative spawns a helper).
        "customSidebars.renderer" = "inProcess";
        "customSidebars.beta.enabled" = false;
        # Right sidebar shows the file tree; beta dock mode off.
        "rightSidebar.mode" = "files";
        "rightSidebar.beta.dock.enabled" = false;
        "sidebar.beta.workspaceTodos.controls.enabled" = true;
        # iPhone pairing host disabled.
        "mobile.iOSPairingHost.enabled" = false;
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
    # Third-party taps. Must be declared here as well as in `brews` below:
    # onActivation.cleanup = "uninstall" prunes taps that aren't listed, so an
    # undeclared tap would be removed on every switch and re-added on the next.
    #
    # ONE-TIME MANUAL STEP on a new machine: Homebrew refuses to load formulae
    # from third-party taps until they are explicitly trusted, so activation
    # fails with "Refusing to load formula ... from untrusted tap" until you run
    #
    #     brew trust superradcompany/tap
    #
    # once. This cannot be declared here: `brew trust` records the decision in
    # ~/.homebrew/trust.json (or $XDG_CONFIG_HOME/homebrew/trust.json), which
    # nix-darwin does not manage.
    taps = [
      "superradcompany/tap"  # microsandbox; see brews below
    ];
    # Fly.io CLI. Homebrew ships the formula with daily updates, well ahead of
    # nixpkgs. The formula drops both `flyctl` and `fly` into /opt/homebrew/bin;
    # home.nix removes the `fly` symlink on activation so it doesn't shadow
    # Concourse's `fly` CLI at /usr/local/bin/fly. See home.activation.removeBrewFlyLink.
    brews = [
      "flyctl"
      "pi-coding-agent"  # Pi terminal coding agent (pi.dev). Homebrew ships it
                         # ahead of nixpkgs and autoUpdate/upgrade keep it current.
      # nono (nono.sh, github.com/nolabs-ai/nono): capability sandbox for AI
      # coding agents. Declares fs/network access up front and lets the kernel
      # enforce it -- Seatbelt on macOS, Landlock on Linux -- so no daemon, no
      # container, no VM, and the agent cannot widen its own constraints from
      # the inside. Shape is `nono run --profile <p> -- <agent>`.
      #
      # Paired with microsandbox below deliberately: the two sit at different
      # points on the isolation/overhead curve and we want to compare them on
      # real moab runs. nono is process-level and needs nothing installed
      # inside it, so the existing node/ACP-adapter/credential setup works
      # unchanged; microsandbox is a hardware boundary but needs a guest image.
      # moab's own backend evaluation (docs/sandbox/sandbox-evaluation.md in
      # the moab repo) scores nono 5/5/5/5/5/5 and rates microsandbox a 2 on
      # fit, VM-based backends being out of scope there -- so nono is the
      # likelier long-term answer for wrapping agents.
      #
      # In homebrew-core, so unlike microsandbox it needs no `brew trust`.
      "nono"
      # microsandbox (microsandbox.dev): runs untrusted code -- AI agents,
      # plugins, CI jobs -- in hardware-isolated microVMs that boot in
      # milliseconds. Installs the `msb` CLI (not `microsandbox`).
      #
      # Homebrew rather than nixpkgs for two reasons. It isn't in nixpkgs at
      # all, and more importantly the release binary is code-signed with the
      # com.apple.security.hypervisor and disable-library-validation
      # entitlements it needs to boot VMs. The formula is careful to install it
      # without running install_name_tool, because touching the binary would
      # invalidate that signature and strip the entitlements, and macOS would
      # then kill it on launch. A nixpkgs-style build that patches rpaths would
      # hit exactly that problem.
      #
      # Apple Silicon only -- the formula calls `odie` on x86_64 macOS.
      "superradcompany/tap/microsandbox"
    ];
    casks = [
      "1password-cli"
      "calibre"
      "claude-code@latest"  # Auto-updating Claude Code CLI (v2.1.140)
      "codex"         # OpenAI's terminal coding agent (github.com/openai/codex).
                      # Depends on ripgrep (already provided in home.nix).
      "cmux"          # Ghostty-based macOS terminal for running AI agents in
                      # parallel; reads ~/.config/ghostty/config for appearance.
                      # cmux-specific config in programs/cmux.nix. Auto-updates.
      "eqmac"         # System-wide EQ + gain; boosts output volume above 100%
                      # (e.g. to hear people better in Zoom). First launch needs
                      # a one-time audio-driver approval in System Settings.
      "flycut"
      "fossa"
      "gcloud-cli"
      # greedy: the cask is marked auto_updates upstream, so `brew bundle`
      # skips it and defers to Karabiner's own updater -- which left this
      # machine stranded on 15.7.0 (Nov 2025) while 16.1.0 was current.
      # greedy upgrades it on rebuild regardless. Set per-cask rather than
      # via onActivation.greedy so the other auto_updates casks (cmux,
      # raycast, linearmouse, thaw) keep self-updating on their own schedule.
      #
      # NOTE: Karabiner 16.0.0+ requires a NEW Accessibility grant for
      # Karabiner-Core-Service. TCC grants cannot be automated (SIP-protected),
      # so after the upgrade lands, approve it in System Settings > Privacy &
      # Security > Accessibility or Karabiner will silently stop working.
      {
        name = "karabiner-elements";
        greedy = true;
      }
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
