{ config, pkgs, lib, ... }:

# JankyBorders -- coloured border on the focused window.
#
# NOT OmniWM's own [borders]: those draw entirely OUTSIDE the window frame
# (measured at width=8: window x=16 y=48 w=736 h=918, border x=8 y=40 w=752
# h=934), and the schema is only enabled/width/colour -- no inset option.
# JankyBorders straddles the edge instead: at width=8, for a window edge at
# x=756, the stroke covered 755.0 -> 759.0pt -- ~1pt outside and ~3pt over app
# content. It scales with width (see bordersWidth in darwin.nix).
#
# Do not infer placement from the border window's frame -- that container is
# 16pt outset for width=8 and looks like a pure outset border. Only the
# pixels show where the stroke lands.
#
# gaps.outer.top IS 36, NOT 32 (programs/omniwm/settings.toml), and that 4pt
# is load-bearing. The bar is 32pt tall, so a 32pt gap puts the window edge
# at the bar's edge and exactly width/2 of the stroke paints inside the bar.
# At 36 the stroke runs 32.0 -> 36.5, starting where the bar ends.
#
# order=below does NOT fix that overlap, though it is the obvious fix: the bar
# is absent from the CoreGraphics window list (private layer above normal
# windows), so no ordering hides the border behind it. It only renders the
# stroke under the bar's ~93%-opaque background, dimming it.
#
# NO LAUNCHD AGENT, on purpose -- this machine is MDM-managed and a second
# org.nixos.* plist is one more thing to audit. sketchybarrc spawns it at the
# end of its startup instead. Tradeoff: no KeepAlive, so a crash stays dead
# until the bar restarts.
#
# hidpi is OFF (sketchybarrc), and it is the difference between ~330MB and
# ~740MB resident. JankyBorders' memory is almost entirely CoreAnimation layer
# backing store -- `footprint` attributed 286MB of a 457MB total to it -- and
# hidpi doubles the backing resolution on each of the two large displays here
# (3024x1964 XDR plus a 4K). Measured twice, after forcing 30 redraws each way:
#   hidpi=off  336MB / 332MB
#   hidpi=on   755MB / 726MB
# The border is a flat 4pt rounded stroke, so the extra sample density buys
# very little; if it ever looks soft, this is the knob.
#
# NOT a memory leak, though it reads as one: RSS swings between roughly 270MB
# and 880MB and comes back down on its own (a 30s idle sample DROPPED 269MB).
# Sampling it once while it is spiking will convince you otherwise.
#
# Width and colours live in sketchybarEnv (darwin.nix), not here: both
# consumers -- the spawn and the recolour hook -- run under the sketchybar
# agent and read only that environment.

{
  home.file.".config/borders/scratchpad-color.sh" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./borders/scratchpad-color.sh;
    executable = true;
  };

  home.packages = lib.mkIf pkgs.stdenv.isDarwin [ pkgs.jankyborders ];
}
