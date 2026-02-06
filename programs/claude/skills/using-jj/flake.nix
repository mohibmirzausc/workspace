{
  description = "jj-tool: TypeScript API for Jujutsu version control";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # TypeScript/JavaScript
            bun

            # Jujutsu VCS (required for API)
            jujutsu

            # Development tools
            git
            tree
            just
          ];

          shellHook = ''
            echo "🚀 jj-tool development environment"
            echo "Bun version: $(bun --version)"
            echo "jj version: $(jj --version)"
            echo ""
            echo "Available commands:"
            echo "  bun test   - Run TypeScript tests"
            echo "  bun run -  - Execute TypeScript code (pipe from stdin)"
          '';
        };
      }
    );
}
