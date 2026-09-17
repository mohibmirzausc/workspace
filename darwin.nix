{ config, pkgs, lib, user, home, system, ... }:

let
  # Environment shared by the sketchybar daemon and its event bridge, both
  # declared in launchd.user.agents below. Kept here rather than in
  # programs/sketchybar.nix because launchd agents live in nix-darwin while
  # that module is home-manager, and crossing that boundary for one attrset is
  # more indirection than it is worth.
  #
  # PATH is the load-bearing part: launchd's default omits /opt/homebrew/bin
  # (sketchybar, omniwmctl) and jq, and plugin scripts are spawned by the
  # daemon so they inherit it. COLOR_*/WM_BAR_FONT are the Catppuccin Mocha
  # palette, read by both sketchybarrc and the plugins.
  sketchybarEnv = {
    PATH = "/opt/homebrew/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    # UTF-8 locale. WITHOUT THIS, EVERY MULTI-BYTE ICON RENDERS AS LITERAL
    # "\uf0b1" TEXT. launchd hands agents no locale at all, and sketchybar
    # needs one to decode the UTF-8 bytes of a private-use-area codepoint --
    # so the whole Nerd Font icon set silently degrades to escape text while
    # ASCII items (and sketchybar-app-font's ligatures, which ARE ascii) keep
    # working. That asymmetry is what made this look like a font bug.
    #
    # Matches upstream SketchyBar issue #154 / #176.
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    WM_BACKEND = "omniwm";
    # Departure Mono: lo-fi pixel/bitmap monospace. The Nerd Font patched
    # build, so one family covers both the text and the glyph ranges.
    WM_BAR_FONT = "DepartureMono Nerd Font";
    # This family ships REGULAR ONLY. CoreText does not synthesise the missing
    # weight -- it falls back to Helvetica, silently, which does not look like
    # a pixel font at all. So the bar's "bold" weight is Regular here.
    # Switching back to JetBrainsMono? Set this to "Bold".
    WM_BAR_FONT_BOLD = "Regular";
    # ONE window pill (the focused window) to start; widen to 2 later if the
    # room is there. Upstream defaults to 3.
    #
    # The constraint is the notch, measured at 663pt from the left edge on this
    # 1512pt panel. notch_width does NOT solve this: it reserves the centre for
    # CENTER-anchored items, while left-anchored items flow rightward straight
    # past the reservation. So the left side has to be narrow by construction.
    # With 3 pills the island spanned 282-701, i.e. 38pt under the notch.
    WM_WIN_MAX = "1";
    COLOR_BG = "0xee1e1e2e";
    COLOR_FG = "0xffcdd6f4";
    COLOR_DIM = "0xff7f849c";
    COLOR_ACCENT = "0xffcba6f7";
    COLOR_ON_ACCENT = "0xff1e1e2e";
    COLOR_ITEM_BG = "0x40313244";
    COLOR_POPUP_BG = "0xf0181825";
    COLOR_POPUP_BORDER = "0xff45475a";
    COLOR_BLUE = "0xff89b4fa";
    COLOR_FLAMINGO = "0xfff2cdcd";
    COLOR_PEACH = "0xfffab387";
    COLOR_TEAL = "0xff94e2d5";
    COLOR_SAPPHIRE = "0xff74c7ec";
    COLOR_LAVENDER = "0xffb4befe";
    COLOR_RED = "0xfff38ba8";
  };
in
{
  imports = [
    ./programs/shottr.nix
  ];

  # NOTE: SketchyBar's fonts are installed via Homebrew casks (see
  # homebrew.casks below), NOT via fonts.packages.
  #
  # nix-darwin's fonts.packages symlinks each font DERIVATION into
  # /Library/Fonts/Nix Fonts/, leaving the actual .ttf files six directories
  # deep (<drv>/share/fonts/truetype/NerdFonts/JetBrainsMono/*.ttf). macOS only
  # scans the TOP LEVEL of a font directory, so nothing in there ever gets
  # registered with CoreText and every glyph renders as a \uf... box -- in
  # SketchyBar and in any other app. Verified by printing the codepoints to a
  # terminal: identical boxes there.
  #
  # This is a confusing failure to chase because the fonts look present at
  # every layer you would check: the .ttf exists, its cmap maps the codepoint
  # to a real glyph with a normal advance, and CTFontCreateWithName even
  # round-trips the family name. None of that means CoreText will serve the
  # font to an app.
  #
  # nixpkgs also names these differently from upstream: its Family names are
  # the abbreviated "JetBrainsMono NF/NFM/NFP", with the long
  # "JetBrainsMono Nerd Font Mono" only present as the typographic family
  # (name ID 16). The Homebrew casks use the upstream names that sketchybarrc
  # and kang's plugins ask for.

  # Disable nix-darwin's Nix management (using Determinate Nix)
  nix.enable = false;

  # Necessary for using flakes on this system
  nix.settings.experimental-features = "nix-command flakes";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Apply overlays for package overrides
  # No overlays currently. Both previous ones were removed in the nixpkgs
  # 26.11 upgrade:
  #
  #   shopify-cli  existed only to bump the package to 3.90.1, and nixpkgs now
  #                ships 4.6.0 (upstream's latest). It also pinned
  #                fetchPnpmDeps fetcherVersion = 2, which 26.11 removed
  #                outright, so it broke evaluation.
  #   zellij       patched a hardcoded 3-line mouse-wheel scroll down to 1.
  #                Any overrideAttrs changes the derivation hash, so this cost
  #                a full from-source Rust rebuild of zellij on every nixpkgs
  #                bump -- a large, slow build for a one-line cosmetic tweak,
  #                and the version/src/cargoDeps it also pinned had been
  #                overtaken by nixpkgs anyway. Dropped in favour of the cached
  #                build; mouse wheel now scrolls zellij's default 3 lines.
  #                Upstream still has no config option for this (checked
  #                against the 0.44.x release notes), so restoring the patch
  #                means reinstating the overlay and accepting the rebuild.
  nixpkgs.overlays = [
    # (import ./overlays/claude-code-overlay.nix)  # Using Homebrew cask instead
  ];

  # Primary user for system operations
  system.primaryUser = user;

  # User configuration
  users.users.${user} = {
    name = user;
    home = home;
  };

  # System-wide packages (optional - most can stay in home.nix)
  environment.systemPackages = with pkgs; [
    vim
  ];

  # macOS system defaults
  system.defaults = {
    # Configure dock at bottom (accessible on all monitors) with speed improvements
    dock = {
      orientation = "bottom";
      autohide = true;
      show-process-indicators = true;
      show-recents = false;
      # Speed up dock autohide animation
      autohide-time-modifier = 0.5;
      autohide-delay = 0.0;
      # Speed up expose animation
      expose-animation-duration = 0.1;
      # Minimize windows into application icon
      minimize-to-application = true;
      # Don't rearrange spaces based on most recent use
      mru-spaces = false;
      # Scroll up on dock icon to show all windows or open stack
      scroll-to-open = true;
      # Show only open applications in the dock
      static-only = true;
    };

    # Speed up animations by 2x (reduce animation duration by half)
    NSGlobalDomain = {
      # Reduce window resize time
      NSWindowResizeTime = 0.1;
      # Set icon and widget style to dark mode
      AppleInterfaceStyle = "Dark";
      # Automatically switch between light and dark mode
      AppleInterfaceStyleSwitchesAutomatically = true;
      # Speed up key repeat rate (lower = faster, range 2-120, default 6)
      KeyRepeat = 2;
      # Reduce initial delay before key repeat (lower = faster, range 15-120, default 68)
      InitialKeyRepeat = 15;
      # Auto-hide the native macOS menu bar so SketchyBar (programs/sketchybar.nix)
      # owns the top strip. This does NOT remove the menu bar -- it slides back in
      # whenever the cursor reaches the top of the screen, which means it will
      # temporarily draw over the SketchyBar items underneath. That overlap is
      # inherent to this setup, not a misconfiguration.
      #
      # Note this makes the `thaw` cask (Ice fork menu-bar manager) largely
      # redundant -- it is organising a strip that is now usually offscreen.
      # Left alone rather than ripped out, but if the top of the screen ever
      # misbehaves, that overlap is the first thing to check.
      #
      # OmniWM's own hiddenBar setting is NOT part of that overlap despite being
      # enabled = true in programs/omniwm/settings.toml: the app reports
      # "Hiding requires macOS 27 or later" and this machine runs 26.6.2, so the
      # feature cannot activate and the stored preference is inert.
      #
      # This machine has a notch: hiding the menu bar does not reclaim it, so
      # SketchyBar items still have to route around that dead centre zone once
      # the bar grows enough to reach it.
      _HIHideMenuBar = true;
    };

    # Spotlight settings - disable the default Command+Space shortcut
    # This disables the Spotlight search keyboard shortcut
    CustomUserPreferences = {
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Disable Spotlight search (Command+Space)
          "64" = {
            enabled = false;
            value = {
              parameters = [ 32 49 1048576 ];
              type = "standard";
            };
          };
          # Disable "Show Desktop" gesture (clicking desktop to hide windows)
          "36" = {
            enabled = false;
          };
          "37" = {
            enabled = false;
          };
        };
      };
      # Disable Stage Manager if on macOS Ventura or later
      "com.apple.WindowManager" = {
        GloballyEnabled = false;
        AutoHide = false;
        StageManagerHideWidgets = false;
      };
      # cmux settings that its cmux.json schema does NOT cover. Everything
      # expressible in the schema is pinned declaratively in programs/cmux.nix
      # instead (cmux imports that JSON into this same defaults domain); these
      # keys exist only here, so without this block they silently drift back to
      # cmux's defaults on a fresh machine.
      "com.cmuxterm.app" = {
        # Compact sidebar rows: show only the last path segment rather than the
        # full workspace path.
        sidebarPathLastSegmentOnly = false;
        # Chrome-less workspace presentation ("minimal" hides the tab bar).
        workspacePresentationMode = "minimal";
        # Global show/hide hotkey.
        "systemWideHotkey.enabled" = true;
        # Idle-screen mascot/glow/theme, all set to the cmux branding.
        "sleepyMode.mascot" = "cmux";
        "sleepyMode.glow" = "cmux";
        "sleepyMode.theme" = "cmux";
        # Render custom sidebars in-process (the alternative spawns a helper).
        "customSidebars.renderer" = "inProcess";
        "customSidebars.beta.enabled" = false;
        # Right sidebar shows the file tree; beta dock mode off.
        "rightSidebar.mode" = "files";
        "rightSidebar.beta.dock.enabled" = false;
        "sidebar.beta.workspaceTodos.controls.enabled" = true;
        # iPhone pairing host disabled.
        "mobile.iOSPairingHost.enabled" = false;
      };
      # Note: com.apple.universalaccess is applied via system.activationScripts
      # below because it's a protected domain that may fail silently
    };
  };

  # Apply protected accessibility defaults (best-effort, may fail without Full Disk Access)
  system.activationScripts.postActivation.text = ''
    defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true 2>/dev/null || true
    defaults write com.apple.universalaccess closeViewScrollWheelModifiersInt -int 1048576 2>/dev/null || true

    # Make the menu-bar auto-hide take effect in the RUNNING session.
    #
    # system.defaults.NSGlobalDomain._HIHideMenuBar above writes the preference,
    # but macOS caches it: `defaults read` reports 1 while the menu bar stays
    # permanently visible until the next logout. Poking it through System Events
    # applies it immediately, so activation does not leave a correct-on-disk /
    # wrong-on-screen split.
    #
    # Guarded because this needs the Automation TCC grant for System Events; if
    # that is missing the write above still lands and a logout will pick it up.
    /usr/bin/osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to true' 2>/dev/null || \
      echo "note: could not apply menu-bar autohide live; it will apply after logout"
  '';

  # Enable Touch ID for sudo (including inside tmux sessions)
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation = {
      # "uninstall" removes Homebrew packages not listed here but, unlike "zap",
      # respects dependencies. "zap" tried to remove ca-certificates/openssl@3/etc.
      # that gcloud-cli depends on, producing a "Refusing to uninstall ... required
      # by gcloud-cli" error on every run. "uninstall" is dependency-aware and quiet.
      cleanup = "uninstall";
      autoUpdate = true;
      upgrade = true;
    };
    # Third-party taps. Must be declared here as well as in `brews` below:
    # onActivation.cleanup = "uninstall" prunes taps that aren't listed, so an
    # undeclared tap would be removed on every switch and re-added on the next.
    #
    # ONE-TIME MANUAL STEP on a new machine: Homebrew refuses to load formulae
    # from third-party taps until they are explicitly trusted, so activation
    # fails with "Refusing to load formula ... from untrusted tap" until you run
    #
    #     brew trust superradcompany/tap
    #
    # once. This cannot be declared here: `brew trust` records the decision in
    # ~/.homebrew/trust.json (or $XDG_CONFIG_HOME/homebrew/trust.json), which
    # nix-darwin does not manage.
    taps = [
      "superradcompany/tap"  # microsandbox; see brews below
      # SketchyBar's upstream tap. nixpkgs has sketchybar too (2.24.0) but lags
      # upstream releases; taken from Homebrew for the faster cadence, same
      # reasoning as flyctl and pi below. Needs `brew trust felixkratz/formulae`
      # once per machine -- see the ONE-TIME MANUAL STEP note above.
      "felixkratz/formulae"  # sketchybar
    ];
    # Fly.io CLI. Homebrew ships the formula with daily updates, well ahead of
    # nixpkgs. The formula drops both `flyctl` and `fly` into /opt/homebrew/bin;
    # home.nix removes the `fly` symlink on activation so it doesn't shadow
    # Concourse's `fly` CLI at /usr/local/bin/fly. See home.activation.removeBrewFlyLink.
    brews = [
      "flyctl"
      # Tailscale CLI. Connectivity on this machine comes from the standalone
      # macsys Tailscale.app and its network system extension, NOT from a
      # tailscaled we run ourselves -- so do NOT `brew services start
      # tailscale`. That would stand up a second, competing client.
      #
      # The formula bundles its own tailscaled binary; we install it only for
      # the `tailscale` CLI and leave the daemon unstarted.
      #
      # This CLI does drive the app's daemon -- `tailscale status` returns the
      # real tailnet, verified on 2026-08-13. It prints a harmless version-skew
      # warning first:
      #
      #   Warning: client version "1.102.2-teb67e5dcb" != tailscaled server
      #   version "1.102.2-t6cac91817-g6ff0ddc72"
      #
      # Same 1.102.2 tag, different builds -- Homebrew's vs Tailscale's official
      # macsys build. Matching version numbers won't silence it, since the two
      # ship independent builds; expect it to persist and to change shape as the
      # app self-updates. If a subcommand ever fails outright on protocol skew,
      # /Applications/Tailscale.app/Contents/MacOS/Tailscale is the exact-match
      # fallback.
      "tailscale"
      "pi-coding-agent"  # Pi terminal coding agent (pi.dev). Homebrew ships it
                         # ahead of nixpkgs and autoUpdate/upgrade keep it current.
      # nono (nono.sh, github.com/nolabs-ai/nono): capability sandbox for AI
      # coding agents. Declares fs/network access up front and lets the kernel
      # enforce it -- Seatbelt on macOS, Landlock on Linux -- so no daemon, no
      # container, no VM, and the agent cannot widen its own constraints from
      # the inside. Shape is `nono run --profile <p> -- <agent>`.
      #
      # Paired with microsandbox below deliberately: the two sit at different
      # points on the isolation/overhead curve and we want to compare them on
      # real moab runs. nono is process-level and needs nothing installed
      # inside it, so the existing node/ACP-adapter/credential setup works
      # unchanged; microsandbox is a hardware boundary but needs a guest image.
      # moab's own backend evaluation (docs/sandbox/sandbox-evaluation.md in
      # the moab repo) scores nono 5/5/5/5/5/5 and rates microsandbox a 2 on
      # fit, VM-based backends being out of scope there -- so nono is the
      # likelier long-term answer for wrapping agents.
      #
      # In homebrew-core, so unlike microsandbox it needs no `brew trust`.
      "nono"
      # ttyd (tsl0922.github.io/ttyd): serves a terminal over HTTP/WebSocket, so
      # a local shell or TUI is reachable from a browser -- handy for driving a
      # long-running session from another device on the tailnet.
      #
      # In nixpkgs too (same 1.7.7), but Homebrew keeps it: the bottle links
      # against the brew openssl@3/libwebsockets already here for other formulae,
      # and autoUpdate/upgrade track releases without waiting on a flake bump.
      #
      # Binds 0.0.0.0 by default. Prefer `ttyd -i lo0` (or a Tailscale interface)
      # over exposing an unauthenticated shell on every interface; `-c user:pass`
      # adds basic auth.
      "ttyd"
      # microsandbox (microsandbox.dev): runs untrusted code -- AI agents,
      # plugins, CI jobs -- in hardware-isolated microVMs that boot in
      # milliseconds. Installs the `msb` CLI (not `microsandbox`).
      #
      # Homebrew rather than nixpkgs for two reasons. It isn't in nixpkgs at
      # all, and more importantly the release binary is code-signed with the
      # com.apple.security.hypervisor and disable-library-validation
      # entitlements it needs to boot VMs. The formula is careful to install it
      # without running install_name_tool, because touching the binary would
      # invalidate that signature and strip the entitlements, and macOS would
      # then kill it on launch. A nixpkgs-style build that patches rpaths would
      # hit exactly that problem.
      #
      # Apple Silicon only -- the formula calls `odie` on x86_64 macOS.
      "superradcompany/tap/microsandbox"
      # SketchyBar status bar. Config is generated by programs/sketchybar.nix
      # into ~/.config/sketchybar/sketchybarrc; the launchd agent that keeps it
      # running is declared below in launchd.user.agents.sketchybar.
      #
      # From the upstream tap rather than nixpkgs for release cadence. The
      # formula also ships a `brew services` definition, which we do NOT use --
      # the launchd agent here owns the process, and running both would start
      # two bars.
      "felixkratz/formulae/sketchybar"
    ];
    casks = [
      "1password-cli"
      "calibre"
      "claude-code@latest"  # Auto-updating Claude Code CLI (v2.1.140)
      "codex"         # OpenAI's terminal coding agent (github.com/openai/codex).
                      # Depends on ripgrep (already provided in home.nix).
      "cmux"          # Ghostty-based macOS terminal for running AI agents in
                      # parallel; reads ~/.config/ghostty/config for appearance.
                      # cmux-specific config in programs/cmux.nix. Auto-updates.
      # SketchyBar's two glyph fonts, from Homebrew rather than
      # fonts.packages -- see the long note near the top of this file. Casks
      # install the .ttf files flat into ~/Library/Fonts, which macOS actually
      # registers, and they carry upstream's family names
      # ("JetBrainsMono Nerd Font Mono", not nixpkgs' "JetBrainsMono NFM").
      #
      # font-sketchybar-app-font is a LIGATURE font and a separate thing from
      # the Nerd Font: plugins/icon_map.sh emits literal text like ":terminal:"
      # which it substitutes with that app's glyph. The cask ships 2.0.86,
      # closer to the 2.0.60 mappings icon_map.sh was generated from than the
      # 2.0.62 in nixpkgs.
      "font-jetbrains-mono-nerd-font"
      # Departure Mono -- lo-fi pixel/bitmap-style monospace, the bar's font
      # (WM_BAR_FONT in the sketchybar agent env). The NERD FONT variant, not
      # plain "font-departure-mono": the patched build keeps the pixel look
      # and adds the glyph ranges, so the bar keeps one font for text and
      # icons. Family name is "DepartureMono Nerd Font".
      #
      # Note this is a PIXEL font: it is designed around a small em grid and
      # looks crisp at sizes that land on whole pixels, blurry between them.
      "font-departure-mono-nerd-font"
      # Hack is SketchyBar's built-in default font, so keeping it installed
      # means the bar still renders if a custom font name is ever wrong.
      "font-hack-nerd-font"
      "font-sketchybar-app-font"
      "flycut"
      "fossa"
      "gcloud-cli"
      # greedy: the cask is marked auto_updates upstream, so `brew bundle`
      # skips it and defers to Karabiner's own updater -- which left this
      # machine stranded on 15.7.0 (Nov 2025) while 16.1.0 was current.
      # greedy upgrades it on rebuild regardless. Set per-cask rather than
      # via onActivation.greedy so the other auto_updates casks (cmux,
      # raycast, linearmouse, thaw) keep self-updating on their own schedule.
      #
      # NOTE: Karabiner 16.0.0+ requires a NEW Accessibility grant for
      # Karabiner-Core-Service. TCC grants cannot be automated (SIP-protected),
      # so after the upgrade lands, approve it in System Settings > Privacy &
      # Security > Accessibility or Karabiner will silently stop working.
      {
        name = "karabiner-elements";
        greedy = true;
      }
      "linearmouse"   # Fast-scroll when holding modifier key (configured in home.nix)
      # Tiling window manager (arm64 + macOS 26 only). Ships an `omniwmctl`
      # CLI symlinked out of the app bundle for scripting layouts.
      #
      # NOTE: needs a one-time Accessibility grant in System Settings >
      # Privacy & Security > Accessibility to move windows at all. TCC grants
      # are SIP-protected and cannot be automated from here, so the app will
      # launch but silently do nothing until it is approved by hand.
      #
      # Pre-1.0 (0.6.9) and very low adoption upstream (single-digit installs
      # per year via brew), so treat breakage across updates as expected.
      "omniwm"
      # Replaces eqmac. Per-app volume and per-app EQ, a system-wide output EQ,
      # output boost above 100%, and menu-bar device switching.
      #
      # PAID ($59, trial available) and marked auto_updates upstream, so
      # `brew bundle` will not upgrade it -- it self-updates on its own
      # schedule, same as raycast/cmux/linearmouse below. Not set greedy,
      # unlike karabiner-elements, because nothing here depends on a pinned
      # version.
      #
      # First launch needs a one-time audio-driver approval in System Settings
      # (it installs a virtual audio device to sit in the output path), and
      # Rogue Amoeba's installer asks for admin once. Neither can be automated.
      #
      # NOTE this does NOT raise microphone gain: macOS caps input volume at
      # 100 and no userspace app exceeds that. SoundSource is for OUTPUT
      # shaping. If the mic sounds quiet, check the input level first --
      #   osascript -e 'input volume of (get volume settings)'
      # Krisp/Zoom/Tandem/Tuple all lower it and do not restore it.
      "soundsource"
      "superwhisper"
      "raycast"
      "thaw"          # Menu bar manager (Ice fork) for macOS 26+
      "ticktick"
      "finetune"
    ];
  };

  # Always-on local gallery server for the `html-page` Claude skill. Runs at
  # login, restarts on crash, serves ~/html-pages at http://localhost:7777.
  # Managed here (nix-darwin launchd.user.agents) rather than home-manager's
  # launchd.agents, which is not activated when HM runs as a nix-darwin module.
  launchd.user.agents.html-pages-server = {
    serviceConfig = {
      ProgramArguments = [ "${pkgs.callPackage ./programs/html-pages-server { }}/bin/html-pages-server" ];
      EnvironmentVariables = {
        PORT = "7777";
        HTML_PAGES_DIR = "${home}/html-pages";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${home}/Library/Logs/html-pages-server.log";
      StandardErrorPath = "${home}/Library/Logs/html-pages-server.log";
    };
  };

  # SketchyBar status bar. Config lives in programs/sketchybar.nix, which writes
  # ~/.config/sketchybar/sketchybarrc; this just keeps the daemon alive.
  #
  # Same rationale as html-pages-server above: declared in nix-darwin's
  # launchd.user.agents rather than home-manager's launchd.agents, which is not
  # activated when HM runs as a nix-darwin module.
  #
  # KeepAlive so it comes back if it crashes. Note SketchyBar needs no special
  # TCC grant to draw its own bar, but items that read other apps' state (e.g.
  # window titles) would -- the starting config here only uses SketchyBar's own
  # front_app event and pmset, so it works unattended.
  launchd.user.agents.sketchybar = {
    serviceConfig = {
      # Homebrew path, not a nix store path: sketchybar comes from
      # felixkratz/formulae (see homebrew.brews above). Hardcoded rather than
      # interpolated because nix has no reference to a brew-installed binary.
      ProgramArguments = [ "/opt/homebrew/bin/sketchybar" ];
      # sketchybarrc AND every plugin inherit this environment. Both halves
      # matter:
      #
      #   PATH    launchd's default is /usr/bin:/bin:/usr/sbin:/sbin, which has
      #           neither /opt/homebrew/bin (sketchybar, omniwmctl) nor jq. Item
      #           scripts are spawned by the daemon, so they inherit that same
      #           minimal PATH -- without this the bar draws but every label
      #           renders empty, which is a confusing way to fail.
      #   COLOR_* the Catppuccin Mocha palette. Plugins inherit sketchybar's
      #           environment but NOT variables exported inside sketchybarrc, so
      #           this is the only place both can read one definition from.
      EnvironmentVariables = sketchybarEnv;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${home}/Library/Logs/sketchybar.log";
      StandardErrorPath = "${home}/Library/Logs/sketchybar.log";
    };
  };

  # OmniWM -> SketchyBar event bridge. Translates OmniWM's IPC event stream
  # into the three wm_* events sketchybarrc subscribes to; see the provenance
  # notes in programs/sketchybar.nix.
  #
  # Depends on OmniWM IPC being enabled, which needs a one-time "Enable IPC"
  # click in OmniWM's menu bar icon (the settings.toml flag alone is not
  # enough on 0.6.10). The bridge is written to no-op safely when omniwmctl or
  # sketchybar is missing, so KeepAlive will not spin on a half-set-up machine.
  launchd.user.agents.sketchybar-bridge = {
    serviceConfig = {
      ProgramArguments = [
        "${home}/.config/sketchybar/bridge.sh"
        "omniwm"
      ];
      EnvironmentVariables = sketchybarEnv;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${home}/Library/Logs/sketchybar-bridge.log";
      StandardErrorPath = "${home}/Library/Logs/sketchybar-bridge.log";
    };
  };

  # Used for backwards compatibility, please read the changelog before changing
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on. Provided by flake.nix
  # specialArgs so the same config works on both Apple Silicon and Intel Macs.
  nixpkgs.hostPlatform = system;
}
