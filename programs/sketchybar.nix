{ config, pkgs, lib, ... }:

# SketchyBar -- customizable macOS status bar replacement
# (https://github.com/FelixKratz/SketchyBar).
#
# The BINARY is installed via Homebrew from the upstream felixkratz/formulae
# tap (see homebrew.taps/brews in darwin.nix), not from nixpkgs -- nixpkgs
# carries sketchybar but lags upstream releases. This module owns only the
# config file. The launchd agent that runs it lives in darwin.nix.
#
# Coexistence with OmniWM: OmniWM's own workspaceBar is also enabled and also
# sits at `position = "overlappingMenuBar"`, but it is a REVEAL bar -- with
# revealHoldMilliseconds = 0 it appears only while the super key (Caps Lock) is
# held, then hides again. So the two do not fight over that strip in normal use,
# and OmniWM's bar is deliberately left enabled.
#
# This is a starting config, not a finished bar: a left-side space/app-name
# readout and a right-side clock + battery. SketchyBar's whole value is the
# custom scripting, so this exists to get a working bar on screen that can then
# be grown. Everything here is plain `sketchybar --<cmd>` calls, so it can be
# extended incrementally.
#
# NOT wired to OmniWM workspaces yet. Doing that properly needs OmniWM's IPC,
# which is currently off (general.ipcEnabled = false in
# programs/omniwm/settings.toml). Once enabled, `omniwmctl subscribe
# workspace-bar,active-workspace` + `omniwmctl query workspaces` can feed a
# workspace indicator here -- that is the natural next step.

let
  # The config is a shell script SketchyBar executes on startup. It must be
  # executable, so it is installed via home.file with executable = true rather
  # than written as plain text.
  sketchybarrc = pkgs.writeShellScript "sketchybarrc" ''
    # sketchybar itself comes from Homebrew (felixkratz/formulae, declared in
    # darwin.nix) rather than nixpkgs, for faster release cadence -- so its
    # bin dir is prepended explicitly instead of via a nix store path.
    export PATH="/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:$PATH"

    # ---- bar ----------------------------------------------------------------
    # Catppuccin Mocha base (#1e1e2e) at ~90% alpha, matching the ghostty theme
    # in programs/ghostty.nix. SketchyBar colors are 0xAARRGGBB.
    sketchybar --bar \
      height=32 \
      position=top \
      padding_left=8 \
      padding_right=8 \
      color=0xe61e1e2e \
      corner_radius=8 \
      y_offset=4 \
      margin=8 \
      blur_radius=20

    # ---- defaults applied to every item ------------------------------------
    sketchybar --default \
      icon.font="SF Pro:Semibold:14.0" \
      icon.color=0xffcdd6f4 \
      label.font="SF Pro:Semibold:13.0" \
      label.color=0xffcdd6f4 \
      padding_left=5 \
      padding_right=5 \
      icon.padding_left=6 \
      icon.padding_right=3 \
      label.padding_left=3 \
      label.padding_right=6

    # ---- left: focused application -----------------------------------------
    # front_app_switched is a built-in SketchyBar event; no polling needed.
    sketchybar --add item front_app left \
               --set front_app \
                     icon=󰀽 \
                     label.font="SF Pro:Bold:13.0" \
                     script="/opt/homebrew/bin/sketchybar --set front_app label=\"\$INFO\"" \
               --subscribe front_app front_app_switched

    # ---- right: clock ------------------------------------------------------
    sketchybar --add item clock right \
               --set clock \
                     update_freq=10 \
                     icon= \
                     script="/opt/homebrew/bin/sketchybar --set clock label=\"\$(/bin/date '+%a %d %b  %H:%M')\""

    # ---- right: battery ----------------------------------------------------
    # Driven by the system power event plus a slow poll, so it updates on
    # plug/unplug without burning CPU on a tight timer.
    sketchybar --add item battery right \
               --set battery \
                     update_freq=120 \
                     script="
                       export PATH=/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin
                       PCT=\$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
                       CHARGING=\$(pmset -g batt | grep -c 'AC Power')
                       [ -z \"\$PCT\" ] && exit 0
                       if [ \"\$CHARGING\" -gt 0 ]; then ICON=; \
                       elif [ \"\$PCT\" -gt 80 ]; then ICON=; \
                       elif [ \"\$PCT\" -gt 50 ]; then ICON=; \
                       elif [ \"\$PCT\" -gt 20 ]; then ICON=; \
                       else ICON=; fi
                       sketchybar --set battery icon=\"\$ICON\" label=\"\$PCT%\"
                     " \
               --subscribe battery power_source_change system_woke

    # Render everything at once rather than item-by-item.
    sketchybar --update
  '';
in
{
  # No home.packages entry: the sketchybar binary is installed by Homebrew
  # (see homebrew.brews in darwin.nix), not by nix. This module only owns the
  # config file.
  home.file.".config/sketchybar/sketchybarrc" = lib.mkIf pkgs.stdenv.isDarwin {
    source = sketchybarrc;
    executable = true;
  };
}
