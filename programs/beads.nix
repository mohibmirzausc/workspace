{
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "beads";
  version = "0.24.3";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-BXmQEgBH2GrfgKDRGvU5pCM3WGUyTA2e6VNduO5Y144=";
  };

  vendorHash = "sha256-Pmd/kVUgS8mHaCxrZ3mFSqnodHgp0Ts+gShQLW9Hxl0=";

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  # Tests require network access and git setup
  doCheck = false;

  meta = {
    mainProgram = "bd";
  };
}