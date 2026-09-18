{ config, pkgs, lib, ... }:

# JankyBorders -- a coloured border on the focused window.
#
# WHY NOT OMNIWM'S OWN BORDERS. OmniWM has [borders] in settings.toml, but it
# draws the stroke ENTIRELY OUTSIDE the window frame, in the inter-window gap.
# Measured with a border width of 8: the app window sat at x=16 y=48 w=736
# h=918 and OmniWM's border window at x=8 y=40 w=752 h=934 -- exactly 8pt out
# on every side. Its whole schema is `enabled`, `width` and a colour; there is
# no inset or placement option, so an on-the-window border is not reachable
# from there.
#
# JankyBorders straddles the edge instead. Measured at the pixel level (2x
# Retina screencapture, decoded and scanned for the accent colour): for a
# window whose left edge is at x=756, the stroke covered 755.0 -> 759.0pt.
# So ~1pt sits outside and ~3pt over the app's own content -- a border ON the
# window rather than around it, which is the intent here.
#
# Do not infer placement from the border window's frame: that container is
# reported 16pt outset for width=8 (it is padded to hold the stroke plus its
# rounding), which looks like a pure outset border and is misleading. Only the
# pixels tell you where the stroke lands.
#
# Same author as SketchyBar, and it reads focus from the window server
# directly, so it needs no OmniWM integration and does not interact with the
# event bridge.

{
  # The recolour hook, invoked by sketchybar on wm_focus_changed.
  home.file.".config/borders/scratchpad-color.sh" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./borders/scratchpad-color.sh;
    executable = true;
  };

  home.packages = lib.mkIf pkgs.stdenv.isDarwin [ pkgs.jankyborders ];

  # WHERE THE REST OF THIS LIVES: darwin.nix, not here. The launchd agent is
  # launchd.user.agents.borders, and the width/colour values are in
  # sketchybarEnv next to it. Two reasons they are not in this file:
  #
  #   1. home-manager's launchd.agents option produced no plist in this setup
  #      -- every agent on this machine is an org.nixos.* one from nix-darwin
  #      -- so the agent is defined alongside sketchybar's.
  #   2. The recolour hook runs as a sketchybar child and inherits only that
  #      agent's environment, so the colours have to be in sketchybarEnv
  #      anyway. Defining them here too would be two sources of truth for one
  #      colour.
  #
  # This module therefore owns the package and the hook; darwin.nix owns the
  # agent and the values.
}
