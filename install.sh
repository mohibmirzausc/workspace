#!/usr/bin/env bash

# Note: Do NOT run this script with sudo directly!
# The script will use sudo internally where needed.

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
  # NONINTERACTIVE=1 makes `brew bundle cleanup` (homebrew.onActivation.cleanup = "zap")
  # skip its "Do you want to proceed with the cleanup? [y/n]" prompt so the
  # install runs unattended instead of blocking on stdin.
  sudo USER="$USER" HOME="$HOME" NONINTERACTIVE=1 nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake .#darwin --impure

  # Garbage-collect old generations so the nix store doesn't grow unbounded.
  # On Determinate Nix (nix.enable = false) nix-darwin does NOT manage the daemon,
  # so nix.gc.automatic is ineffective — we GC explicitly here instead.
  # KEEP_DAYS: delete system + home-manager generations older than this, then
  # collect the now-unreferenced store paths. Override with KEEP_DAYS=N ./install.sh.
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
  echo "Running home-manager switch..."
  USER="$USER" HOME="$HOME" nix --extra-experimental-features "nix-command flakes" run home-manager -- switch -b backup --flake .#linux --impure --show-trace
fi
