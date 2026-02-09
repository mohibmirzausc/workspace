{ config, pkgs, lib, ... }:

{
  # Ghostty terminal emulator configuration
  home.file.".config/ghostty/config" = {
    text = ''
      # Bell configuration
      bell-features = system,attention,title

      # macOS app icon (dock/app switcher)
      macos-icon = xray

      # Theme and appearance
      theme = dark:Catppuccin Mocha,light:Catppuccin Mocha 
      
      # Font configuration
      # font-family = "JetBrains Mono"
      # font-size = 13
      # font-thicken = true
      
      # Window settings
      # window-padding-x = 8
      # window-padding-y = 8
      # window-decoration = true
      # window-theme = auto
      
      # Performance
      # shell-integration = detect
      # shell-integration-features = cursor,sudo,title
      
      # Cursor
      # cursor-style = block
      # cursor-style-blink = true
      
      # Scrollback
      # scrollback-limit = 10000
      
      # Mouse
      # mouse-hide-while-typing = true
      # copy-on-select = clipboard
      
      # Clipboard
      # clipboard-read = allow
      # clipboard-write = allow
      # clipboard-paste-protection = false

      # Unbind keys that Zellij uses (so Zellij can intercept them)
      # These won't work in Ghostty when not using Zellij
      keybind = super+t=unbind
      keybind = super+w=unbind
      keybind = super+d=unbind
      keybind = super+shift+d=unbind
      keybind = super+left_bracket=unbind
      keybind = super+right_bracket=unbind
      keybind = super+shift+enter=unbind
      keybind = super+k=unbind
      keybind = super+f=unbind
      keybind = super+p=unbind
      keybind = super+r=unbind
      keybind = super+s=unbind
      keybind = super+shift+c=unbind
      keybind = super+shift+s=unbind
      keybind = super+1=unbind
      keybind = super+2=unbind
      keybind = super+3=unbind
      keybind = super+4=unbind
      keybind = super+5=unbind
      keybind = super+6=unbind
      keybind = super+7=unbind
      keybind = super+8=unbind
      keybind = super+9=unbind

      # Tab bar
      # window-step-resize = true
      
      # Background
      # background-opacity = 1.0
      # unfocused-split-opacity = 0.8
      
      # Advanced
      # confirm-close-surface = false
      # quit-after-last-window-closed = false
    '';
  };
}

