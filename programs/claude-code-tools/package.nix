{ lib
, python3Packages
, fetchPypi
, nodejs
}:

python3Packages.buildPythonApplication rec {
  pname = "claude-code-tools";
  version = "1.10.3";
  format = "pyproject";

  src = fetchPypi {
    pname = "claude_code_tools";
    inherit version;
    hash = "sha256-W78vrIEN4Dnk8eHWTQj3u72FRM9TnQgs8SI2YvsiGPc=";
  };

  # Node.js is required for action menus
  nativeBuildInputs = [
    nodejs
  ];

  propagatedBuildInputs = with python3Packages; [
    # Core dependencies
    click
    fire
    mcp
    pyyaml
    rich
    tantivy
    tqdm
    # Note: claude-agent-sdk might need to be packaged separately
  ];

  pythonImportsCheck = [ "claude_code_tools" ];

  meta = with lib; {
    description = "Collection of tools for working with Claude Code - session management, terminal automation, and safety features";
    homepage = "https://github.com/pchalasani/claude-code-tools";
    license = licenses.mit;
    maintainers = [ ];
  };
}
