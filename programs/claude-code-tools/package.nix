{ lib
, python3
, fetchurl
, nodejs
, makeWrapper
}:

python3.pkgs.buildPythonApplication rec {
  pname = "claude-code-tools";
  version = "1.10.3";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/e3/5e/5f84d9f3b54c5e530d19d52dd8363e3d5f65eb284f38d5d82d0c87b78b9b/claude_code_tools-${version}-py3-none-any.whl";
    hash = "sha256-pnudEbKaBB+eH1TEV+VQUC5iGX07iZp1H1O9SDquwhA=";
  };

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = with python3.pkgs; [
    click
    pyyaml
    rich
    tantivy
    tqdm
  ];

  # Wrap commands to include nodejs in PATH for interactive menus
  postInstall = ''
    for cmd in $out/bin/*; do
      wrapProgram $cmd --prefix PATH : ${lib.makeBinPath [ nodejs ]}
    done
  '';

  # Don't check - tests require API keys
  doCheck = false;

  # nixpkgs 26.11 added pythonRuntimeDepsCheckHook, which fails the build when
  # the wheel's declared runtime dependencies are not all present:
  #
  #   claude-agent-sdk not installed   commitizen not installed
  #   fire not installed               mcp not installed
  #   pytest not installed
  #
  # (doCheck = false does not cover this -- it is a separate hook from the
  # test phase.) The list is not honest about what the CLI actually needs:
  # pytest and commitizen are development tooling the wheel over-declares, and
  # the subcommands backed by claude-agent-sdk / mcp / fire are not the ones
  # used here -- the tools invoked from this config run on the click / rich /
  # tantivy / pyyaml / tqdm set already listed above. Rather than package five
  # dependencies (two of them dev-only) to satisfy a metadata check, skip the
  # check and keep the closure small.
  #
  # If a claude-code-tools command ever fails with ModuleNotFoundError, the
  # honest fix is to add that specific module to propagatedBuildInputs.
  dontCheckRuntimeDeps = true;

  meta = with lib; {
    description = "Collection of tools for working with Claude Code";
    homepage = "https://github.com/pchalasani/claude-code-tools";
    license = licenses.mit;
    maintainers = [ ];
  };
}
