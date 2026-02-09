{ lib
, stdenv
, makeWrapper
, uv
, nodejs
}:

stdenv.mkDerivation rec {
  pname = "claude-code-tools";
  version = "1.10.3";

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Create wrapper script that uses uv to install claude-code-tools
    cat > $out/bin/claude-code-tools-install <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

UV_BIN="${uv}/bin/uv"
TOOL_HOME="$HOME/.local/share/claude-code-tools"

echo "Installing claude-code-tools via uv..."
"$UV_BIN" tool install --force claude-code-tools

# Create symlinks to the installed tools
for cmd in aichat tmux-cli fix-session vault env-safe; do
  if [ -f "$HOME/.local/bin/$cmd" ]; then
    ln -sf "$HOME/.local/bin/$cmd" "$TOOL_HOME/bin/$cmd"
  fi
done

echo "claude-code-tools installed successfully!"
echo "Make sure ~/.local/bin is in your PATH to use: aichat, tmux-cli, fix-session, vault, env-safe"
EOF

    chmod +x $out/bin/claude-code-tools-install

    runHook postInstall
  '';

  meta = with lib; {
    description = "Collection of tools for working with Claude Code - session management and terminal automation";
    homepage = "https://github.com/pchalasani/claude-code-tools";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
