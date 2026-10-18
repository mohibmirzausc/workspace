# moab's sandboxed runtime: the pieces `moab run start --sandbox nono` needs on
# the PATH of the daemon that launches agents, plus the launcher launchd keeps
# alive (darwin.nix: launchd.user.agents.moab-daemon).
#
# Why each piece is pinned here rather than taken from what is already installed:
#
#   * nono: moab refuses any nono except the exact release in its
#     nono-pin.toml (0.73.0 for moab 0.39), because nono is pre-1.0. Homebrew's
#     nono (darwin.nix brews) tracks upstream (0.79.0 on 2026-10-17) and stays
#     for interactive use; this one is put first on the *daemon's* PATH only.
#     The hash is the aarch64-apple-darwin digest from moab's nono-pin.toml.
#     When moab bumps its pin, update version + hash from that file.
#
#   * node: the ACP adapters are `#!/usr/bin/env node` scripts. moab grants the
#     sandbox read access to the interpreter binary only, not to libraries it
#     loads (docs/sandbox/sandbox-nono.md "Agent adapter runtime"). Both node
#     builds on this machine load dylibs from outside nono's baseline -- nix's
#     from /nix/store/*-libuv etc., Homebrew's from /opt/homebrew/opt/* -- so
#     the adapter would die at launch. nodejs.org builds link only system
#     libraries; that is the build the docs name. Hash from the release's
#     SHASUMS256.txt.
#
#   * adapters: claude-agent-acp and codex-acp, installed with `npm install -g`
#     into adapterPrefix by home.nix (home.activation.installMoabAdapters), using
#     this node. Published only to npm; nixpkgs' claude-agent-acp (0.64.0) is
#     older than the 0.87.0 moab warns about. A global npm tree is the layout
#     moab expects: it grants the adapter's whole node_modules read-only.
{ pkgs, lib, home }:

let
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
    dontFixup = true;          # ship the upstream binary byte for byte
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

  adapterPrefix = "${home}/.local/share/moab-toolchain/npm";
  adapters = [
    "@agentclientprotocol/claude-agent-acp@0.93.0"
    "@agentclientprotocol/codex-acp@2.2.2"
  ];

  # 1Password references for the API keys moab's credential routes read from
  # the daemon's environment (sandbox.secrets="anthropic" / "openai").
  # Anthropic is required: without it the launcher starts no daemon.
  # OpenAI is optional: null means no key, so Codex nodes can't authenticate
  # sandboxed (Claude Code nodes are unaffected). Set it to an `op://` path to
  # enable them.
  anthropicKeyRef = "op://Employee/Anthropic Pi Coach Key/credential";
  openaiKeyRef = null;

  # PATH for the daemon and every runner/agent it starts: the pinned toolchain
  # first, then the usual dirs (moab and op under /opt/homebrew/bin, claude
  # under ~/.local/bin, git). ~/.cargo/bin is left out on purpose: it holds an
  # old moab 0.33 that must not shadow Homebrew's.
  daemonPath = lib.concatStringsSep ":" [
    "${nono}/bin"
    "${node}/bin"
    "${adapterPrefix}/bin"
    "${home}/.local/bin"
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];

  # Reads the keys from 1Password (needs a fingerprint), then becomes
  # moab-daemon in the foreground so launchd supervises it.
  #
  # Fails closed: if a configured key can't be read -- placeholder ref, 1Password
  # locked or dismissed, `op` hanging (it has hung for >20s here) -- it never
  # starts a keyless daemon. Those exits are status 0 on purpose: launchd only
  # restarts on a non-zero exit (KeepAlive.SuccessfulExit = false), so a
  # dismissed prompt is not retried every few seconds. Start it again with
  #   launchctl kickstart -k gui/$(id -u)/org.nixos.moab-daemon
  launcher = pkgs.writeShellApplication {
    name = "moab-daemon-launch";
    runtimeInputs = [ pkgs.coreutils ];   # timeout(1); macOS has none
    text = ''
      log() { echo "moab-daemon-launch: $(date '+%F %T') $*" >&2; }

      read_key() {
        local name=$1 ref=$2 value
        case "$ref" in
          *REPLACE_ME*)
            log "$name: 1Password reference is still a placeholder ($ref); edit programs/moab/default.nix"
            return 1 ;;
        esac
        if ! value=$(timeout 120 /opt/homebrew/bin/op read --no-newline "$ref"); then
          log "$name: could not read $ref (1Password locked, prompt dismissed, or op timed out)"
          return 1
        fi
        if [ -z "$value" ]; then
          log "$name: $ref is empty"
          return 1
        fi
        printf '%s' "$value"
      }

      ANTHROPIC_API_KEY=$(read_key ANTHROPIC_API_KEY ${lib.escapeShellArg anthropicKeyRef}) || exit 0
      export ANTHROPIC_API_KEY
      keys=ANTHROPIC_API_KEY
    '' + lib.optionalString (openaiKeyRef != null) ''
      OPENAI_API_KEY=$(read_key OPENAI_API_KEY ${lib.escapeShellArg openaiKeyRef}) || exit 0
      export OPENAI_API_KEY
      keys="$keys OPENAI_API_KEY"
    '' + ''

      export PATH=${lib.escapeShellArg daemonPath}
      if ! nono_version=$(nono --version 2>&1) || [ "$nono_version" != "nono ${nono.version}" ]; then
        log "first nono on PATH reports '$nono_version', expected 'nono ${nono.version}'"
        exit 1
      fi
      if ! command -v moab-daemon >/dev/null; then
        log "moab-daemon not on PATH ($PATH); is Homebrew's moab installed?"
        exit 0
      fi
      log "starting $(command -v moab-daemon) ($(moab --version 2>&1)) with $keys"
      exec moab-daemon
    '';
  };
in
{
  inherit nono node adapterPrefix adapters launcher daemonPath;
}
