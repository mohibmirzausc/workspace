{ config, pkgs, lib, ... }:

# Shottr — scrolling/full-page screenshots, OCR, annotations.
#
# This is a nix-darwin module (not home-manager): it touches system.defaults
# and homebrew.casks, which only exist in the darwin module context. Imported
# from darwin.nix.
{
  homebrew.casks = [
    "shottr"  # Scrolling/full-page screenshots, OCR, annotations
  ];

  system.defaults.CustomUserPreferences = {
    # Disable the macOS screenshot shortcuts so Shottr can own ⌘⇧3 / ⌘⇧4.
    # (⌘⇧5 recording toolbar is left enabled; ⌘⇧2 isn't a macOS default.)
    # Merged with the symbolichotkeys disabled in darwin.nix.
    "com.apple.symbolichotkeys" = {
      AppleSymbolicHotKeys = {
        "28" = { enabled = false; };  # Save full screen as file (⌘⇧3)
        "29" = { enabled = false; };  # Copy full screen to clipboard (⌃⌘⇧3)
        "30" = { enabled = false; };  # Save selected area as file (⌘⇧4)
        "31" = { enabled = false; };  # Copy selected area to clipboard (⌃⌘⇧4)
      };
    };

    # Shottr capture hotkeys. Values are the KeyboardShortcuts library's carbon
    # encoding: carbonModifiers 768 = ⌘⇧, 6400 = ⌃⌥⌘. Carbon key codes:
    # 19=2, 20=3, 21=4, 31=O.
    "cc.ffitch.shottr" = {
      "KeyboardShortcuts_fullscreen" = ''{"carbonKeyCode":20,"carbonModifiers":768}'';  # ⌘⇧3
      "KeyboardShortcuts_area" = ''{"carbonKeyCode":21,"carbonModifiers":768}'';         # ⌘⇧4
      "KeyboardShortcuts_scrolling" = ''{"carbonKeyCode":19,"carbonModifiers":768}'';    # ⌘⇧2
      "KeyboardShortcuts_ocr" = ''{"carbonKeyCode":31,"carbonModifiers":6400}'';         # ⌃⌥⌘O
    };
  };
}
