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
#
# WHY gaps.outer.top IS 36 AND NOT 32 (programs/omniwm/settings.toml).
# The bar is 32pt tall, so a 32pt gap puts windows flush against it -- and
# since the stroke is centred on the window edge, exactly width/2 then paints
# INSIDE the bar. Measured at the pixel level, probing down through the bar
# into the window:
#
#   width=8  stroke 28.0 -> 32.5   4.0pt inside the bar
#   width=6  stroke 29.0 -> 32.5   3.0pt
#   width=4  stroke 30.0 -> 32.5   2.0pt
#   width=2  stroke 31.0 -> 32.5   1.0pt
#
# Intrusion is exactly width/2, so thinning the border only ever halves the
# problem -- and thins it everywhere else too. The 4pt gap moves the window
# edge to y=36 instead, and the stroke then runs 32.0 -> 36.5: it starts
# exactly at the bar's bottom edge and the 0..32 strip is pure wallpaper.
# Full width, nothing dimmed, no overlap. So the 4pt of gap is load-bearing;
# setting it back to 32 reintroduces the overlap.
#
# `order=below` does NOT fix this, which is worth recording because it is the
# intuitive fix. The bar is not in the CoreGraphics window list at all (it
# draws on a private layer above normal windows), so there is no ordering that
# puts the border behind it. What order=below actually does is render the
# stroke beneath the bar's ~93%-opaque background (COLOR_BG = 0xee1e1e2e),
# which merely dims the intruding part (197,167,242 -> ~175,149,216) rather
# than hiding it.

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
