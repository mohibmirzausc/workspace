{
  symlinkJoin,
  writers,
  git,
  cmake,
  gnumake,
}:

# VoiceInk is a GPL-3 macOS dictation app (Superwhisper replacement). Its
# prebuilt binary is a paid license, but building from source is free and
# supported upstream via `make local`.
#
# Ported from github.com/lexun/system (packages/voiceink) at 9d9b1d2, which is
# a good deal further along than the write-up that prompted this: it also
# carries the stable-signing-certificate path, the Metal toolchain download and
# the package-plugin trust defaults. The scripts are kept as close to upstream
# as possible so his fixes can be pulled forward by diffing rather than
# re-derived -- every comment in them marks a failure mode that was paid for
# once already.
#
# This is a script rather than a real derivation on purpose: the build drives a
# SwiftUI .xcodeproj through xcodebuild plus a cmake Xcode-generator build of a
# whisper.cpp xcframework, all of which need the full Xcode.app that the Nix
# build sandbox cannot reach. An impure derivation would give up Nix's
# guarantees while keeping its complexity, so the imperative parts stay
# explicit and the recoverable failure modes are checked up front instead.

let
  voiceink-update = writers.writeNuBin "voiceink-update" ''
    const NIX_BIN_PATHS = [ "${git}/bin" "${cmake}/bin" "${gnumake}/bin" ]

    ${builtins.readFile ./voiceink-update.nu}
  '';

  # Separate binary because diagnosing is not updating: the hotkey breaks for
  # reasons that have nothing to do with rebuilding the app, and reaching for
  # voiceink-update to investigate is what turned one stale system lock into a
  # multi-day hunt.
  voiceink-doctor = writers.writeNuBin "voiceink-doctor" (
    builtins.readFile ./voiceink-doctor.nu
  );
in
symlinkJoin {
  name = "voiceink-tools";
  paths = [
    voiceink-update
    voiceink-doctor
  ];
}
