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
# PERFORMANCE, measured with the wallpaper genuinely visible through
# ghostty's background-opacity = 0.9. Sampled from cumulative CPU-time deltas,
# not `ps %cpu` (a lifetime average that reads 20-40% during startup):
#
#   60fps  6.2%     <- the file as downloaded
#   30fps  4.7%
#   15fps  4.3%
#   30fps at 2x slower playback  4.3%   (same as normal-speed 30fps)
#
# Roughly 4% of that is a floor the agent costs regardless, so the video
# itself is ~2.2% at 60fps and ~0.7% at 30fps. Halving 60 -> 30 is worth it;
# halving again buys almost nothing, so the file is stored at 30fps.
#
# FRAME RATE is the only input that matters. Playback SPEED does not (slowing
# 2x measured identically -- the compositor still redraws per frame, it just
# advances the video half as fast). DURATION does not either: a loop decodes
# one frame at a time regardless of length, so longer only costs disk.
# RESOLUTION barely does: a 4K gallery wallpaper measured the same as this
# 1080p one, because decode runs on the M4 media engine rather than the CPU.
#
# An earlier note here claimed ~27%. That was wrong -- it was measuring
# Wallspace's own settings WINDOW, which renders a live preview of the
# wallpaper. With that window closed the cost is what is tabulated above.
# When measuring this, check for a layer=0 Wallspace window first.

let
  videoPath = "${config.home.homeDirectory}/Pictures/Wallpapers/cozy-8bit.mp4";
in
{
  home.file.".local/bin/wallspace-seed-wallpaper" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ./wallspace/seed-wallpaper.py;
    executable = true;
  };

  # Power-saving toggles, set from the app's UI and recorded here so a fresh
  # machine gets them without a visit to Settings. These are the whole reason
  # this app was chosen over the DIY options, which have no automatic pausing
  # at all -- so they should not depend on someone remembering to tick them.
  #
  # `targets.darwin.defaults` would be the tidier home-manager way, but this
  # domain also holds the wallpaper SELECTION (savedWallpaperKey and friends),
  # which the app rewrites on quit. Managing the whole domain declaratively
  # would fight it, so only these specific keys are pinned -- the same
  # narrow-ownership approach the seed script takes.
  home.activation.wallspaceSettings = lib.mkIf pkgs.stdenv.isDarwin
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      # Deliberately one long line, no shell line-continuations: inside a
      # Nix indented string a backslash is literal, so a trailing backslash
      # reaches bash as a real backslash and breaks the loop.
      for KEY in wallpaperAutoPauseOnLowPowerMode wallpaperAutoPauseOnBatteryBelow20Percent wallpaperAutoPauseOnFullscreen startOnLoginEnabled autoStartWallpaperEngine; do
        $DRY_RUN_CMD /usr/bin/defaults write wallspace.app "$KEY" -bool true
      done
    '');

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
