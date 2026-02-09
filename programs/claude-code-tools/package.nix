{ lib
, pkgs
, pyproject-nix
, uv2nix
, pyproject-build-systems
, nodejs
, nodePackages
, makeWrapper
, fetchFromGitHub
}:

let
  version = "1.10.3";

  # Fetch source from GitHub instead of vendoring
  src = fetchFromGitHub {
    owner = "pchalasani";
    repo = "claude-code-tools";
    rev = "v${version}";
    hash = "sha256-/ht0Xt+Pm8MICiSWhrsFBsLmHA/JdfaYGCq8DdANRkg=";
  };

  # Load the workspace from the fetched source
  workspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = src;
  };

  # Create overlay from uv.lock
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel"; # Use wheels when available for faster builds
  };

  # Get compatible Python interpreter
  python = lib.head (
    lib.filter (p: lib.versionAtLeast p.version "3.11") [
      pkgs.python311
      pkgs.python312
      pkgs.python313
    ]
  );

  # Build Python base set with overrides for packages missing build dependencies
  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.default
        overlay
        # Add build dependencies for packages that don't declare them properly
        (final: prev: {
          fire = prev.fire.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
              final.setuptools
            ];
          });
        })
      ]
    );

  # Build the virtual environment with all dependencies from workspace
  # This includes claude-code-tools 1.10.2 from source, but we'll replace it with the PyPI wheel
  venvDeps = pythonSet.mkVirtualEnv "claude-code-tools-deps-env" workspace.deps.default;

  # Fetch the PyPI wheel which includes node_modules
  claudeCodeToolsWheel = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/9e/2e/d8ffc99c74bd4afa6e54c798c8f4f5ddad7f6f6869ccd8aecb37b6d087d2/claude_code_tools-1.10.3-py3-none-any.whl";
    hash = "sha256-k91w32UovG3sEIVLzh1miYXqylpJekocFOuRsQPtB2c=";
  };

in pkgs.stdenv.mkDerivation {
  pname = "claude-code-tools";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper python ];

  buildPhase = ''
    # Copy the dependencies venv
    mkdir -p $TMPDIR/venv
    cp -r ${venvDeps}/* $TMPDIR/venv/

    # Install the claude-code-tools wheel (which includes node_modules) into the venv
    $TMPDIR/venv/bin/pip install --no-deps ${claudeCodeToolsWheel}
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib

    # Copy the complete venv (now with claude-code-tools from PyPI wheel)
    cp -r $TMPDIR/venv $out/lib/venv

    # Only expose the claude-code-tools commands by creating wrapper scripts
    for cmd in aichat tmux-cli fix-session vault env-safe csv2gsheet gsheet2csv gdoc2md md2gdoc; do
      if [ -f $out/lib/venv/bin/$cmd ]; then
        makeWrapper $out/lib/venv/bin/$cmd $out/bin/$cmd \
          --prefix PATH : ${lib.makeBinPath [ nodejs ]}
      fi
    done
  '';

  meta = with lib; {
    description = "Collection of tools for working with Claude Code";
    homepage = "https://github.com/pchalasani/claude-code-tools";
    license = licenses.mit;
    maintainers = [ ];
  };
}
