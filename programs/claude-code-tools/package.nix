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
          # Force claude-code-tools to use the PyPI wheel (1.10.3) instead of building from source (1.10.2)
          # The uv.lock in the git repo is outdated and points to 1.10.2, but PyPI has the correct 1.10.3 wheel with node_modules
          claude-code-tools = prev.claude-code-tools.overrideAttrs (old: {
            # Force wheel installation
            format = "wheel";
            # Fetch the wheel directly from PyPI
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/9e/2e/d8ffc99c74bd4afa6e54c798c8f4f5ddad7f6f6869ccd8aecb37b6d087d2/claude_code_tools-1.10.3-py3-none-any.whl";
              hash = "sha256-Z3Dj1VLiLPzHKqYfh5O9iSKlQ8HdWx5kEIk8gGfqHVs=";
            };
          });
        })
      ]
    );

  # Build the virtual environment
  venv = pythonSet.mkVirtualEnv "claude-code-tools-env" workspace.deps.default;

in pkgs.stdenv.mkDerivation {
  pname = "claude-code-tools";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/lib

    # Copy the entire venv to a lib directory (for runtime dependencies)
    # The Python wheel already contains node_modules in node_ui/
    cp -r ${venv} $out/lib/venv

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
