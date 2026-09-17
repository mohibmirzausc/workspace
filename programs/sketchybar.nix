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
  # NOTE: this module does NOT own the bar's environment.
  #
  # The launchd agents live in nix-darwin (launchd.user.agents.sketchybar in
  # darwin.nix), and the agent's EnvironmentVariables is what sketchybarrc and
  # every plugin actually inherit -- plugins are spawned by the daemon. So the
  # PATH and the full Catppuccin palette are defined once, in darwin.nix's
  # sketchybarEnv, and are deliberately not duplicated here.
  #
  # A previous version of this file carried its own copy of all 17 COLOR_*
  # values. They were never read by anything: only the two font values below
  # were referenced (via home.sessionVariables). Two identical palettes with
  # one of them inert is a quiet trap -- edit the dead copy, rebuild, and
  # nothing changes with no indication why. They had not diverged yet.
  #
  # The COLOR_X:-default fallbacks inside sketchybarrc and the plugins are
  # a third copy, but an intentional one: they keep a plugin looking right
  # when run by hand from a shell, outside the agent environment.
  barFont = {
    WM_BAR_FONT = "DepartureMono Nerd Font";
    # Regular-only family; see the note in darwin.nix's sketchybarEnv.
    WM_BAR_FONT_BOLD = "Regular";
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
      STAMP="$HELPER_DIR/.window-titles.sha"
      if [ -f "$SRC" ] && [ -x /usr/bin/swiftc ]; then
        # Rebuild on CONTENT change, not mtime.
        #
        # `[ "$SRC" -nt "$BIN" ]` looks right but never fires: $SRC is a
        # nix-store symlink, `-nt` dereferences it, and nix pins every store
        # file's mtime to epoch 1. So the source is permanently "older" than
        # any binary and an edited .swift would silently never recompile --
        # activation prints nothing and exits 0, so the diff looks deployed
        # while the old binary keeps running.
        NEW_SHA="$(/usr/bin/shasum -a 256 "$SRC" | cut -d' ' -f1)"
        OLD_SHA=""
        [ -f "$STAMP" ] && OLD_SHA="$(cat "$STAMP")"
        if [ ! -x "$BIN" ] || [ "$NEW_SHA" != "$OLD_SHA" ]; then
          if $DRY_RUN_CMD /usr/bin/swiftc -O -o "$BIN.tmp" "$SRC" 2>/dev/null \
             && $DRY_RUN_CMD mv "$BIN.tmp" "$BIN"; then
            [ -z "$DRY_RUN_CMD" ] && printf '%s\n' "$NEW_SHA" > "$STAMP"
          else
            $DRY_RUN_CMD rm -f "$BIN.tmp"
            echo "warning: could not build window-titles helper; bar will use OmniWM titles"
          fi
        fi
      fi
    '');

  # So running a plugin or `sketchybar --reload` by hand from a login shell
  # picks the same font as the agent.
  home.sessionVariables = lib.mkIf pkgs.stdenv.isDarwin {
    WM_BAR_FONT = barFont.WM_BAR_FONT;
    WM_BAR_FONT_BOLD = barFont.WM_BAR_FONT_BOLD;
  };
}
