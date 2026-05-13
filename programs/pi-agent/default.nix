{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs,
}:

buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.74.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha512-Q5GikbB5vRBrsrrf/uvet53rPSQ1sn5I5mO+l7sIobdXYpS04/X2oOc2UHFm90fNdkl3yU+ANTZL0zOtHbnqRw==";
  };

  # The published tarball ships pre-built dist/ but no package-lock.json.
  # We vendor a lockfile generated from this exact package.json so npm
  # can populate node_modules deterministically inside the Nix sandbox.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-wHezOFyQQNb9SmRe+RCH5LfE+JEp0v053R1xgNzJYIQ=";

  # dist/ is already built upstream; skip the build phase entirely.
  dontNpmBuild = true;

  # Avoid lifecycle scripts that would try to recompile native deps.
  npmFlags = [ "--ignore-scripts" ];

  inherit nodejs;

  meta = {
    description = "Pi minimal terminal coding agent (pi.dev)";
    homepage = "https://pi.dev";
    license = lib.licenses.unfree;
    mainProgram = "pi";
    platforms = lib.platforms.unix;
  };
}
