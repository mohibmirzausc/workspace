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
    let
      # Generic Darwin config — works for any username/hostname.
      # Usage: sudo nix run nix-darwin -- switch --flake .#darwin --impure
      # Reads USER and HOME from the environment at build time.
      # Fallbacks are provided so `nix flake check --no-build` passes pure evaluation.
      mkDarwin = system: let
        currentUser = let v = builtins.getEnv "USER"; in if v == "" then "nobody" else v;
        currentHome = if currentUser == "nobody" then "/var/empty" else "/Users/${currentUser}";
      in nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          user = currentUser;
          home = currentHome;
        };
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.users.${currentUser} = import ./home.nix;
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
            home-manager.extraSpecialArgs = {
              user = currentUser;
              home = currentHome;
            };
          }
        ];
      };
    in
    {
      # Generic Darwin configuration — username/home read from environment at build time.
      darwinConfigurations."darwin" = mkDarwin "aarch64-darwin";

      # Back-compat alias for the original hostname-pinned attribute.
      darwinConfigurations."Mohibs-MacBook-Pro" = mkDarwin "aarch64-darwin";

      # Generic Linux home-manager config — works for any username.
      # Usage: home-manager switch --flake .#linux --impure
      # Reads USER and HOME from the environment at build time.
      # Fallbacks are provided so `nix flake check --no-build` passes pure evaluation.
      homeConfigurations."linux" = let
        currentUser = let v = builtins.getEnv "USER"; in if v == "" then "nobody" else v;
        currentHome = let v = builtins.getEnv "HOME"; in if v == "" then "/homeless-shelter" else v;
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
