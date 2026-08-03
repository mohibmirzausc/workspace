#!/usr/bin/env bash

# Note: Do NOT run this script with sudo directly!
# The script will use sudo internally where needed.

# Parse flags. Nix generation cleanup / garbage collection is OFF by default
# and only runs when --cleanup is passed:
#   bash install.sh            -> switch only
#   bash install.sh --cleanup  -> switch, then GC old generations
RUN_CLEANUP=0
for arg in "$@"; do
  case "$arg" in
    --cleanup) RUN_CLEANUP=1 ;;
    *) echo "Unknown argument: $arg" >&2; echo "Usage: bash install.sh [--cleanup]" >&2; exit 1 ;;
  esac
done

# Detect if running on macOS
if [[ "$(uname)" == "Darwin" ]]; then
  echo "Detected macOS - running nix-darwin switch..."

  # Check if script is being run with sudo
  if [ "$EUID" -eq 0 ]; then
    echo "Error: Do not run this script with sudo!"
    echo "Run it as: ./install.sh"
    echo "The script will request sudo when needed."
    exit 1
  fi

  # Run darwin-rebuild with sudo (it needs root for system activation).
  # Pass USER/HOME through sudo and use --impure so the flake can read them at build time.
  #
  # Homebrew runs during activation and otherwise blocks on
  #   ==> Do you want to proceed with the cleanup? [y/n]
  # These env vars make it fully non-interactive:
  #   NONINTERACTIVE=1               - brew never prompts (answers yes to confirmations)
  #   HOMEBREW_NO_INSTALL_CLEANUP=1  - skip the post-install cleanup that raises that prompt
  #   HOMEBREW_NO_ENV_HINTS=1        - silence the "Hide these hints..." noise
  sudo USER="$USER" HOME="$HOME" \
    NONINTERACTIVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 \
    nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake .#darwin --impure

  # Re-run home-manager's user activation explicitly.
  #
  # The switch above reliably builds the correct home-manager generation into the
  # system closure, but its user-activation step does not always run, so
  # `linkGeneration` never fires and ~/ keeps symlinks into the PREVIOUS
  # home-manager-files store path. The switch still reports success, so the
  # result is a silent no-op: files under programs/ (claude skills, settings.json,
  # ...) are built and staged but never linked, and stay stale until something
  # forces activation. This was observed leaving ~/.claude pinned to an old
  # generation across several switches, hiding newly added skills entirely.
  #
  # nix-darwin wraps the home-manager generation in an `activation-<user>` script
  # and invokes it from `activate`. Re-running that script directly is idempotent
  # (it just relinks the generation), so doing it unconditionally is safe and
  # makes a stale-link outcome impossible.
  #
  # The path is scraped out of the just-activated `activate` script rather than
  # hardcoded or evaluated separately, so it stays correct for any username and
  # always matches the generation that was actually switched to.
  echo "Re-running home-manager user activation..."
  HM_ACTIVATE=$(grep -o '/nix/store/[a-z0-9]\{32\}-activation-[^ "]*' \
    /nix/var/nix/profiles/system/activate 2>/dev/null | head -1)
  if [ -n "$HM_ACTIVATE" ] && [ -x "$HM_ACTIVATE" ]; then
    "$HM_ACTIVATE"
    echo "home-manager user activation complete."
  else
    # Not fatal: the switch itself succeeded, and on a config with no
    # home-manager user there is nothing to activate.
    echo "Warning: could not locate the home-manager activation script;" >&2
    echo "         files under programs/ may not be linked into \$HOME." >&2
  fi

  # Garbage-collect old generations so the nix store doesn't grow unbounded.
  # On Determinate Nix (nix.enable = false) nix-darwin does NOT manage the daemon,
  # so nix.gc.automatic is ineffective — we GC explicitly here instead.
  # Only runs when --cleanup is passed (it is destructive and slow), so a plain
  # switch stays fast and leaves rollback generations intact.
  # KEEP_DAYS: delete system + home-manager generations older than this, then
  # collect the now-unreferenced store paths. Override with KEEP_DAYS=N bash install.sh --cleanup.
  if [ "$RUN_CLEANUP" -eq 1 ]; then
    KEEP_DAYS="${KEEP_DAYS:-14}"
    echo "Cleaning up Nix generations older than ${KEEP_DAYS} days and collecting garbage..."

    # Delete old system (darwin) profile generations.
    sudo nix profile wipe-history --older-than "${KEEP_DAYS}d" \
      --profile /nix/var/nix/profiles/system 2>/dev/null \
      || sudo nix-env --delete-generations "${KEEP_DAYS}d" \
           --profile /nix/var/nix/profiles/system

    # Delete old home-manager generations (user-owned profile, no sudo).
    nix profile wipe-history --older-than "${KEEP_DAYS}d" \
      --profile "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null \
      || nix-env --delete-generations "${KEEP_DAYS}d" \
           --profile "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null || true

    # Collect garbage left behind by the deleted generations.
    sudo nix-collect-garbage --delete-older-than "${KEEP_DAYS}d"
    echo "Nix generation cleanup complete."
  else
    echo "Skipping Nix generation cleanup (pass --cleanup to garbage-collect old generations)."
  fi
else
  echo "Running home-manager switch..."
  USER="$USER" HOME="$HOME" nix --extra-experimental-features "nix-command flakes" run home-manager -- switch -b backup --flake .#linux --impure --show-trace
fi
