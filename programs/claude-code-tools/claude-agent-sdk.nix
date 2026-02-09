{ lib
, buildPythonPackage
, fetchPypi
, hatchling
, anyio
, mcp
, typing-extensions
}:

buildPythonPackage rec {
  pname = "claude-agent-sdk";
  version = "0.1.33";
  format = "pyproject";

  src = fetchPypi {
    pname = "claude_agent_sdk";
    inherit version;
    hash = "sha256-PRZ3sdzbiA3zkHocafIbMsedWPxC1hQl1aDkLMG8dPg=";
  };

  nativeBuildInputs = [
    hatchling
  ];

  propagatedBuildInputs = [
    anyio
    mcp
    typing-extensions
  ];

  pythonImportsCheck = [ "claude_agent_sdk" ];

  meta = with lib; {
    description = "SDK for building Claude AI agents";
    homepage = "https://github.com/anthropics/claude-agent-sdk";
    license = licenses.mit;
    maintainers = [ ];
  };
}
