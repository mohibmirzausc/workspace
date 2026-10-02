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
  # Where a waiting session is: see programs/cmux/attention.py. The same
  # command is the notification hook below and the cmux-attention launchd
  # agent in darwin.nix, which feeds the sketchybar indicator. A store path,
  # not a ~/.config link, for the reason in programs/cmux/default.nix.
  attentionPkg = pkgs.callPackage ./cmux { };
  attention = "${attentionPkg}/bin/cmux-attention";

  cmuxConfig = {
    "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
    schemaVersion = 1;

    app = {
      appearance = "dark";          # matches the dark Catppuccin Mocha ghostty theme
      appIcon = "dark";
      newWorkspacePlacement = "end";
      confirmQuit = "always";
      globalFontMagnification = 190;
      workspaceInheritWorkingDirectory = true;
      reorderOnNotification = false;   # don't shuffle the sidebar when a workspace pings
      sendAnonymousTelemetry = false;
      iMessageMode = false;

      # Keep cmux a regular app: Dock icon, app switcher entry, and its own menu
      # bar. Turning this on sets an .accessory activation policy, which means
      # macOS gives cmux no menu bar at all -- so even when a cmux window is
      # frontmost the menus belong to whatever regular app is behind it (for us,
      # the standalone Ghostty), which reads as "cmux vanished from the top bar".
      # Pinned false because it's a one-click toggle in cmux's own settings UI
      # and the flag is easy to flip by accident.
      menuBarOnly = false;
    };

    terminal = {
      autoResumeAgentSessions = true;  # bring Claude Code / Codex sessions back on relaunch
      copyOnSelect = true;
      scrollSpeed = 1.15;
    };

    notifications = {
      dockBadge = true;
      sound = "Funk";

      # Put the OmniWM location in front of every notification's subtitle:
      #   "Completed in dotfiles" -> "Caps+F1 dotfiles · Completed in dotfiles"
      # so a banner says which Caps chord reaches the session. The hook gets
      # the policy JSON on stdin and prints it back. A hook that fails, times
      # out or prints bad JSON makes cmux fall back to the default AND post a
      # failure alert, so attention.py echoes its input unchanged on every
      # error and gives up by itself after 1s -- well inside this timeout. It
      # typically takes ~70ms (a state-file read plus two OmniWM queries).
      hooks = [
        {
          id = "omniwm-location";
          command = "${attention} hook";
          timeoutSeconds = 3;
        }
      ];
    };

    sidebar = {
      showBranchDirectory = true;
      showWorkspaceDescription = true;
      branchLayout = "vertical";
      watchGitStatus = true;
      wrapWorkspaceTitles = false;
      hideAllDetails = false;
      notificationMessageLineLimit = 12;
      beta.workspaceTodos.checklistStyle = "popover";
    };

    # Sidebar chrome picks up the ghostty terminal background (Catppuccin Mocha
    # #1e1e2e) instead of the system window color, so the two don't clash.
    sidebarAppearance.matchTerminalBackground = true;

    automation = {
      workspaceAutoNaming = true;

      # Let processes that cmux did not start use its socket. The default,
      # cmuxOnly, admits only cmux's own descendants; run from a launchd job
      # every command fails with "Access denied - only processes started
      # inside cmux can connect" (checked with `launchctl submit`). Three
      # things live outside cmux and need it: the cmux-attention agent
      # (`cmux events`, `tree`, `list-notifications`), the sketchybar
      # indicator's click, and the Caps+U chord in Karabiner (both
      # `cmux jump-to-unread`).
      #
      # "automation" is cmux's mode for this: "Allow external local
      # automation clients from this macOS user (no ancestry check)". Other
      # users still cannot connect. What it gives up is ancestry as a gate
      # between this user's own processes, and anything running as me can
      # already type into my terminals, so that gate protected little. The
      # stricter "password" mode would need the password on disk, where the
      # same processes could read it.
      socketControlMode = "automation";
    };

    canvas.paneGap = 20;

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

  # On PATH for hand runs: `cmux-attention snapshot`.
  home.packages = [ attentionPkg ];
}
