{
  config,
  lib,
  pkgs,
  self-inputs,
  forge-inputs,
  forge-lib,
  system,
  ...
}:
{
  options.forge = lib.mkOption {
    description = "Module-system framework for building packages and apps (eg. NixOS VMs, or Podman containers) using those packages.";
    default = { };
    type = lib.types.submoduleWith {
      specialArgs = {
        inherit system;
        forgeConfig = config;
        inputs = self-inputs;
        inherit forge-inputs;
        inherit forge-lib;
        pkgs = pkgs.extend (
          finalPkgs: previousPkgs:
          # Extend `pkgs` with the packages from the forge.
          lib.mapAttrs (packageName: package: package.result.derivation) config.forge.pkgs
          // {
            # `pkgs.pkgsOriginal` provides packages from the original `pkgs` (usually from Nixpkgs)
            # Eg. `pkgs.pkgsOriginal.offen` (Nixpkgs) and `pkgs.offen` (ngi-forge).
            # Note that as a consequence, all dependencies of those packages
            # remain those coming from the original `pkgs`,
            # even when they happen to also be packaged in the forge.
            pkgsOriginal = previousPkgs;
          }
        );
        lib = lib // {
          maintainers =
            (import "${forge-inputs.nixpkgs}/maintainers/maintainer-list.nix")
            // lib.foldl' (acc: path: acc // import path) { } config.forge.maintainerLists;
        };
      };
      modules = [
        {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether to expose applications and packages by default in flake's `packages`.
                If set it also expose internal packages within `_forge` in `packages`.
              '';
            };
            maintainerLists = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [ forge-inputs.self.maintainerList ];
              defaultText = lib.literalExpression "[ inputs.ngi-forge.maintainerList ]";
              description = ''
                Paths to files containing a list of Forge maintainers.
                Each file must follow the format of the
                [Nixpkgs maintainer-list.nix file](https://github.com/NixOS/nixpkgs/blob/master/maintainers/maintainer-list.nix).'';
              example = lib.literalExpression ''
                [ inputs.ngi-forge.maintainerList
                ./maintainers/maintainer-list.nix ]
              '';
            };

            repositoryUrl = lib.mkOption {
              type = lib.types.str;
              default = "github:ngi-nix/forge";
              example = "github:ngi-nix/forge";
              description = "URL of the Forge repository.";
            };

            appCategories = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {
                chat = "Chat & email";
                documents = "Documents, office & publishing";
                collaboration = "Collaboration";
                multimedia = "Graphics, video & audio";
                web = "Web & browsing";
                maps = "Maps & location";
                science = "Science & data analysis";
                electronics = "Electronics & hardware design";
                engineering = "Engineering & CAD";
                security = "Security, privacy & cryptography";
                networking = "Networking & internet infrastructure";
                development = "Programming languages & dev tools";
                code-analysis = "Code & binary analysis";
                system = "System, files & storage";
              };
              description = ''
                Categories that applications can use in `apps.<name>.categories`.
                Each attribute name is a category identifier and each value is the label that the UI shows.
              '';
              example = {
                games = "Games";
              };
            };

            snippets = lib.mkOption {
              readOnly = true;
              type = lib.types.submodule ./snippets.nix;
              default = { };
              description = "Re-usable snippets in Markdown format.";
            };
          };
        }
      ];
    };
  };
}
