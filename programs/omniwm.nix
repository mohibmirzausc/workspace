{ config, pkgs, lib, ... }:

# OmniWM -- scrollable-tiling window manager for macOS 26+ (https://omniwm.app/).
# Installed as a Homebrew cask in darwin.nix.
#
# Layout model is "niri" (see general.defaultLayoutType): windows live in
# COLUMNS on an infinite horizontal strip and you scroll through them, rather
# than a binary-split tree like yabai/Amethyst. niri.visibleContainerCount
# controls how many columns are on screen at once. A traditional split layout
# ("dwindle") is also configured and reachable at runtime via Opt+Shift+L.
#
# The settings live in ./omniwm/settings.toml rather than as a Nix attrset
# because OmniWM owns this file's schema (schemaVersion = 3) and writes ~1000
# lines of it, including one [[hotkeys]] block per bindable command (188 of
# them, 67 bound). Round-tripping that through Nix buys nothing and would drift
# from upstream's key ids on every release, so the TOML is tracked verbatim and
# edited in place.
#
# IMPORTANT -- this file is a read-only symlink into the nix store, so OmniWM's
# own Settings UI CANNOT save changes to it. That is deliberate (same tradeoff
# as programs/karabiner.nix): this repo is the single source of truth. To change
# a setting, edit ./omniwm/settings.toml here and rebuild. If you do want to
# explore in the GUI, `rm ~/.config/omniwm/settings.toml` first to let the app
# own a real file again, then copy the result back here.
#
# The file is tracked in FULL, including the sections that look machine-written.
# Do not be tempted to "clean up" the two array-of-table sections:
#
#   [[workspaces]]  Looks like runtime state (UUID `id` per entry) but carries
#                   real configuration: the custom workspace displayNames
#                   (1 = briefcase, 6 = heart, 7 = rocket) and, more
#                   importantly, each workspace's monitorAssignment -- 6 and 7
#                   are pinned to "secondary", the rest to "main". Stripping
#                   this silently loses the emoji names and un-pins the
#                   multi-monitor layout.
#   [[appRules]]    Per-app minimum window sizes. These do appear to be probed
#                   by the app rather than hand-set, but they are kept anyway:
#                   they are harmless, and the cost of guessing wrong here is
#                   losing settings. Intentional rules (float/tile/
#                   assign-to-workspace) can be added alongside them -- see
#                   `omniwmctl rule add`.
#
# In short: OmniWM mixes config and derived state in one file with no marker
# distinguishing them, so the safe default is to track everything verbatim.

{
  home.file.".config/omniwm/settings.toml" = lib.mkIf pkgs.stdenv.isDarwin {
    force = true;   # overwrite the app-managed file on activation
    source = ./omniwm/settings.toml;
  };
}
