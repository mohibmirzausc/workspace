final: prev: {
  # Fetch latest Claude Code from unstable nixpkgs
  claude-code = let
    unstablePkgs = import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/c5296fdd05cfa2c187990dd909864da9658df755.tar.gz";
      sha256 = "0xbslcscqsmzqc08anc7hgcykp41vf6khfk9bds42lshapb8vjd0";
    }) {
      system = prev.system;
      config.allowUnfree = true;
    };
  in unstablePkgs.claude-code;
}
