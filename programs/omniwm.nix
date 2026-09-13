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
# from upstream's key ids on every release, so the TOML is tracked verbatim.
#
# INSTALLED AS A MUTABLE COPY, NOT A SYMLINK -- this matters.
#
# OmniWM rewrites this file whenever you change anything in its Settings UI.
# Managing it via home.file makes ~/.config/omniwm/settings.toml a read-only
# symlink into the nix store, which the app cannot write to -- and OmniWM does
# not warn or error when the save fails. It keeps the new values in memory and
# they look applied until the process exits, at which point they are gone. That
# silently destroyed a batch of real settings changes once already.
#
# So this follows the same activation-script pattern as the LinearMouse config
# in home.nix (home.activation.installLinearMouseConfig): the seed is copied in
# as a writable file, re-copied only when the tracked seed's hash changes, and
# a legacy symlink at that path is replaced. GUI changes therefore persist, and
# the repo still reproduces a known-good baseline on a fresh machine.
#
# Workflow for changing settings: tune in the GUI, then copy the result back
#
#     cp ~/.config/omniwm/settings.toml programs/omniwm/settings.toml
#
# and commit. Editing the tracked seed directly also works -- the hash change
# is what triggers the re-copy on the next rebuild.
#
# The file is tracked in FULL, including the sections that look machine-written.
# Do not be tempted to "clean up" the two array-of-table sections:
#
#   [[workspaces]]  Looks like runtime state (UUID `id` per entry) but carries
#                   real configuration: the custom workspace displayNames and,
#                   more importantly, each workspace's monitorAssignment ("main"
#                   vs "secondary"). Stripping this silently loses the emoji
#                   names and un-pins the multi-monitor layout.
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
  home.activation.installOmniwmConfig = lib.mkIf pkgs.stdenv.isDarwin
    (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      OW_DIR="$HOME/.config/omniwm"
      OW_FILE="$OW_DIR/settings.toml"
      OW_SEED="${./omniwm/settings.toml}"
      OW_STAMP="$OW_DIR/.seed-hash"

      $DRY_RUN_CMD mkdir -p "$OW_DIR"

      # Replace a legacy read-only symlink (from when this was managed via
      # home.file) with a writable copy of the seed.
      if [ -L "$OW_FILE" ]; then
        $DRY_RUN_CMD rm "$OW_FILE"
      fi

      SEED_HASH="$(${pkgs.coreutils}/bin/sha256sum "$OW_SEED" | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
      PREV_HASH=""
      if [ -f "$OW_STAMP" ]; then
        PREV_HASH="$(${pkgs.coreutils}/bin/cat "$OW_STAMP")"
      fi

      # Only overwrite when the tracked seed itself changed, so settings saved
      # from OmniWM's UI survive unrelated rebuilds.
      if [ ! -f "$OW_FILE" ] || [ "$SEED_HASH" != "$PREV_HASH" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 "$OW_SEED" "$OW_FILE"
        if [ -z "$DRY_RUN_CMD" ]; then
          printf '%s\n' "$SEED_HASH" > "$OW_STAMP"
        else
          echo "would write $OW_STAMP"
        fi
      fi
    '');
}
