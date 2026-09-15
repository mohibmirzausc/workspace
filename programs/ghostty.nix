{ config, pkgs, lib, ... }:

let
  homeDir = config.home.homeDirectory;
  configDir = "${homeDir}/.config/ghostty";

  sharedConfig = ''
    bell-features = system,attention,title
    theme = dark:Catppuccin Mocha,light:Catppuccin Mocha
    mouse-scroll-multiplier = precision:1,discrete:1
  '';

  tmuxKeybinds = ''
    keybind = super+t=text:\x00t
    keybind = super+w=text:\x00w
    keybind = super+one=text:\x001
    keybind = super+two=text:\x002
    keybind = super+three=text:\x003
    keybind = super+four=text:\x004
    keybind = super+five=text:\x005
    keybind = super+six=text:\x006
    keybind = super+seven=text:\x007
    keybind = super+eight=text:\x008
    keybind = super+nine=text:\x009
    keybind = super+shift+left_bracket=text:\x00{
    keybind = super+shift+right_bracket=text:\x00}
    keybind = super+e=text:\x00e
    keybind = super+d=text:\x00d
    keybind = super+shift+d=text:\x00D
    keybind = super+left_bracket=text:\x00[
    keybind = super+right_bracket=text:\x00]
    keybind = super+shift+enter=text:\x00\x0d
    keybind = super+shift+b=text:\x00B
    keybind = super+shift+j=text:\x00J
    keybind = super+shift+f=text:\x00F
    keybind = super+p=text:\x00p
    keybind = super+r=text:\x00r
    keybind = super+k=text:\x00k
    keybind = super+f=text:\x00f
    keybind = super+shift+c=text:\x00C
    keybind = super+s=text:\x00s
    keybind = super+shift+s=text:\x00S
    keybind = super+q=text:\x00q
  '';

  zellijKeybinds = ''
    keybind = super+t=unbind
    keybind = super+w=unbind
    keybind = super+d=unbind
    keybind = super+shift+d=unbind
    keybind = super+left_bracket=unbind
    keybind = super+right_bracket=unbind
    keybind = super+shift+left_bracket=unbind
    keybind = super+shift+right_bracket=unbind
    keybind = super+alt+left_bracket=unbind
    keybind = super+alt+right_bracket=unbind
    keybind = super+shift+enter=unbind
    keybind = super+k=unbind
    keybind = super+f=unbind
    keybind = super+shift+f=unbind
    keybind = super+shift+b=unbind
    keybind = super+e=unbind
    keybind = super+p=unbind
    keybind = super+r=unbind
    keybind = super+s=unbind
    keybind = super+shift+c=unbind
    keybind = super+shift+s=unbind
    keybind = super+shift+left=unbind
    keybind = super+shift+right=unbind
    keybind = super+shift+up=unbind
    keybind = super+shift+down=unbind
    keybind = super+one=unbind
    keybind = super+two=unbind
    keybind = super+three=unbind
    keybind = super+four=unbind
    keybind = super+five=unbind
    keybind = super+six=unbind
    keybind = super+seven=unbind
    keybind = super+eight=unbind
    keybind = super+nine=unbind
  '';
in
{
  # Default Ghostty config (loads swappable keybinds)
  home.file.".config/ghostty/config" = {
    text = sharedConfig + ''
      macos-icon = xray
      config-file = ?${configDir}/keys.conf
    '';
  };

  # Standalone config for tmux instance (blue icon)
  home.file.".config/ghostty/config-tmux" = {
    text = sharedConfig + ''
      macos-icon = custom-style
      macos-icon-ghost-color = #89b4fa
      macos-icon-screen-color = #1e1e2e
      macos-icon-frame = chrome
      title = Ghostty (tmux)
    '' + tmuxKeybinds;
  };

  # Standalone config for zellij instance (green icon)
  home.file.".config/ghostty/config-zellij" = {
    text = sharedConfig + ''
      macos-icon = custom-style
      macos-icon-ghost-color = #a6e3a1
      macos-icon-screen-color = #1e1e2e
      macos-icon-frame = chrome
      title = Ghostty (zellij)
    '' + zellijKeybinds;
  };

  # Keybind files for the switcher approach
  home.file.".config/ghostty/keys-tmux.conf".text = tmuxKeybinds;
  home.file.".config/ghostty/keys-zellij.conf".text = zellijKeybinds;

  # Default to tmux keybinds if keys.conf doesn't exist
  home.activation.ghosttyKeys = lib.hm.dag.entryAfter ["writeBoundary"] ''
    KEYS="$HOME/.config/ghostty/keys.conf"
    mkdir -p "$HOME/.config/ghostty"
    if [ ! -e "$KEYS" ]; then
      ln -sf keys-tmux.conf "$KEYS"
    fi
  '';
}
