#!/usr/bin/env bash

nix --extra-experimental-features "nix-command flakes" run home-manager -- switch -b backup --flake . --show-trace
