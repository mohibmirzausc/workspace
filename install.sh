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

  # Run darwin-rebuild with sudo (it needs root for system activation)
  sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake .#Mohibs-MacBook-Pro
else
  echo "Running home-manager switch..."
  USER="$USER" HOME="$HOME" nix --extra-experimental-features "nix-command flakes" run home-manager -- switch -b backup --flake .#linux --impure --show-trace
fi
