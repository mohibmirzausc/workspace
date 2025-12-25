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
      
      # Keybindings (can be customized)
      # keybind = ctrl+shift+c=copy_to_clipboard
      # keybind = ctrl+shift+v=paste_from_clipboard
      # keybind = ctrl+shift+n=new_window
      # keybind = ctrl+shift+t=new_tab
      # keybind = ctrl+shift+w=close_surface
      # keybind = ctrl+shift+equal=increase_font_size:1
      # keybind = ctrl+shift+minus=decrease_font_size:1
      # keybind = ctrl+shift+zero=reset_font_size
      
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

