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

  meta = with lib; {
    description = "Collection of tools for working with Claude Code";
    homepage = "https://github.com/pchalasani/claude-code-tools";
    license = licenses.mit;
    maintainers = [ ];
  };
}
