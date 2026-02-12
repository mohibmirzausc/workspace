{ config, pkgs, lib, home, ... }:

let
  sopsFile = ./secrets.yaml;
  ageKeyFile = "${home}/.config/sops/age/keys.txt";

  # ── Secret patches ─────────────────────────────────────────
  # Each patch reads a key from the decrypted secrets JSON
  # and runs a shell command with the value.
  #
  # To add a new secret:
  #   1. hm-secrets set <key> <value>
  #   2. Add a patch entry below
  #   3. bash install.sh
  patches = [
    # ── Claude MCP servers ──
    {
      sopsKey = "agent_mail_bearer_token";
      description = "agent-mail MCP bearer token";
      script = ''
        ${pkgs.jq}/bin/jq --arg val "Bearer $VAL" '
          if .mcpServers["agent-mail"] then
            .mcpServers["agent-mail"].headers.Authorization = $val
          else . end
        ' "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
      '';
    }
    {
      sopsKey = "shortcut_api_token";
      description = "Shortcut MCP API token";
      script = ''
        ${pkgs.jq}/bin/jq --arg val "$VAL" '
          .mcpServers["shortcut"] = {
            command: "npx",
            args: ["-y", "@shortcut/mcp@0.19.0"],
            env: { SHORTCUT_API_TOKEN: $val }
          }
          # Remove redundant project-level shortcut configs
          | if .projects then
              .projects |= with_entries(
                .value.mcpServers |= (if . then del(.shortcut) else . end)
              )
            else . end
        ' "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
      '';
    }

    # ── Other secrets ──
    # Example: write a dotfile with secrets
    # {
    #   sopsKey = "ticktick_client_id";
    #   description = "TickTick client ID";
    #   script = ''
    #     sed -i '' "s|your_client_id_here|$VAL|" "$HOME/.ticktick-secrets"
    #   '';
    # }
    #
    # Example: write a secret to a file
    # {
    #   sopsKey = "some_api_key";
    #   description = "Some API key";
    #   script = ''
    #     echo "$VAL" > "$HOME/.config/some-tool/api-key"
    #     chmod 600 "$HOME/.config/some-tool/api-key"
    #   '';
    # }
  ];

  # Generate the activation script from patches
  patchScript = lib.concatMapStringsSep "\n" (patch: ''
    VAL=$(echo "$SECRETS_JSON" | ${pkgs.jq}/bin/jq -r '.${patch.sopsKey}')
    if [ -n "$VAL" ] && [ "$VAL" != "null" ]; then
      ${patch.script}
      echo "  ${patch.description}"
    fi
  '') patches;

in
{
  home.packages = [
    (pkgs.writeShellScriptBin "hm-secrets" ''
      set -euo pipefail
      SOPS_FILE="$(cd ~/src/workspace && pwd)/programs/sops/secrets.yaml"
      export SOPS_AGE_KEY_FILE="${ageKeyFile}"

      case "''${1:-help}" in
        edit)
          cd ~/src/workspace && ${pkgs.sops}/bin/sops "$SOPS_FILE"
          ;;
        show)
          ${pkgs.sops}/bin/sops --decrypt "$SOPS_FILE"
          ;;
        set)
          if [ -z "''${2:-}" ]; then
            echo "Usage: hm-secrets set <key> [value]"
            echo "If value is omitted, reads from stdin (avoids shell history)."
            exit 1
          fi
          KEY="$2"
          if [ -n "''${3:-}" ]; then
            VALUE="$3"
          else
            echo -n "Enter value for $KEY: "
            read -rs VALUE
            echo ""
          fi
          cd ~/src/workspace && ${pkgs.sops}/bin/sops --set "[\"$KEY\"] \"$VALUE\"" "$SOPS_FILE"
          echo "Updated $KEY. Run 'bash ~/src/workspace/install.sh' to apply."
          ;;
        apply)
          echo "Re-running install..."
          cd ~/src/workspace && bash install.sh
          ;;
        help|*)
          echo "hm-secrets - manage encrypted secrets for home-manager"
          echo ""
          echo "Commands:"
          echo "  edit     Open secrets in \$EDITOR (decrypts, re-encrypts on save)"
          echo "  show     Print decrypted secrets to stdout"
          echo "  set K V  Set a single key (e.g. hm-secrets set shortcut_api_token NEW_TOKEN)"
          echo "  apply    Run install.sh to apply secrets"
          echo ""
          echo "Secrets file: $SOPS_FILE"
          echo "Age key:      ${ageKeyFile}"
          ;;
      esac
    '')
  ];

  # Activation: decrypt all secrets once, apply all patches
  home.activation.applySecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "${ageKeyFile}" ] || [ ! -f "${sopsFile}" ]; then
      echo "Skipping secrets: age key or sops file not found"
    else
      export SOPS_AGE_KEY_FILE="${ageKeyFile}"
      SECRETS_JSON=$(${pkgs.sops}/bin/sops --decrypt --output-type json "${sopsFile}" 2>/dev/null || echo "{}")

      if [ "$SECRETS_JSON" != "{}" ]; then
        echo "Applying secrets..."
        ${patchScript}
        echo "Secrets applied."
      else
        echo "Warning: could not decrypt secrets"
      fi
    fi
  '';
}
