# moab's sandboxed-run toolchain, shared by programs/moab/darwin.nix (the
# launchd daemon) and programs/moab/home.nix (user-facing bits). Both are
# gated on features.work (flake.nix): a machine without
# ~/.config/workspace/work gets none of this.
#
# Why each piece is pinned here rather than taken from what is already installed:
#
#   * nono: moab refuses any nono except the exact release in its
#     nono-pin.toml (0.73.0 for moab 0.39), because nono is pre-1.0. Homebrew's
#     nono (darwin.nix brews) tracks upstream (0.79.0 on 2026-10-17) and stays
#     for interactive use; this one is put first on the *daemon's* PATH only.
#     The hash is the aarch64-apple-darwin digest from moab's nono-pin.toml.
#     When moab bumps its pin, update version + hash from that file, and
#     moabVersion below.
#
#   * node: the ACP adapters are node scripts. moab grants the sandbox read
#     access to the interpreter binary only, not to libraries it loads
#     (docs/sandbox/sandbox-nono.md "Agent adapter runtime"). Both node builds
#     on this machine load dylibs from outside nono's baseline -- nix's from
#     /nix/store/*-libuv etc., Homebrew's from /opt/homebrew/opt/* -- so the
#     adapter would die at launch. nodejs.org builds link only system
#     libraries; that is the build the docs name. Hash from the release's
#     SHASUMS256.txt.
#
#   * adapters: claude-agent-acp and codex-acp, published only to npm (nixpkgs'
#     claude-agent-acp is 0.64.0, older than the 0.87.0 moab warns about).
#     Built from the committed adapters/package-lock.json, so every transitive
#     dependency is hash-pinned, installed with --ignore-scripts (the lock has
#     no install scripts), and read-only in /nix/store. Both bundle their agent
#     binary (claude-agent-sdk-darwin-arm64, @openai/codex-darwin-arm64), so no
#     separate claude/codex CLI is needed on the daemon's PATH. To bump: edit
#     adapters/package.json, run `npm install --package-lock-only` there.
{ pkgs, lib, user }:

let
  # The moab release these pins were checked against. The launcher warns when
  # Homebrew has moved moab past it (onActivation.upgrade): check the new
  # release's nono-pin.toml, then bump nono and this together.
  moabVersion = "0.39.0";

  nono = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "nono-moab-pin";
    version = "0.73.0";
    src = pkgs.fetchurl {
      url = "https://github.com/nolabs-ai/nono/releases/download/v${version}/nono-v${version}-aarch64-apple-darwin.tar.gz";
      sha256 = "f17afb66cc513506efea26da583be92d2235bb9467664c21c268f0c4592a7c65";
    };
    sourceRoot = ".";          # the tarball holds a bare `nono`, no directory
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;          # ship the upstream (signed) binary byte for byte
    installPhase = ''
      install -Dm755 nono $out/bin/nono
    '';
  };

  node = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "nodejs-official";
    version = "24.22.0";       # current LTS; the adapters need node >= 22
    src = pkgs.fetchurl {
      url = "https://nodejs.org/dist/v${version}/node-v${version}-darwin-arm64.tar.gz";
      sha256 = "6a9724d9b50a5f22b4816cded441b5a8d9ddae546191a5e5b7efa5a5e2ee26d5";
    };
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;          # no patching: it must keep linking system libs only
    installPhase = ''
      mkdir -p $out
      cp -R . $out
    '';
  };

  # importNpmLock installs with nixpkgs' node and patches every
  # `#!/usr/bin/env node` to that node's store path. moab runs an adapter with
  # the interpreter its #! line names, and nixpkgs' node can't start inside the
  # sandbox (see node above), so the shebangs are pointed at the nodejs.org
  # node instead, and fixup is told not to patch them back.
  adapters = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ./adapters;
    nodejs = pkgs.nodejs;
    derivationArgs = {
      dontPatchShebangs = true;
      postInstall = ''
        grep -rlZ --include='*.js' --include='*.cjs' --include='*.mjs' -e '^#!/nix/store/[^ ]*/bin/node' \
            "$out/node_modules" 2>/dev/null \
          | xargs -0 -r sed -i '1s|^#!/nix/store/[^ ]*/bin/node|#!${node}/bin/node|'
        # Check: nothing is left pointing at another node.
        if grep -rl --include='*.js' -e '^#!/nix/store/[^ ]*/bin/node' "$out/node_modules" \
            | xargs -r grep -L '^#!${node}/bin/node' | grep .; then
          echo "adapters: shebangs still name a node other than ${node}" >&2
          exit 1
        fi
      '';
    };
  };
  # Just the two adapter commands. node_modules/.bin also links every
  # dependency's commands (codex 0.160 among them), which must not shadow the
  # real ones on a user's PATH. The links resolve into the store's
  # node_modules, which is what moab grants the sandbox.
  adapterBinDir = pkgs.runCommand "moab-acp-adapters-bin" { } ''
    mkdir -p $out/bin
    for cmd in claude-agent-acp codex-acp; do
      test -e ${adapters}/node_modules/.bin/$cmd
      ln -s "$(readlink -f ${adapters}/node_modules/.bin/$cmd)" $out/bin/$cmd
    done
  '';
  adapterBin = "${adapterBinDir}/bin";

  # Where moab keeps its state; moab-daemon refuses to start if it is missing.
  moabHome = "/Users/${user}/.moab";
  brewMoab = "/opt/homebrew/opt/moab/libexec";

  # PATH for the daemon and every runner/agent it starts. The pinned toolchain
  # first, then directories only root can write (nix profiles, system), then
  # Homebrew (git, op and friends) and the store-built adapters. Nothing in
  # $HOME: this process holds the API key, and moab write-protects PATH entries
  # only up to the first match, so a user-writable directory early on PATH
  # (~/.local/bin, ~/.cargo/bin with its stale moab 0.33) could be used by a
  # sandboxed node with a broad rw grant to plant a binary that the next
  # unsandboxed tool node runs with the key.
  daemonPath = lib.concatStringsSep ":" [
    "${nono}/bin"
    "${node}/bin"
    "/etc/profiles/per-user/${user}/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
    "/opt/homebrew/bin"
    adapterBin
  ];

  # The moab CLI starts a daemon itself when it finds none, or when the running
  # one is a different version (after `brew upgrade moab`, the old daemon is
  # asked to exit and the CLI spawns a new one from its own environment). That
  # daemon would have no API key and the caller's PATH. The CLI starts the
  # daemon through $MOAB_DAEMON_BIN when it is set (moab src/exe.rs), so user
  # sessions point it here and only launchd ever starts the real one.
  daemonShim = pkgs.writeShellScriptBin "moab-daemon-shim" ''
    echo "moab: the daemon is managed by launchd so it gets the API key from 1Password." >&2
    echo "moab: start it with:  launchctl kickstart -k gui/$(id -u)/org.nixos.moab-daemon" >&2
    echo "moab: log: ~/Library/Logs/moab-daemon.log" >&2
    exit 1
  '';

  # Reads the key from 1Password (needs a fingerprint), then runs moab-daemon
  # with the pinned toolchain first on PATH.
  #
  # Every "can't start" case exits 0, and only after the cheap checks pass
  # does it touch 1Password: launchd restarts only on a non-zero exit
  # (KeepAlive.SuccessfulExit = false), so no misconfiguration or dismissed
  # prompt turns into a fingerprint prompt every minute. The daemon runs as a
  # child rather than via exec so a failure at startup (lock held, port taken)
  # can be told apart from a crash after it was up: the first exits 0, only
  # the second is passed on for launchd to restart.
  launcher = pkgs.writeShellApplication {
    name = "moab-daemon-launch";
    runtimeInputs = [ ];   # PATH is set below; timeout(1) is called by store path (macOS has none)
    text = ''
      log() { echo "moab-daemon-launch: $(date '+%F %T') $*" >&2; }
      daemon=${brewMoab}/moab-daemon
      moab=${brewMoab}/moab
      export PATH=${lib.escapeShellArg daemonPath}
      export MOAB_HOME=${lib.escapeShellArg moabHome}
      unset MOAB_DAEMON_BIN

      if [ ! -x "$daemon" ]; then
        log "$daemon not found; is Homebrew's moab installed? (features.work)"
        exit 0
      fi
      if ! nono_version=$(nono --version 2>&1) || [ "$nono_version" != "nono ${nono.version}" ]; then
        log "first nono on PATH reports '$nono_version', expected 'nono ${nono.version}'"
        exit 0
      fi
      moab_version=$("$moab" --version 2>&1 || true)
      # moab prints a build suffix: "moab 0.39.0 (3ee9971)".
      if [ "''${moab_version%% (*}" != "moab ${moabVersion}" ]; then
        log "warning: Homebrew has $moab_version, pins were checked against ${moabVersion}; if sandboxed runs refuse nono, bump programs/moab/default.nix from the new nono-pin.toml"
      fi
      mkdir -p "$MOAB_HOME"
      if status=$("$moab" service status 2>&1); then
        log "a daemon is already running, leaving it: $(echo "$status" | tr '\n' ' ')"
        log "if it lacks ANTHROPIC_API_KEY: moab service stop, then launchctl kickstart -k gui/$(id -u)/org.nixos.moab-daemon"
        exit 0
      fi

      # At login launchd may get here before the 1Password app is up.
      for _ in $(seq 60); do
        pgrep -x 1Password >/dev/null && break
        sleep 2
      done
      if ! key=$(${pkgs.coreutils}/bin/timeout -k 10 120 /opt/homebrew/bin/op read --no-newline ${lib.escapeShellArg anthropicKeyRef}); then
        log "could not read ${anthropicKeyRef} (1Password locked or not running, prompt dismissed, or op timed out); not starting"
        exit 0
      fi
      if [ -z "$key" ]; then
        log "${anthropicKeyRef} is empty; not starting"
        exit 0
      fi
      export ANTHROPIC_API_KEY="$key"
      unset key

      log "starting $daemon ($moab_version) with ANTHROPIC_API_KEY"
      "$daemon" &
      pid=$!
      trap 'kill -TERM "$pid" 2>/dev/null || true' TERM INT HUP
      started=$(date +%s)
      rc=0
      wait "$pid" || rc=$?
      while kill -0 "$pid" 2>/dev/null; do    # a trapped signal interrupted wait
        rc=0
        wait "$pid" || rc=$?
      done
      ran=$(( $(date +%s) - started ))
      if [ "$rc" -ne 0 ] && [ "$ran" -lt 60 ]; then
        log "moab-daemon failed at startup (exit $rc after ''${ran}s); not retrying. See messages above."
        exit 0
      fi
      log "moab-daemon exited $rc after ''${ran}s"
      exit "$rc"
    '';
  };

  # 1Password reference for the Anthropic key moab's `anthropic` credential
  # route reads from the daemon's environment. The field name is unchecked.
  # No OpenAI key yet, so Codex nodes can't authenticate sandboxed.
  anthropicKeyRef = "op://Employee/Anthropic Pi Coach Key/credential";
in
{
  inherit moabVersion nono node adapters adapterBin daemonPath daemonShim launcher brewMoab;
}
