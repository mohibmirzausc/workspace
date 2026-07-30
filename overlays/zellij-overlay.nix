{ mouseScrollLines ? 1 }:

final: prev: {
  zellij = prev.zellij.overrideAttrs (oldAttrs: rec {
    version = "0.44.3";

    src = final.fetchFromGitHub {
      owner = "zellij-org";
      repo = "zellij";
      rev = "v${version}";
      hash = "sha256-r8GAOiau4CZPVotFmsBQJOvEu+t0Bu9UCYAOs18i3Kg=";
    };

    cargoDeps = final.rustPlatform.importCargoLock {
      lockFile = "${src}/Cargo.lock";
    };

    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace zellij-server/src/screen.rs \
        --replace-fail '.handle_scrollwheel_up(&point, 3, client_id)' \
                       '.handle_scrollwheel_up(&point, ${toString mouseScrollLines}, client_id)' \
        --replace-fail '.handle_scrollwheel_down(&point, 3, client_id)' \
                       '.handle_scrollwheel_down(&point, ${toString mouseScrollLines}, client_id)'
    '';
  });
}
