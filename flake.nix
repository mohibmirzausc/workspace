{
  description = "Darwin system configuration for mohib";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-overlay = {
      url = "github:ryoppippi/claude-code-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, claude-code-overlay, ... }:
    {
      # Darwin configuration for macOS
      darwinConfigurations."Mohibs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            nixpkgs.overlays = [ claude-code-overlay.overlays.default ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.mohib = import ./home.nix;
            home-manager.extraSpecialArgs = {
              user = "mohib";
              home = "/Users/mohib";
            };
          }
        ];
      };

      # Keep standalone home-manager config for Linux (coder)
      homeConfigurations."coder" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        modules = [ ./home.nix ];
        extraSpecialArgs = {
          user = "coder";
          home = "/home/coder";
        };
      };

      homeConfigurations."mohib" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        modules = [ ./home.nix ];
        extraSpecialArgs = {
          user = "mohib";
          home = "/home/mohib";
        };
      };
    };
}
