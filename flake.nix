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
      # Generic Darwin config — works for any username/hostname/arch.
      # Usage: sudo nix run nix-darwin -- switch --flake .#darwin --impure
      # Reads USER, HOME, and the current system from the environment at build
      # time. Fallbacks are provided so `nix flake check --no-build` passes pure
      # evaluation.
      mkDarwin = system: let
        currentUser = let v = builtins.getEnv "USER"; in if v == "" then "nobody" else v;
        currentHome = if currentUser == "nobody" then "/var/empty" else "/Users/${currentUser}";
      in nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          user = currentUser;
          home = currentHome;
          inherit system;
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
              inherit system;
            };
          }
        ];
      };

      # Detect the host's Darwin arch at evaluation time. `--impure` is already
      # required (see install.sh) for USER/HOME, so reading currentSystem here
      # is consistent. Fall back to aarch64-darwin for pure evaluation, where
      # builtins.currentSystem is unavailable.
      currentDarwinSystem = let
        attempt = builtins.tryEval builtins.currentSystem;
        sys = if attempt.success then attempt.value else "aarch64-darwin";
      in if sys == "x86_64-darwin" then "x86_64-darwin" else "aarch64-darwin";
    in
    {
      # Generic Darwin configuration — arch auto-detected from the host.
      darwinConfigurations."darwin" = mkDarwin currentDarwinSystem;

      # Back-compat alias for the original hostname-pinned attribute.
      darwinConfigurations."Mohibs-MacBook-Pro" = mkDarwin currentDarwinSystem;

      # Explicit per-arch aliases for cross-builds, CI, or forcing a target.
      # Usage: sudo nix run nix-darwin -- switch --flake .#darwin-x86_64 --impure
      darwinConfigurations."darwin-aarch64" = mkDarwin "aarch64-darwin";
      darwinConfigurations."darwin-x86_64" = mkDarwin "x86_64-darwin";

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
