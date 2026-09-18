{ config, pkgs, lib, ... }:

# VoiceInk -- local-model dictation, driven by a hotkey. Installs two commands,
# `voiceink-update` (build/install from source) and `voiceink-doctor` (diagnose
# a dead hotkey). See programs/voiceink/package.nix for why the build is a
# wrapper script instead of a derivation.
#
# THE APP IS NOT INSTALLED BY A SWITCH. Nothing here downloads or builds
# anything; `homeswitch` only puts the two commands on PATH. Build the app with:
#
#   voiceink-update             # clone or pull, build, install to /Applications
#   voiceink-update --clean     # also rebuild the cached whisper framework
#   voiceink-update --repo PATH # checkout other than ~/workspace/VoiceInk
#
# PREREQUISITE: THE FULL Xcode.app, not the Command Line Tools. As of this
# module landing, this machine has only /Library/Developer/CommandLineTools, so
# the first run will stop at the preflight check with install instructions:
#
#   1. Install Xcode (App Store, ~10GB).
#   2. sudo xcode-select -s /Applications/Xcode.app
#
# The first build then downloads the Metal toolchain (~700MB, once) because
# whisper.cpp's Metal kernels need it and Xcode 26 ships it separately.
# Deliberately NOT added to homebrew.casks in darwin.nix: the cask needs an
# Apple ID sign-in anyway, so it cannot be made automatic, and it would add
# ~10GB to bootstrapping a machine that may never want dictation.
#
# AFTER AN XCODE UPGRADE, stale content under /Library/Developer makes the
# build die with "No CMAKE_CXX_COMPILER could be found", which sounds like a
# compiler problem and is not. voiceink-update runs `xcodebuild -runFirstLaunch`
# every time to head that off.
#
# PERMISSIONS ARE THE SHARP EDGE. Local builds are ad-hoc signed, so the
# signature's designated requirement is a bare CDHash. Any rebuild whose output
# actually changes gets a new hash, and macOS quietly stops honouring VoiceInk's
# Accessibility grant while System Settings still shows it switched on -- and
# the rejection may not surface until the next reboot, so it can look fine for
# days and then the hotkey just does nothing. voiceink-update compares CDHash to
# detect a real change, clears the grants so the breakage is visible rather than
# silent, and prints re-grant steps. Use --keep-permissions to leave them.
#
# THE PROPER FIX IS A STABLE SELF-SIGNED CERTIFICATE, which the script already
# looks for by the name "VoiceInk Local" and falls back to ad-hoc signing when
# it is absent or untrusted. Not created here, because a keychain identity is
# not something Nix can own or reproduce. To stop re-granting permissions on
# every rebuild, create it once by hand:
#
#   Keychain Access > Certificate Assistant > Create a Certificate
#     name "VoiceInk Local", Self Signed Root, type Code Signing
#   security find-certificate -c "VoiceInk Local" -p > cert.pem
#   security add-trusted-cert -r trustRoot -p codeSign \
#     -k ~/Library/Keychains/login.keychain-db cert.pem
#
# Trusting it matters: an untrusted certificate forms an identity but not a
# *valid* one, `security find-identity -v` omits it, and the build silently
# falls back to ad-hoc. Note the script also disables the hardened runtime when
# signing with this cert -- a self-signed cert has no Team ID, and the hardened
# runtime requires the process and its frameworks to share one, so the app
# would die at launch loading whisper.framework.
#
# VoiceInk needs Accessibility, NOT Input Monitoring: it never calls the IOHID
# access APIs, so it cannot appear in that pane.

{
  home.packages = lib.mkIf pkgs.stdenv.isDarwin [
    (pkgs.callPackage ./voiceink/package.nix { })
  ];
}
