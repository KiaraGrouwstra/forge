{
  config,
  lib,
  forge-lib,
  packageBuilderModule,
  pkgs,
  ...
}:
{
  imports = [
    ./assertions-warnings.nix
    ./builders/shared
  ];

  options.forge = lib.mkOption {
    type = lib.types.submoduleWith {
      modules = [
        (
          { specialArgs, ... }@forgeArgs:
          {
            options.pkgs = lib.mkOption {
              default = { };
              description = ''
                Packages indexed by their `pname`.

                Each package uses one of the available builders.
                Only one builder can be enabled per package by setting build.<builder>.enable = true.
              '';
              type = lib.types.attrsOf (
                lib.types.submoduleWith {
                  specialArgs = specialArgs // {
                    enable = forgeArgs.config.enable;
                    forgeOptions = forgeArgs.options;
                    inherit packageBuilderModule;
                  };
                  modules = [
                    ./pkgs/pkg.nix
                  ];
                }
              );
            };
          }
        )
      ];
    };
  };

  # Config section is now provided by builder modules
  config =
    let
      packagesWithNamespace = pkgs.callPackage (forge-lib.flakePackagesWithNamespace {
        namespace = "pkgs";
        derivations = lib.mapAttrs (packageName: package: package.result.derivation) (
          lib.filterAttrs (_: pkg: !pkg.broken && pkg.enable) config.forge.pkgs
        );
      }) { };
    in
    {
      inherit (packagesWithNamespace) packages;

      # Collect warnings from forge.pkgs
      warnings = lib.pipe config.forge.pkgs [
        (lib.attrValues)
        (map (x: x.warnings))
        (lib.flatten)
      ];

      # Collect assertions from forge.pkgs
      assertions = lib.pipe config.forge.pkgs [
        (lib.attrValues)
        (map (x: x.assertions))
        (lib.flatten)
      ];

      # Evaluation check: show warnings first, then throw on failed assertions
      _module.check = import ./check-assertions-warnings.nix { inherit lib; } {
        inherit (config) assertions warnings;
      } true;
    };
}
