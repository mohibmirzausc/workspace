{ lib
, buildPythonPackage
, fetchPypi
, hatchling
, httpx
, pydantic
, mcp
, pydantic-settings
}:

buildPythonPackage rec {
  pname = "ticktick-sdk";
  version = "0.2.1";
  format = "pyproject";

  src = fetchPypi {
    pname = "ticktick_sdk";
    inherit version;
    hash = "sha256-OtP1mekFYhIEbt84s4854IzjGlctC/q6oFlVQ6NXwis=";
  };

  nativeBuildInputs = [
    hatchling
  ];

  propagatedBuildInputs = [
    httpx
    pydantic
    mcp
    pydantic-settings
  ];

  pythonImportsCheck = [ "ticktick_sdk" ];

  meta = with lib; {
    description = "A comprehensive async Python SDK for TickTick with MCP server support";
    homepage = "https://github.com/dev-mirzabicer/ticktick-sdk";
    license = licenses.mit;
    maintainers = [ ];
  };
}
