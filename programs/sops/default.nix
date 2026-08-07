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
          .mcpServers["agent-mail"] = {
            type: "http",
            url: "http://127.0.0.1:8765/api/",
            headers: { Authorization: $val }
          }
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

    # ── Playwright MCP (no secret needed) ──
    {
      sopsKey = null;
      description = "Playwright MCP server";
      script = ''
        ${pkgs.jq}/bin/jq '
          .mcpServers["playwright"] = {
            command: "npx",
            args: ["-y", "@playwright/mcp@latest"]
          }
        ' "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
      '';
    }

    # ── Slack MCP (no secret needed) ──
    # Slack's official remote server authenticates over OAuth on first use, so
    # no token belongs in this config. Run `/mcp` in Claude Code to authorize.
    {
      sopsKey = null;
      description = "Slack MCP server";
      script = ''
        ${pkgs.jq}/bin/jq '
          .mcpServers["slack"] = {
            type: "http",
            url: "https://mcp.slack.com/mcp"
          }
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

  # Split patches into secret-dependent and non-secret
  secretPatches = builtins.filter (p: p.sopsKey != null) patches;
  nonSecretPatches = builtins.filter (p: p.sopsKey == null) patches;

  # Generate scripts
  secretPatchScript = lib.concatMapStringsSep "\n" (patch: ''
    VAL=$(echo "$SECRETS_JSON" | ${pkgs.jq}/bin/jq -r '.${patch.sopsKey}')
    if [ -n "$VAL" ] && [ "$VAL" != "null" ]; then
      ${patch.script}
      echo "  ${patch.description}"
    fi
  '') secretPatches;

  nonSecretPatchScript = lib.concatMapStringsSep "\n" (patch: ''
    ${patch.script}
    echo "  ${patch.description}"
  '') nonSecretPatches;

in
{
  home.packages = [
    (pkgs.writeShellScriptBin "hm-secrets" ''
      set -euo pipefail
      SOPS_FILE="$(cd ~/src/workspace && pwd)/programs/sops/secrets.yaml"
      export SOPS_AGE_KEY_FILE="${ageKeyFile}"

      BOLD=$'\033[1m'
      DIM=$'\033[2m'
      GREEN=$'\033[32m'
      YELLOW=$'\033[33m'
      RED=$'\033[31m'
      CYAN=$'\033[36m'
      RESET=$'\033[0m'

      ok()   { echo "''${GREEN}''${BOLD}ok''${RESET} $*"; }
      warn() { echo "''${YELLOW}''${BOLD}!!''${RESET} $*"; }
      err()  { echo "''${RED}''${BOLD}err''${RESET} $*" >&2; exit 1; }

      case "''${1:-help}" in
        edit)
          cd ~/src/workspace && ${pkgs.sops}/bin/sops "$SOPS_FILE"
          ;;
        show)
          ${pkgs.sops}/bin/sops --decrypt "$SOPS_FILE"
          ;;
        list)
          ${pkgs.sops}/bin/sops --decrypt --output-type json "$SOPS_FILE" | \
            ${pkgs.jq}/bin/jq -r 'keys[]'
          ;;
        set)
          [ -z "''${2:-}" ] && err "Usage: hm-secrets set <key> [value]"
          KEY="$2"
          if [ -n "''${3:-}" ]; then
            VALUE="$3"
          else
            echo -n "''${DIM}Enter value for ''${RESET}''${BOLD}$KEY''${RESET}''${DIM}: ''${RESET}"
            read -rs VALUE
            echo ""
          fi
          cd ~/src/workspace && ${pkgs.sops}/bin/sops --set "[\"$KEY\"] \"$VALUE\"" "$SOPS_FILE"
          ok "Updated ''${BOLD}$KEY''${RESET}"
          warn "Run ''${CYAN}hm-secrets apply''${RESET} to activate"
          ;;
        remove)
          [ -z "''${2:-}" ] && err "Usage: hm-secrets remove <key>"
          KEY="$2"
          cd ~/src/workspace
          ${pkgs.sops}/bin/sops --decrypt --output-type json "$SOPS_FILE" | \
            ${pkgs.jq}/bin/jq "del(.[\"$KEY\"])" | \
            ${pkgs.yq}/bin/yq -y '.' > "$SOPS_FILE.plain"
          cp "$SOPS_FILE.plain" "$SOPS_FILE"
          rm "$SOPS_FILE.plain"
          ${pkgs.sops}/bin/sops --encrypt --in-place "$SOPS_FILE"
          ok "Removed ''${BOLD}$KEY''${RESET}"
          ;;
        test)
          echo ""
          echo "  ''${BOLD}hm-secrets test''${RESET}"
          echo ""

          # 1. Key file exists
          if [ ! -f "${ageKeyFile}" ]; then
            err "age key not found at ${ageKeyFile}
  Run:  mkdir -p ~/.config/sops/age && age-keygen -o ${ageKeyFile}"
          fi
          ok "key file exists"

          # 2. File contains a valid AGE-SECRET-KEY line
          if ! ${pkgs.gnugrep}/bin/grep -q '^AGE-SECRET-KEY-' "${ageKeyFile}"; then
            err "${ageKeyFile} does not contain a valid AGE-SECRET-KEY"
          fi
          ok "valid age secret key"

          # 3. Derive public key and check it matches .sops.yaml
          DERIVED_PUB=$(${pkgs.age}/bin/age-keygen -y "${ageKeyFile}" 2>/dev/null)
          EXPECTED_PUB="age1p8r7v8ukr8yc2e8823x3jedug94rjx2juraw47n8nn79mcpt6peq5swrv4"
          if [ "$DERIVED_PUB" != "$EXPECTED_PUB" ]; then
            err "public key mismatch — private key doesn't match .sops.yaml
  Expected: $EXPECTED_PUB
  Got:      $DERIVED_PUB"
          fi
          ok "public key matches .sops.yaml"

          # 4. Can decrypt the secrets file (only the key count escapes the pipe)
          if ! KEY_COUNT=$(${pkgs.sops}/bin/sops --decrypt --output-type json "$SOPS_FILE" 2>/dev/null | ${pkgs.jq}/bin/jq 'keys | length'); then
            err "could not decrypt $SOPS_FILE"
          fi
          ok "decryption works ''${DIM}($KEY_COUNT secret(s))''${RESET}"

          echo ""
          ;;
        apply)
          echo "''${DIM}Rebuilding...''${RESET}"
          cd ~/src/workspace && bash install.sh
          ;;
        help|*)
          echo ""
          echo "  ''${BOLD}hm-secrets''${RESET} ''${DIM}- encrypted secrets for home-manager''${RESET}"
          echo ""
          echo "  ''${BOLD}Commands''${RESET}"
          echo "    ''${CYAN}edit''${RESET}            Open in \$EDITOR ''${DIM}(decrypts, re-encrypts on save)''${RESET}"
          echo "    ''${CYAN}show''${RESET}            Print all decrypted secrets"
          echo "    ''${CYAN}list''${RESET}            List secret key names ''${DIM}(no values)''${RESET}"
          echo "    ''${CYAN}set''${RESET} ''${DIM}<key> [val]''${RESET}  Set a secret ''${DIM}(prompts if value omitted)''${RESET}"
          echo "    ''${CYAN}remove''${RESET} ''${DIM}<key>''${RESET}     Remove a secret"
          echo "    ''${CYAN}test''${RESET}            Verify age key is set, valid, and can decrypt"
          echo "    ''${CYAN}apply''${RESET}           Rebuild to activate changes"
          echo ""
          echo "  ''${BOLD}Files''${RESET}"
          echo "    ''${DIM}secrets''${RESET}  $SOPS_FILE"
          echo "    ''${DIM}age key''${RESET}  ${ageKeyFile}"
          echo ""
          ;;
      esac
    '')
  ];

  # Activation: apply non-secret patches always, secret patches when decryptable
  home.activation.applySecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Applying MCP patches..."
    ${nonSecretPatchScript}

    if [ ! -f "${ageKeyFile}" ] || [ ! -f "${sopsFile}" ]; then
      echo "Skipping secrets: age key or sops file not found"
    else
      export SOPS_AGE_KEY_FILE="${ageKeyFile}"
      SECRETS_JSON=$(${pkgs.sops}/bin/sops --decrypt --output-type json "${sopsFile}" 2>/dev/null || echo "{}")

      if [ "$SECRETS_JSON" != "{}" ]; then
        echo "Applying secrets..."
        ${secretPatchScript}
        echo "Secrets applied."
      else
        echo "Warning: could not decrypt secrets"
      fi
    fi
  '';
}
