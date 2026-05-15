{ config, pkgs, lib, ... }:

{
  # Create TickTick secrets template on activation if it doesn't exist
  home.activation.createTickTickSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f $HOME/.ticktick-secrets ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/printf '%s\n' \
        'export TICKTICK_CLIENT_ID="your_client_id_here"' \
        'export TICKTICK_CLIENT_SECRET="your_client_secret_here"' \
        'export TICKTICK_REDIRECT_URI="http://127.0.0.1:8080/callback"' \
        'export TICKTICK_ACCESS_TOKEN=""' \
        'export TICKTICK_USERNAME="your_email@example.com"' \
        'export TICKTICK_PASSWORD="your_password"' \
        'export TICKTICK_TIMEOUT="30"' \
        > $HOME/.ticktick-secrets
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 600 $HOME/.ticktick-secrets
      echo "Created ~/.ticktick-secrets template. Please edit it with your real credentials."
    fi
  '';
}

