{ lib
, pkgs
, pyproject-nix
, uv2nix
, pyproject-build-systems
, nodejs
}:

let
  # Load the workspace from the source directory
  workspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = ./source;
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

in pythonSet.mkVirtualEnv "claude-code-tools-env" workspace.deps.default
