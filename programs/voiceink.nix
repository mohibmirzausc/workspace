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
# PREREQUISITE: THE FULL Xcode.app, not the Command Line Tools -- because the
# build needs `xcodebuild`, which the CLT ship but refuse to run:
#
#   xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
#   directory '/Library/Developer/CommandLineTools' is a command line tools
#   instance
#
# Two things here need it. VoiceInk is a SwiftUI app whose build is defined by
# VoiceInk.xcodeproj, and a scheme is an Xcode concept that swiftc cannot read.
# And `make whisper` runs whisper.cpp's build-xcframework.sh, which drives cmake
# with the XCODE GENERATOR -- cmake emits an .xcodeproj and calls xcodebuild on
# it. Having clang and swift from the CLT (this machine has Swift 6.2) is not
# enough for either.
#
# Upstream's own `make check` is a weaker test than reality: it only does
# `command -v xcodebuild`, which PASSES on a CLT-only machine, so the build
# clears the prerequisite check and then fails later. voiceink-update's
# preflight checks for /Applications/Xcode.app and the xcode-select target
# instead, which is why it fails cleanly and early.
#
# As of this module landing, this machine has only the CLT, so the first run
# stops at that preflight with install instructions:
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
# it is absent or untrusted. That certificate HAS been created on this machine
# (verified: `security find-identity -v -p codesigning` reports it valid, and
# the script's own detection returns it rather than the fallback), so rebuilds
# should keep their grants. It is not created BY Nix: a keychain identity is
# private key material that Nix can neither own nor reproduce, and putting it
# in the store would publish the key. Recreate it on a new machine with:
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
# signing with this cert -- a self-signed cert has no Team ID (confirmed here:
# a test signature reports `TeamIdentifier=not set`), and the hardened runtime
# requires the process and its frameworks to share one, so the app would die at
# launch loading whisper.framework.
#
# Upstream cannot find this certificate on its own, which is why the script
# patches LocalBuild.xcconfig for the duration of the build. Two upstream facts
# force that, both re-verified against the current checkout: the xcconfig
# hardcodes `CODE_SIGN_IDENTITY = -` and an xcconfig beats a command-line build
# setting, and `make local` only auto-detects identities matching
# "Apple Development: ", which a self-signed cert never does.
#
# VoiceInk needs Accessibility, NOT Input Monitoring: it never calls the IOHID
# access APIs, so it cannot appear in that pane.

{
  home.packages = lib.mkIf pkgs.stdenv.isDarwin [
    (pkgs.callPackage ./voiceink/package.nix { })
  ];
}
