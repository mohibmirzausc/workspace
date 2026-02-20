{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  zlib,
  libiconv,
  apple-sdk_15,
  stdenv,
}:

rustPlatform.buildRustPackage rec {
  pname = "yx";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "mattwynne";
    repo = "yaks";
    rev = "ead238d97d935af4646fdbc0997bc80a4844fe9e";
    hash = "sha256-6pkpH7bcYhLg/CWgowKQbInZVU8YsiPQbbdLAtBHEVo=";
  };

  cargoHash = "sha256-daUBBtahFyemLC2Qc6Wua6So3E7m77cljbmM+unHk04=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    openssl
    zlib
  ] ++ lib.optionals stdenv.isDarwin [
    libiconv
    apple-sdk_15
  ];

  doCheck = false;

  meta = {
    description = "DAG-based TODO list CLI for software teams";
    homepage = "https://github.com/mattwynne/yaks";
    license = lib.licenses.mit;
    mainProgram = "yx";
  };
}
