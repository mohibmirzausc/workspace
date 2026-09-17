{ config, pkgs, lib, ... }:

# Wallspace -- animated desktop wallpaper from a local video file.
# The app itself is a Homebrew cask; see homebrew.casks in darwin.nix for why
# this one rather than the open-source alternatives.
#
# THIS MODULE SELECTS THE WALLPAPER. Wallspace has no CLI, declares no document
# types, and its wallspace:// deep link only accepts gallery wallpaper IDs, so
# the only supported way to choose a local file is its
# "Select an MP4 video for personal use" picker. seed-wallpaper.py reproduces
# exactly what that picker writes, so the choice survives a fresh machine.
#
# To be clear about what this does NOT do: it is not the community upload path.
# That lives in the app's FullScreenView (SignedUploadURLService, "requesting
# signed upload URL") and is a separate, opt-in action. Nothing here touches
# the network -- the keys written are pure local state.
#
# THE VIDEO IS NOT TRACKED IN GIT. It is 13MB, and a binary that size roughly
# doubles this repo (.git is ~29MB). Drop any MP4 at the path below and the
# activation script picks it up; absent, it no-ops with a warning. Same
# reasoning that kept intake-form.png out of the tree.
#
# PERFORMANCE, measured rather than assumed. With the wallpaper genuinely
# visible through ghostty's background-opacity = 0.9, Wallspace sits at ~27%
# CPU sustained. That is NOT specific to this video: a 4K gallery wallpaper
# measured the same ~27%, so it is the cost of compositing a full-screen video
# under translucent windows on a 3024x1964 panel, not a bad encode.
#
# The app's "<2% CPU" claim holds only while the desktop is fully occluded --
# its windowDidChangeOcclusionState pause then stops rendering entirely (I
# measured 0.0-1.0% in that state). So the real tradeoff is: see the wallpaper
# OR pay ~27%, not both. autoPauseOnBatteryBelow20Percent and
# autoPauseOnLowPowerMode are the backstops on battery.

let
  videoPath = "${config.home.homeDirectory}/Pictures/Wallpapers/cozy-8bit.mp4";
in
{
  home.file.".local/bin/wallspace-seed-wallpaper" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./wallspace/seed-wallpaper.py;
    executable = true;
  };

  # Runs after linkGeneration so the script above is in place. Skips when
  # Wallspace is running -- it rewrites these keys on quit and would clobber
  # anything set underneath it.
  home.activation.seedWallspaceWallpaper = lib.mkIf pkgs.stdenv.isDarwin
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
