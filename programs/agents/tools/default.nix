# CLI tools for coding agents, paired with skills in ../skills/.
#
# These exist to replace MCP servers where the service is a plain REST API.
# An MCP server pays for its tool definitions in every request; a CLI plus a
# skill is read only when relevant. The Shortcut MCP server alone registers
# ~45 tools (~11k-29k tokens per request).
#
# Each tool reads its credentials from the sops store at call time, so no
# plaintext token is written to a config file. See ../../sops/default.nix.
{ pkgs }:

{
  sc = pkgs.writeShellApplication {
    name = "sc";
    runtimeInputs = with pkgs; [ curl jq sops ];
    text = builtins.readFile ./sc.sh;
  };
}
