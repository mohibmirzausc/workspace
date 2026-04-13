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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, sops-nix, ... }:
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
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
            home-manager.extraSpecialArgs = {
              user = "mohib";
              home = "/Users/mohib";
            };
          }
        ];
      };

      # Generic Linux home-manager config — works for any username.
      # Usage: home-manager switch --flake .#linux
      # Reads USER and HOME from the environment at build time.
      homeConfigurations."linux" = let
        currentUser = builtins.getEnv "USER";
        currentHome = builtins.getEnv "HOME";
      in home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        modules = [
          ./home.nix
          sops-nix.homeManagerModules.sops
        ];
        extraSpecialArgs = {
          user = currentUser;
          home = currentHome;
        };
      };
    };
}
