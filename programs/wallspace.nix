{ config, pkgs, lib, features, ... }:

# Wallspace -- animated desktop wallpaper from a local video. The app is a
# Homebrew cask; see homebrew.casks in darwin.nix for why this one.
#
# GATED ON features.wallspace (set in flake.nix, currently FALSE). When off,
# this module contributes nothing and the cask is not declared -- which means
# homebrew.onActivation.cleanup = "uninstall" removes the app on rebuild.
# Everything below is additionally guarded on isDarwin as before.
#
# THIS MODULE SELECTS THE WALLPAPER. Wallspace has no CLI and its wallspace://
# deep link only accepts gallery IDs, so the only supported way to pick a
# local file is its MP4 picker. seed-wallpaper.py writes exactly what that
# picker writes, so the choice survives a fresh machine. It is NOT the
# community upload path (that is a separate opt-in action) and touches no
# network -- the keys written are local state.
#
# THE VIDEO IS NOT TRACKED IN GIT: 13MB roughly doubles this repo. Drop any
# MP4 at the path below; absent, activation no-ops with a warning.
#
# PERFORMANCE, measured from cumulative CPU-time deltas -- NOT `ps %cpu`,
# a lifetime average that reads 20-40% during startup:
#
#   60fps 6.2%   30fps 4.7%   15fps 4.3%   30fps at 2x slower 4.3%
#
# ~4% is a floor the agent costs regardless, so the video is ~2.2% at 60fps
# and ~0.7% at 30fps. Hence stored at 30fps; halving again buys nothing.
#
# FRAME RATE is the only input that matters. Speed does not (the compositor
# still redraws per frame). Duration does not (a loop decodes one frame at a
# time). Resolution barely does -- decode runs on the media engine, so a 4K
# gallery wallpaper measured the same as this 1080p one.
#
# When measuring, close Wallspace's settings window first: it renders a live
# preview, which is what produced an earlier bogus ~27% reading.

let
  videoPath = "${config.home.homeDirectory}/Pictures/Wallpapers/cozy-8bit.mp4";
in
{
  home.file.".local/bin/wallspace-seed-wallpaper" = lib.mkIf (features.wallspace && pkgs.stdenv.isDarwin) {
    source = ./wallspace/seed-wallpaper.py;
    executable = true;
  };

  # Power-saving toggles. Automatic pausing is the reason this app was chosen
  # over the DIY options, so it should not depend on remembering to tick them.
  #
  # Not `targets.darwin.defaults`: this domain also holds the wallpaper
  # selection, which the app rewrites on quit, so only these keys are pinned.
  home.activation.wallspaceSettings = lib.mkIf (features.wallspace && pkgs.stdenv.isDarwin)
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      # One long line on purpose: in a Nix indented string a backslash is
      # literal, so a line-continuation would reach bash and break the loop.
      for KEY in wallpaperAutoPauseOnLowPowerMode wallpaperAutoPauseOnBatteryBelow20Percent wallpaperAutoPauseOnFullscreen startOnLoginEnabled autoStartWallpaperEngine; do
        $DRY_RUN_CMD /usr/bin/defaults write wallspace.app "$KEY" -bool true
      done
    '');

  # Runs after linkGeneration so the script above is in place. Skips when
  # Wallspace is running -- it rewrites these keys on quit and would clobber
  # anything set underneath it.
  home.activation.seedWallspaceWallpaper = lib.mkIf (features.wallspace && pkgs.stdenv.isDarwin)
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      SEED="$HOME/.local/bin/wallspace-seed-wallpaper"
      VIDEO="${videoPath}"
      if [ -x "$SEED" ] && [ -f "$VIDEO" ]; then
        $DRY_RUN_CMD /usr/bin/python3 "$SEED" "$VIDEO" || \
          echo "warning: could not seed the Wallspace wallpaper"
      elif [ ! -f "$VIDEO" ]; then
        echo "note: no wallpaper video at $VIDEO -- skipping Wallspace seed"
      fi
    '');
}
