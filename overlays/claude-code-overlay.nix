final: prev: {
  # Fetch latest Claude Code from unstable nixpkgs
  claude-code = let
    unstablePkgs = import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/fef9403a3e4d31b0a23f0bacebbec52c248fbb51.tar.gz";
      sha256 = "1fzknmnvbfj8bxkw7bqcyjvxy3v2vz11vkp3r8nwihmrf6wnlpd4";
    }) {
      system = prev.system;
      config.allowUnfree = true;
    };
  in unstablePkgs.claude-code;
}
