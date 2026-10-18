# moab, nix-darwin side: the Homebrew tap and formula, and the launchd agent
# that keeps the moab daemon up with its API key. Work machines only
# (features.work, flake.nix); see programs/moab/default.nix for the toolchain.
#
# Why a launchd-managed daemon: moab's credential routes read
# ANTHROPIC_API_KEY from the *daemon's* environment and broker it into the
# nono sandbox. A daemon the CLI auto-starts from a shell has whatever that
# shell has: no key, and Homebrew's unsupported nono first on PATH.
# programs/moab/home.nix sets MOAB_DAEMON_BIN in user sessions so the CLI
# can't start one; this agent is the only way the daemon starts.
#
# Note the key is in the daemon's environment, so it is visible to what moab
# runs *outside* the sandbox too: tool (parallelogram) nodes and hooks, and
# agents of any run started without --sandbox nono (home.nix makes nono the
# default via MOAB_SANDBOX). An unsandboxed claude-agent-acp would bill the API
# key instead of the Claude subscription.
{ pkgs, lib, user, home, features, ... }:

let
  moab = pkgs.callPackage ./. { inherit user; };
  enabled = features.work && pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
  label = "org.nixos.moab-daemon";
  # A stable path, not the launcher's store path: the plist then doesn't change
  # when the launcher does, so nix-darwin doesn't reload the agent (killing
  # running pipelines) on unrelated rebuilds. postActivation below restarts it
  # deliberately when the launcher or moab actually changed.
  launcherPath = "/etc/profiles/per-user/${user}/bin/moab-daemon-launch";
in
lib.mkIf enabled {
  # Private tap: Homebrew downloads the release with your GitHub credentials,
  # so run `gh auth login` first, then `brew trust mechanical-orchard/tap`
  # once (see the ONE-TIME MANUAL STEP note in darwin.nix). Prebuilt on Apple
  # Silicon: the formula fetches the sha-pinned release tarball, nothing is
  # compiled. Ships moab plus moab-daemon and moab-runner in libexec/ (only
  # moab is linked onto PATH).
  homebrew.taps = [ "mechanical-orchard/tap" ];
  #
  # Homebrew's own `gh` is needed for that download, though nix already
  # provides gh: Homebrew gets your GitHub token by running `gh auth token`
  # with a PATH of only its shims, /usr/bin:/bin:/usr/sbin:/sbin and
  # /opt/homebrew/opt/gh/bin (utils/github/api.rb github_cli_token), so the
  # nix gh is invisible and the private release answers 404
  # (GitHub::API::HTTPNotFoundError). It shares the nix gh's login
  # (~/.config/gh plus the keychain). Listed first so it is installed before
  # moab. HOMEBREW_GITHUB_API_TOKEN is no alternative: nix-darwin runs brew
  # under `sudo --preserve-env=PATH`, and homebrew.extraEnv would put the
  # token in the nix store.
  homebrew.brews = [ "gh" "mechanical-orchard/tap/moab" ];

  users.users.${user}.packages = [ moab.launcher ];

  # KeepAlive only on a non-zero exit. The launcher exits 0 whenever it can't
  # or shouldn't start (prompt dismissed, 1Password locked, a daemon already
  # running, a startup failure) and moab-daemon exits 0 on `moab service
  # stop`, so none of those loops on fingerprint prompts; a crash after the
  # daemon was up for a minute is restarted. Start it by hand with
  #   launchctl kickstart -k gui/$(id -u)/org.nixos.moab-daemon
  # `moab service status` lists the credential variables the daemon holds.
  launchd.user.agents.moab-daemon = {
    serviceConfig = {
      ProgramArguments = [ launcherPath ];
      EnvironmentVariables = {
        HOME = home;
        LANG = "en_US.UTF-8";
      };
      RunAtLoad = true;
      KeepAlive = { SuccessfulExit = false; };
      ThrottleInterval = 60;
      StandardOutPath = "${home}/Library/Logs/moab-daemon.log";
      StandardErrorPath = "${home}/Library/Logs/moab-daemon.log";
    };
  };

  # nix-darwin loads user agents BEFORE the homebrew step, so on the first
  # activation RunAtLoad fires before moab is installed (the launcher logs it
  # and exits). And after `brew upgrade moab` the old daemon keeps running the
  # old version. So after Homebrew, restart the agent when moab or the launcher
  # changed, or when it isn't running. Runs as root; the gui domain is the
  # user's. Restarting stops active runs; it only happens on a rebuild.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    moab_uid=$(id -u ${user})
    moab_stamp_dir=${home}/.local/state/moab-daemon
    moab_want="$(readlink -f /opt/homebrew/opt/moab 2>/dev/null || echo none) $(readlink -f ${launcherPath} 2>/dev/null || echo none)"
    moab_running=no
    if launchctl print "gui/$moab_uid/${label}" 2>/dev/null | grep -q 'state = running'; then
      moab_running=yes
    fi
    if [ "$(cat "$moab_stamp_dir/activation" 2>/dev/null)" != "$moab_want" ] || [ "$moab_running" = no ]; then
      echo "moab: (re)starting the moab daemon (approve the 1Password prompt)"
      launchctl kickstart -k "gui/$moab_uid/${label}" \
        || echo "warning: could not kickstart ${label}"
      sudo -u ${user} mkdir -p "$moab_stamp_dir"
      printf '%s' "$moab_want" | sudo -u ${user} tee "$moab_stamp_dir/activation" >/dev/null
    fi
  '';
}
