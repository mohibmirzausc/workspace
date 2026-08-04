{ config, pkgs, lib, ... }:

# Global `just` recipes, usable from any directory.
#
# `just` itself is installed via home.packages (home.nix). This module only
# provides the *global* justfile: it's symlinked to ~/.config/just/justfile,
# which `just --global-justfile` (`just -g`) reads regardless of cwd.
#
# The shell wrapper in programs/zsh (home.nix) makes a plain `just` fall back
# to this global file when the current directory has no local justfile, so
# global recipes "just work" anywhere while local project justfiles still win.
#
# Edit recipes in programs/just/justfile.

{
  home.file.".config/just/justfile".source = ./just/justfile;
}
