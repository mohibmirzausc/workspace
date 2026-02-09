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
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, pyproject-nix, uv2nix, pyproject-build-systems, ... }:
    {
      # Darwin configuration for macOS
      darwinConfigurations."Mohibs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.mohib = import ./home.nix;
            home-manager.extraSpecialArgs = {
              user = "mohib";
              home = "/Users/mohib";
              inherit pyproject-nix uv2nix pyproject-build-systems;
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
          inherit pyproject-nix uv2nix pyproject-build-systems;
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
          inherit pyproject-nix uv2nix pyproject-build-systems;
        };
      };
    };
}
