{ config, pkgs, lib, ... }:

# Hammerspoon -- currently doing exactly one job: Caps Lock+H leaves the
# current call (Tandem, Tuple or Google Meet).
#
# Why a whole new tool for one hotkey. Neither Tandem nor Tuple is
# AppleScript-scriptable and neither exposes a leave/end-call menu item, so the
# only way to end a call short of quitting the app is to press its leave button
# through the Accessibility API. That is hs.axuielement. The alternative --
# driving the same API from a standalone script -- works (it was how this was
# first proven) but costs ~60 lines of ctypes boilerplate against ~15 lines of
# Lua, and re-pays process startup on every press.
#
# Verified on a live Tandem call: the control is a real AXButton titled
# "Leave Room" with AXPress on it; pressing it left the call and Tandem stayed
# running. Tuple's in-call overlay has NOT been tested -- it exposes no AX
# window while idle, so its titles in programs/hammerspoon/init.lua are
# guesses until someone runs this during a Tuple call.
#
# AppleScript is useless here and misleadingly so: `entire contents` returns
# zero elements for every Chromium-backed app, including Chrome itself. An
# empty result from it means the tool failed, not that the tree is empty.
#
# Cask, not nixpkgs -- Hammerspoon is not packaged there. It is
# `auto_updates`, so the version is not pinned by this config.
#
# Needs Accessibility (granted once, in System Settings; it survives
# rebuilds). Nothing else -- no Screen Recording, no Input Monitoring.
#
# NO LAUNCHD AGENT, matching programs/borders.nix: this machine is
# MDM-managed. Hammerspoon's own "Launch at login" preference handles
# persistence, which is one fewer org.nixos.* plist to audit.

{
  home.file.".hammerspoon/init.lua" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./hammerspoon/init.lua;
  };

  # Diagnostic, expected to be removed once the culprit is known: HUDs every
  # microphone input-volume change. Something lowers it over time (seen at 36%
  # then 10% in one session) and darwin.nix already notes that Krisp, Zoom,
  # Tandem and Tuple all do it without restoring.
  home.file.".hammerspoon/mic-volume-hud.lua" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./hammerspoon/mic-volume-hud.lua;
  };
}
