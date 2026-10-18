# moab, user side. Work machines only (features.work, flake.nix); see
# programs/moab/darwin.nix for the daemon and default.nix for the toolchain.
{ config, pkgs, lib, user, features, ... }:

let
  moab = pkgs.callPackage ./. { inherit user; };

  # moab-run (start pipelines sandboxed in a throwaway clone, collect the result) lives in the
  # memory repo, separate from mem (src/moab, docs/moab-run.md). Run from the checkout like mem
  # (programs/mem.nix), on node 26 for its TypeScript type stripping.
  moabRun = pkgs.writeShellApplication {
    name = "moab-run";
    runtimeInputs = [ pkgs.nodejs_26 ];
    text = ''
      entry="${config.home.homeDirectory}/src/memory/src/moab/cli.ts"
      if [ ! -f "$entry" ]; then
        echo "moab-run: no memory checkout at ~/src/memory (expected $entry)" >&2
        exit 3
      fi
      exec node "$entry" "$@"
    '';
  };
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

  home.packages = [ moabRun ];

  # The moab skills, for both harnesses, beside the shared ones (programs/agents/skills is linked
  # file by file, so these extra entries don't collide). `moab` points at moab's own authoring
  # skills for the installed version; `moab-worker` is the run loop with moab-run.
  home.file = lib.listToAttrs (lib.concatMap (skill:
    map (dir: lib.nameValuePair "${dir}/${skill}" { source = ./skills + "/${skill}"; recursive = true; })
      [ ".pi/agent/skills" ".claude/skills" ]) [ "moab" "moab-worker" ]);
}
