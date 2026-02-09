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

  # Build the virtual environment
  venv = pythonSet.mkVirtualEnv "claude-code-tools-env" workspace.deps.default;

  # Build node_modules for the Node UI using buildNpmPackage
  nodeUI = pkgs.buildNpmPackage {
    pname = "claude-code-tools-node-ui";
    inherit version;

    src = "${src}/node_ui";

    npmDepsHash = "sha256-cGtWyx4Bv7L58NsftwUFusgZMY1Y7UrlkHhsH2q9mxc=";

    dontNpmBuild = true;

    installPhase = ''
      mkdir -p $out
      cp -r node_modules $out/
    '';
  };

in pkgs.stdenv.mkDerivation {
  pname = "claude-code-tools";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    # Copy the venv and add node_modules
    mkdir -p $TMPDIR/venv
    cp -r ${venv}/* $TMPDIR/venv/
    chmod -R +w $TMPDIR/venv

    # Link node_modules into the Python site-packages node_ui directory
    ln -sf ${nodeUI}/node_modules $TMPDIR/venv/lib/python*/site-packages/node_ui/node_modules
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib

    # Copy the modified venv
    cp -r $TMPDIR/venv/* $out/

    # Only expose the claude-code-tools commands, not all python packages
    for cmd in aichat tmux-cli fix-session vault env-safe csv2gsheet gsheet2csv gdoc2md md2gdoc; do
      if [ -f $out/bin/$cmd ]; then
        wrapProgram $out/bin/$cmd \
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
