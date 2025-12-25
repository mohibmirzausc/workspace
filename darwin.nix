{ config, pkgs, lib, ... }:

{
  # Disable nix-darwin's Nix management (using Determinate Nix)
  nix.enable = false;

  # Necessary for using flakes on this system
  nix.settings.experimental-features = "nix-command flakes";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Primary user for system operations
  system.primaryUser = "mohib";

  # User configuration
  users.users.mohib = {
    name = "mohib";
    home = "/Users/mohib";
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
    };

    # Keyboard settings
    # Note: Disabling Spotlight's Command+Space via symbolichotkeys requires
    # additional configuration that may need to be done manually or via
    # a custom plist activation script
  };

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";  # Uninstall packages not listed here
      autoUpdate = true;
      upgrade = true;
    };
    casks = [
      "1password-cli"
      "flycut"
      "fossa"
      "gcloud-cli"
      "karabiner-elements"
      "superwhisper"
    ];
  };

  # Used for backwards compatibility, please read the changelog before changing
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on
  nixpkgs.hostPlatform = "aarch64-darwin";
}
