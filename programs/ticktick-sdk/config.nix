{ config, pkgs, lib, ... }:

{
  # Create TickTick secrets template on activation if it doesn't exist
  home.activation.createTickTickSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f $HOME/.ticktick-secrets ]; then
      $DRY_RUN_CMD cat > $HOME/.ticktick-secrets << 'TICKTICK_EOF'
# TickTick SDK Configuration
#
# IMPORTANT: If your password contains special characters like $ or `, use single quotes
# to prevent shell variable expansion:
#   CORRECT:   export TICKTICK_PASSWORD='$myP@ssw0rd'
#   INCORRECT: export TICKTICK_PASSWORD="$myP@ssw0rd"  # $ will be expanded as a variable!
#
# Alternatively, you can escape the $ with a backslash in double quotes:
#   ALSO CORRECT: export TICKTICK_PASSWORD="\$myP@ssw0rd"
#
# After editing this file, update the MCP configuration with:
#   source ~/.ticktick-secrets && claude mcp remove ticktick && claude mcp add ticktick \
#     -e TICKTICK_CLIENT_ID="\$TICKTICK_CLIENT_ID" \
#     -e TICKTICK_CLIENT_SECRET="\$TICKTICK_CLIENT_SECRET" \
#     -e TICKTICK_ACCESS_TOKEN="\$TICKTICK_ACCESS_TOKEN" \
#     -e TICKTICK_USERNAME="\$TICKTICK_USERNAME" \
#     -e TICKTICK_PASSWORD="\$TICKTICK_PASSWORD" \
#     -e TICKTICK_TIMEOUT="\$TICKTICK_TIMEOUT" \
#     -- ticktick-sdk

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

  # Note: TickTick MCP server should be configured manually using:
  # source ~/.ticktick-secrets && claude mcp add ticktick \
  #   -e TICKTICK_CLIENT_ID="$""{TICKTICK_CLIENT_ID}" \
  #   -e TICKTICK_CLIENT_SECRET="$""{TICKTICK_CLIENT_SECRET}" \
  #   -e TICKTICK_ACCESS_TOKEN="$""{TICKTICK_ACCESS_TOKEN}" \
  #   -e TICKTICK_USERNAME="$""{TICKTICK_USERNAME}" \
  #   -e TICKTICK_PASSWORD="$""{TICKTICK_PASSWORD}" \
  #   -e TICKTICK_TIMEOUT="$""{TICKTICK_TIMEOUT:-30}" \
  #   -- ticktick-sdk
  #
  # This is because ~/.claude.json contains runtime state that shouldn't be
  # managed by home-manager to avoid conflicts.
}
