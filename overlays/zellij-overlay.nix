{ mouseScrollLines ? 1 }:

final: prev: {
  zellij = prev.zellij.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace zellij-server/src/tab/mod.rs \
        --replace-fail 'self.handle_scrollwheel_up(&event.position, 3, client_id)' \
                       'self.handle_scrollwheel_up(&event.position, ${toString mouseScrollLines}, client_id)' \
        --replace-fail 'self.handle_scrollwheel_down(&event.position, 3, client_id)' \
                       'self.handle_scrollwheel_down(&event.position, ${toString mouseScrollLines}, client_id)'
    '';
  });
}
