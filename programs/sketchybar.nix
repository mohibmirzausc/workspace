{ config, pkgs, lib, ... }:

# SketchyBar -- customizable macOS status bar replacement
# (https://github.com/FelixKratz/SketchyBar).
#
# The BINARY is installed via Homebrew from the upstream felixkratz/formulae
# tap (see homebrew.taps/brews in darwin.nix), not from nixpkgs -- nixpkgs
# carries sketchybar but lags upstream releases. This module owns the config.
#
# CONFIG PROVENANCE: sketchybar/{sketchybarrc,bridge.sh,plugins} are vendored
# from
#   https://github.com/chunkanglu/nix-config/tree/main/programs/window-manager/sketchybar
# and adapted for this machine. Upstream drives one bar config from any of four
# window managers; only the OmniWM path is exercised here.
#
# The design is a bridge plus a WM-agnostic bar. bridge.sh reads OmniWM's event
# stream and normalizes it onto three sketchybar events, so sketchybarrc never
# has to know which window manager is running:
#
#   wm_workspace_changed   WM_BACKEND WM_WORKSPACE
#   wm_windows_changed     WM_BACKEND WM_WORKSPACE WM_WINDOW_COUNT
#   wm_focus_changed       WM_BACKEND WM_WORKSPACE WM_APP WM_TITLE
#
# REQUIRES OMNIWM IPC. bridge.sh runs `omniwmctl subscribe workspace-bar`,
# which needs the socket at ~/Library/Caches/com.barut.OmniWM/ipc.sock. On
# OmniWM 0.6.10 `general.ipcEnabled = true` in settings.toml is NOT sufficient
# on its own -- "Enable IPC" must also be clicked once from the OmniWM menu bar
# icon. That gate cannot be automated from nix, same class as the Accessibility
# grant. Without it the bridge no-ops and the WM items stay blank.
#
# Upstream subscribes to `workspace-bar` rather than the more obvious channels,
# and that reasoning was re-verified against this machine:
#   * windows-changed reports EVERY managed window, including ones with
#     hiddenReason = "workspace-inactive", so its length is the global window
#     count rather than what is on screen.
#   * the focus channel delivers an empty payload {}.
# workspace-bar is the projection OmniWM's own bar renders, scoped to the
# interaction monitor, so a single event carries workspace + count + focus.
#
# LOCAL ADAPTATIONS (upstream assumes helper commands from its own repo):
#   * 4 workspace pills, not 6 -- matches [[workspaces]] in
#     omniwm/settings.toml. The left_group bracket was trimmed to match, since
#     naming a nonexistent space.5/space.6 item breaks the bracket.
#   * workspace click: `wm-goto-workspace N` -> `omniwmctl command
#     switch-workspace N`.
#   * plugins/wm_backend.sh: `wm-keys-open` -> OmniWM's command palette, and
#     the `wm status` label fallback -> the literal "omniwm".
#
# FONT: the icons are Nerd Font glyphs, so nerd-fonts.jetbrains-mono is
# installed in darwin.nix and WM_BAR_FONT points at it. Without it they render
# as tofu boxes; sketchybarrc itself falls back to Menlo when unset.

let
  # Every plugin shells out to sketchybar, and several to jq / omniwmctl.
  # launchd hands the daemon PATH=/usr/bin:/bin:/usr/sbin:/sbin, and item
  # scripts are spawned BY that daemon, so they inherit the same minimal PATH.
  # Without this the bar draws correctly but every label renders empty -- a
  # deceptive failure mode that already cost one debugging round here. Set on
  # the launchd agent so sketchybarrc and all plugins inherit it.
  barPath = "/opt/homebrew/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  # Catppuccin Mocha, matching the ghostty theme in programs/ghostty.nix.
  # Plugins inherit sketchybar's environment but NOT shell variables exported
  # inside sketchybarrc, so the palette has to live on the agent to be the one
  # source of truth for both.
  barEnv = {
    PATH = barPath;
    WM_BACKEND = "omniwm";
    WM_BAR_FONT = "DepartureMono Nerd Font";
    # Regular-only family; see the note in darwin.nix's sketchybarEnv.
    WM_BAR_FONT_BOLD = "Regular";
    COLOR_BG = "0xee1e1e2e";
    COLOR_FG = "0xffcdd6f4";
    COLOR_DIM = "0xff7f849c";
    COLOR_ACCENT = "0xffcba6f7";
    COLOR_ON_ACCENT = "0xff1e1e2e";
    COLOR_ITEM_BG = "0x40313244";
    COLOR_POPUP_BG = "0xf0181825";
    COLOR_POPUP_BORDER = "0xff45475a";
    COLOR_BLUE = "0xff89b4fa";
    COLOR_FLAMINGO = "0xfff2cdcd";
    COLOR_PEACH = "0xfffab387";
    COLOR_TEAL = "0xff94e2d5";
    COLOR_SAPPHIRE = "0xff74c7ec";
    COLOR_LAVENDER = "0xffb4befe";
    COLOR_RED = "0xfff38ba8";
    # Battery state colours (battery.sh): green charging, then a
    # yellow -> peach -> red ramp as the charge falls.
    COLOR_GREEN = "0xffa6e3a1";
    COLOR_YELLOW = "0xfff9e2af";
  };
in
{
  # sketchybarrc is exec'd directly by sketchybar, so it must be executable.
  home.file.".config/sketchybar/sketchybarrc" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./sketchybar/sketchybarrc;
    executable = true;
  };

  # Run by its own launchd agent; see launchd.user.agents.sketchybar-bridge.
  home.file.".config/sketchybar/bridge.sh" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./sketchybar/bridge.sh;
    executable = true;
  };

  # sketchybarrc resolves these as "$CONFIG_DIR/plugins/<name>.sh" and execs
  # each one. `recursive` links the files individually rather than symlinking
  # the directory, which is what lets executable bits apply per file.
  home.file.".config/sketchybar/plugins" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./sketchybar/plugins;
    recursive = true;
    executable = true;
  };

  # Source for the window-titles helper (see the activation script below).
  home.file.".config/sketchybar/helpers/window-titles.swift" =
    lib.mkIf pkgs.stdenv.isDarwin { source = ./sketchybar/helpers/window-titles.swift; };

  # Compile the helper with the HOST Swift toolchain rather than nixpkgs'.
  #
  # It links CoreGraphics and wants the machine's own SDK; nixpkgs' swift
  # wrapper fails outright here ("NIX_CC: unbound variable" from its
  # setup-hook under stdenvNoCC). Building against the installed Xcode CLT
  # also keeps it matched to the OS whose window server it queries.
  #
  # Rebuilt only when the source is newer than the binary, so ordinary
  # rebuilds stay fast. A missing binary is non-fatal -- wm_window_list.sh
  # falls back to OmniWM's (stale) titles.
  home.activation.buildSketchybarHelpers = lib.mkIf pkgs.stdenv.isDarwin
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      HELPER_DIR="$HOME/.config/sketchybar/helpers"
      SRC="$HELPER_DIR/window-titles.swift"
      BIN="$HELPER_DIR/window-titles"
      if [ -f "$SRC" ] && [ -x /usr/bin/swiftc ]; then
        if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
          $DRY_RUN_CMD /usr/bin/swiftc -O -o "$BIN.tmp" "$SRC" 2>/dev/null \
            && $DRY_RUN_CMD mv "$BIN.tmp" "$BIN" \
            || echo "warning: could not build window-titles helper; bar will use OmniWM titles"
        fi
      fi
    '');

  # So running a plugin or `sketchybar --reload` by hand from a login shell
  # picks the same font as the agent.
  home.sessionVariables = lib.mkIf pkgs.stdenv.isDarwin {
    WM_BAR_FONT = barEnv.WM_BAR_FONT;
    WM_BAR_FONT_BOLD = barEnv.WM_BAR_FONT_BOLD;
  };
}
