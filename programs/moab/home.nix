# moab, user side. Work machines only (features.work, flake.nix); see
# programs/moab/darwin.nix for the daemon and default.nix for the toolchain.
{ pkgs, lib, user, features, ... }:

let
  moab = pkgs.callPackage ./. { inherit user; };
  enabled = features.work && pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
in
lib.mkIf enabled {
  home.sessionVariables = {
    # The CLI never starts a daemon itself: it would lack the API key and the
    # pinned nono. The shim tells you to kickstart the launchd agent instead.
    MOAB_DAEMON_BIN = "${moab.daemonShim}/bin/moab-daemon-shim";
    # Sandboxed by default: a run started without --sandbox would give agents
    # the daemon's unbrokered API key. `--sandbox` on the command line still
    # wins; there is no "off" value, so run unsandboxed only with this unset.
    MOAB_SANDBOX = "nono";
  };

  # Lets `moab init`, `moab models` and `moab pipeline validate` find the
  # adapters, as the daemon does. Holds only the two adapter commands.
  home.sessionPath = [ moab.adapterBin ];
}
