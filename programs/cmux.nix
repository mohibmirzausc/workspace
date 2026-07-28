{ config, pkgs, lib, ... }:

# cmux — native macOS Ghostty-based terminal for running AI coding agents in
# parallel (https://github.com/manaflow-ai/cmux). Installed as a Homebrew cask
# in darwin.nix.
#
# Appearance (theme, font, colors, cursor) is NOT configured here: cmux reads
# ~/.config/ghostty/config directly, so everything from programs/ghostty.nix
# (Catppuccin Mocha theme, bell, mouse settings) carries over automatically.
#
# This file only manages cmux's own application config (~/.config/cmux/cmux.json):
# app behavior + the pane/tab keyboard shortcuts. The ghostty `super+…` binds in
# ghostty.nix were tmux/zellij escape-sequence passthroughs and are intentionally
# NOT ported — inside cmux those keys drive cmux's native tabs/panes instead,
# and cmux's defaults already match that muscle memory (cmd+t new tab, cmd+d
# split, cmd+w close, etc.). We pin them explicitly here so they're documented
# and stable across cmux default changes.

let
  cmuxConfig = {
    "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
    schemaVersion = 1;

    app = {
      appearance = "dark";          # matches the dark Catppuccin Mocha ghostty theme
      newWorkspacePlacement = "afterCurrent";
      confirmQuit = "always";
    };

    terminal = {
      autoResumeAgentSessions = true;  # bring Claude Code / Codex sessions back on relaunch
      copyOnSelect = false;
    };

    notifications = {
      dockBadge = true;
      sound = "default";
    };

    sidebar = {
      showBranchDirectory = true;
      showWorkspaceDescription = true;
    };

    # Pin the pane/tab bindings to cmux defaults (= your old ghostty super+ habits,
    # now as cmd+). Documented explicitly so they survive future default changes.
    shortcuts.bindings = {
      newTab = "cmd+t";
      closeTab = "cmd+w";
      splitRight = "cmd+d";        # split pane to the right
      splitDown = "cmd+shift+d";   # split pane downward
      nextSidebarTab = "cmd+shift+]";
      prevSidebarTab = "cmd+shift+[";
    };
  };
in
{
  home.file.".config/cmux/cmux.json".text =
    builtins.toJSON cmuxConfig;
}
