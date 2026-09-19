{ config, pkgs, lib, ... }:

# VoiceInk -- local-model dictation, driven by a hotkey. Installs two commands,
# `voiceink-update` (build/install from source) and `voiceink-doctor` (diagnose
# a dead hotkey). See programs/voiceink/package.nix for why the build is a
# wrapper script instead of a derivation.
#
# THE APP IS NOT INSTALLED BY A SWITCH. Nothing here downloads or builds
# anything; `homeswitch` only puts the two commands on PATH. Build the app with:
#
#   voiceink-update             # build the latest RELEASE TAG, install to /Applications
#   voiceink-update --ref main  # build the branch tip instead
#   voiceink-update --ref v2.13 # pin an older release (also the rollback path)
#   voiceink-update --clean     # also rebuild the cached whisper framework
#   voiceink-update --repo PATH # checkout other than ~/workspace/VoiceInk
#
# NOTHING UPDATES ITSELF. There is no launchd agent and no activation hook, so
# a new VoiceInk release is picked up only when you run voiceink-update again.
#
# It builds the newest release tag rather than main, because main is not a
# thing upstream chose to ship. Left on main this checkout reached 95 commits
# PAST v2.13 while v2.20 was already released -- i.e. on no release at all,
# carrying whatever refactor was in flight. See checkout-target in
# voiceink-update.nu for the two tag-selection traps this repo's tag list
# contains (out-of-order tag dates, and malformed tags that `sort -V` ranks
# above every real one).
#
# ROLLBACK IS `--ref <older tag>` AND A REBUILD. The script deletes the
# installed app before moving the new one into place, so there is no previous
# generation to return to the way there would be for a Nix-managed package.
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
# The Metal toolchain is a separate ~700MB component (mlx-swift's kernels need
# it, and so do whisper.cpp's), and STILL SEPARATE ON XCODE 27 -- the `metal`
# binary ships inside XcodeDefault.xctoolchain while the toolchain behind it
# does not, so `xcrun --find metal` exits 0 on a machine that cannot compile a
# single .metal file. voiceink-update's check was upstream's `--find` test,
# which this machine proved is a false negative; it now runs `xcrun metal
# --version`, since only a real toolchain answers that. Cost of the bug: the
# build ran ~7400 log lines and failed in mlx-swift's CompileMetalFile steps,
# which looks like an mlx problem rather than a missing Xcode component.
#
# Xcode CANNOT be installed by a switch, so this stays a manual prerequisite.
# There is no `xcode` Homebrew cask (Apple's licence forbids redistribution),
# and `mas install 497799835` fails with "No downloads initiated" because Apple
# removed the private API mas drove for apps not already tied to the signed-in
# Apple ID. Every route ends at an interactive Apple ID sign-in, so automating
# it is not possible -- and it would add ~10GB to bootstrapping a machine that
# may never want dictation.
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
# THE KEY'S ACL MATTERS AS MUCH AS THE TRUST, and this one is not in Luke's
# notes -- his certificate was made in Keychain Access, which grants the key a
# permissive ACL, while a key imported with `security import` demands
# interactive authorization. Symptom: every CodeSign step in the build fails
# with `errSecInternalComponent` while `security find-identity -v` still lists
# the identity as valid, so the certificate looks entirely healthy. The tell is
# that a plain `codesign --sign <hash> <file>` reproduces it outside the build,
# and a SecurityAgent process is alive holding a GUI prompt no headless build
# can answer. `security set-key-partition-list` alone did NOT fix it; the
# pending prompt had to be approved (Always Allow, not Allow -- one build signs
# dozens of targets). Verify with a real signature rather than the lock state:
#
#   codesign --force --sign "VoiceInk Local" /tmp/t && codesign -dvvv /tmp/t
#
# `Authority=VoiceInk Local` means it works; `errSecInternalComponent`, or an
# unchanged Apple authority, means the key is still gated.
#
# Trusting it matters too: an untrusted certificate forms an identity but not a
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
