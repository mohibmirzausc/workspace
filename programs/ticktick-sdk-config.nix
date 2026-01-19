{ config, pkgs, lib, ... }:

{
  # Create TickTick secrets template on activation if it doesn't exist
  home.activation.createTickTickSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f $HOME/.ticktick-secrets ]; then
      $DRY_RUN_CMD cat > $HOME/.ticktick-secrets << 'TICKTICK_EOF'
export TICKTICK_CLIENT_ID="your_client_id_here"
export TICKTICK_CLIENT_SECRET="your_client_secret_here"
export TICKTICK_REDIRECT_URI="http://127.0.0.1:8080/callback"
export TICKTICK_ACCESS_TOKEN=""
export TICKTICK_USERNAME="your_email@example.com"
export TICKTICK_PASSWORD="your_password"
export TICKTICK_TIMEOUT="30"
TICKTICK_EOF
      $DRY_RUN_CMD chmod 600 $HOME/.ticktick-secrets
      echo "Created ~/.ticktick-secrets template. Please edit it with your real credentials."
    fi
  '';
}

