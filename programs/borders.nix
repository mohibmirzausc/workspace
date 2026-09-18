{ config, pkgs, lib, ... }:

# JankyBorders -- coloured border on the focused window.
#
# NOT OmniWM's own [borders]: those draw entirely OUTSIDE the window frame
# (measured at width=8: window x=16 y=48 w=736 h=918, border x=8 y=40 w=752
# h=934), and the schema is only enabled/width/colour -- no inset option.
# JankyBorders straddles the edge instead: for a window edge at x=756 the
# stroke covered 755.0 -> 759.0pt, so ~1pt outside and ~3pt over app content.
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
