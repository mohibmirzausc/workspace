{ lib
, buildPythonPackage
, fetchPypi
, rustPlatform
, cargo
, rustc
, maturin
}:

buildPythonPackage rec {
  pname = "tantivy";
  version = "0.25.1";
  format = "pyproject";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-2JNlkOSQVaezBk/VZfOhV62YqobyNpsu9W0a6NPwbBI=";
  };

  cargoDeps = rustPlatform.fetchCargoTarball {
    inherit src;
    name = "${pname}-${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Will get from build error
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    maturin
    cargo
    rustc
  ];

  buildPhase = ''
    runHook preBuild
    maturin build --release --strip --manylinux off
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 target/wheels/*.whl $out/
    runHook postInstall
  '';

  pythonImportsCheck = [ "tantivy" ];

  meta = with lib; {
    description = "Python bindings for Tantivy, a full-text search engine library";
    homepage = "https://github.com/quickwit-oss/tantivy-py";
    license = licenses.mit;
    maintainers = [ ];
  };
}
