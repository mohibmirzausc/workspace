final: prev: {
  # Fetch Claude Code directly from Anthropic's official distribution
  claude-code = prev.stdenv.mkDerivation rec {
    pname = "claude-code";
    version = "2.1.39";

    src = prev.fetchurl {
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/darwin-arm64/claude";
      hash = "sha256-2NeiuZamkQNqU5M6JZpTIlSkAJNK7kUuKJ4fREMCbYI=";
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/claude
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Claude Code CLI - Agentic coding tool from Anthropic";
      homepage = "https://code.claude.com";
      license = licenses.unfree;
      platforms = [ "aarch64-darwin" ];
      maintainers = [ ];
    };
  };
}
