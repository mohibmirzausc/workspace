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
# Two things are deliberately NOT tracked, because OmniWM regenerates them as
# runtime state and they would produce churn in every diff:
#
#   [[appRules]]    auto-discovered per-app minimum window sizes, each carrying
#                   a freshly generated UUID `id`. Real, intentional rules
#                   (float/tile/assign-to-workspace) can be added here later --
#                   see `omniwmctl rule add --help`.
#   [[workspaces]]  live workspace list + per-workspace monitorAssignment.
#
# Dropping them means the app recreates them on first launch from its own
# defaults, which is what we want.

{
  home.file.".config/omniwm/settings.toml" = lib.mkIf pkgs.stdenv.isDarwin {
    force = true;   # overwrite the app-managed file on activation
    source = ./omniwm/settings.toml;
  };
}
