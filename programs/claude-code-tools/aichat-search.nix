{ lib
, stdenv
, fetchurl
}:

let
  # Select the appropriate binary based on the platform
  sources = {
    aarch64-darwin = {
      url = "https://github.com/pchalasani/claude-code-tools/releases/download/rust-v0.3.0/aichat-search-macos-arm64.tar.gz";
      sha256 = "sha256-5ZY2FV56E7+HLqlJYXD2rVcY8KOiBKGIBB7b7YtgXqo=";
    };
    x86_64-darwin = {
      url = "https://github.com/pchalasani/claude-code-tools/releases/download/rust-v0.3.0/aichat-search-macos-intel.tar.gz";
      sha256 = "sha256-1Hgm0K/RtP6Yo2M7541BKTUst0Jh7kE231+brWPtgNg=";
    };
    x86_64-linux = {
      url = "https://github.com/pchalasani/claude-code-tools/releases/download/rust-v0.3.0/aichat-search-linux-x86_64.tar.gz";
      sha256 = "sha256-/2YYuLv3Gr7hlyBldxbvUy/pS3CNUnMDOh5/TVL/30I=";
    };
    aarch64-linux = {
      url = "https://github.com/pchalasani/claude-code-tools/releases/download/rust-v0.3.0/aichat-search-linux-arm64.tar.gz";
      sha256 = "sha256-SvNfsO9L6T0c27IP1bPnjg74XyA5rkkrYCSKgqChT34=";
    };
  };

  source = sources.${stdenv.hostPlatform.system} or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

in stdenv.mkDerivation rec {
  pname = "aichat-search";
  version = "0.3.0";

  src = fetchurl {
    inherit (source) url sha256;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp aichat-search $out/bin/
    chmod +x $out/bin/aichat-search

    runHook postInstall
  '';

  meta = with lib; {
    description = "Rust-based full-text search engine for Claude Code sessions";
    homepage = "https://github.com/pchalasani/claude-code-tools";
    license = licenses.mit;
    platforms = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
    maintainers = [ ];
  };
}
