# This module is the common base for the NixOS and nix-darwin modules.
# For OS-specific configuration, please edit nixos/default.nix or nix-darwin/default.nix instead.

{
  config,
  lib,
  pkgs,
  _class,
  ...
}:

let
  inherit (lib)
    flip
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  cfg = config.home-manager;

  extendedLib = import ../modules/lib/stdlib-extended.nix lib;

  usersUsingUserPackages = lib.filterAttrs (
    _username: usercfg: usercfg.home.useUserPackages
  ) cfg.users;

  # `defaultOverridePriority` (and its legacy counterpart `defaultPriority`)
  # represents the priority of option definitions that do not explicity specify
  # a priority; that is, definitions of the form `{ foo = "bar"; }`.
  #
  # Setting an option with `mkUserDefault` permits the module system to resolve
  # the so-defined option's priority without evaluating its value.  We use this
  # to define `home.username` and `home.homeDirectory` at the default priority,
  # while also allowing consumers to override these values with `mkForce`, and,
  # crucially, allowing consumers to define `home-manager.users` entries
  # **without those users needing to have corresponding entries in
  # `config.users.users`**.
  #
  # In other respects, `{ foo = mkUserDefault "bar"; }` quacks like
  # `{ foo = "bar"; }`.
  mkUserDefault = lib.mkOverride (lib.modules.defaultOverridePriority or lib.modules.defaultPriority);

  hmModule = types.submoduleWith {
    description = "Home Manager module";
    class = "homeManager";
    specialArgs = {
      lib = extendedLib;
      osConfig = config;
      osClass = _class;
      modulesPath = toString ../modules;
    }
    // cfg.extraSpecialArgs;

    modules = [
      (
        { name, options, ... }@usercfg:
        {
          imports =
            import ../modules/modules.nix {
              inherit pkgs;
              lib = extendedLib;
              inherit (cfg) minimal;
              useNixpkgsModule = !cfg.useGlobalPkgs;
            }
            ++ cfg.sharedModules;

          config = {
            submoduleSupport = {
              enable = true;
              externalPackageInstall = usercfg.config.home.useUserPackages;
            };

            home = {
              uid =
                let
                  # `users.users.<name>.uid` may be declared but unset on
                  # nix-darwin, so probe it with `tryEval` instead of forcing a
                  # no-value-defined error during module evaluation.
                  userUid = builtins.tryEval config.users.users.${name}.uid;
                in
                mkIf (userUid.success && userUid.value != null) (mkUserDefault userUid.value);
              username = mkUserDefault config.users.users.${name}.name;
              homeDirectory = mkUserDefault config.users.users.${name}.home;
            };

            nix = {
              # Forward `nix.enable` from the OS configuration. The
              # conditional is to check whether nix-darwin is new enough
              # to have the `nix.enable` option; it was previously a
              # `mkRemovedOptionModule` error, which we can crudely detect
              # by `visible` being set to `false`.
              enable = mkIf (options.nix.enable.visible or true) config.nix.enable;

              # Make activation script use same version of Nix as system as a whole.
              # This avoids problems with Nix not being in PATH.
              # Only set package when nix is enabled to avoid errors when
              # nix-darwin has nix.enable = false (e.g., Determinate Nix users).
              package = mkIf config.nix.enable config.nix.package;
            };
          };
        }
      )
    ];
  };

in
{
  options.home-manager = {
    useUserPackages = mkEnableOption ''
      the per-user option {option}`home-manager.users.<name>.useUserPackages`
      by default'';

    useGlobalPkgs = mkEnableOption ''
      using the system configuration's `pkgs`
      argument in Home Manager. This disables the Home Manager
      options {option}`nixpkgs.*`'';

    backupCommand = mkOption {
      type = types.nullOr (types.either types.str types.path);
      default = null;
      example = lib.literalExpression "\${pkgs.trash-cli}/bin/trash";
      description = ''
        On activation run this command on each existing file
        rather than exiting with an error.
      '';
    };

    backupFileExtension = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "backup";
      description = ''
        On activation move existing files by appending the given
        file extension rather than exiting with an error.
      '';
    };

    overwriteBackup = mkEnableOption ''
      forced overwriting of existing backup files when using `backupFileExtension`
    '';

    extraSpecialArgs = mkOption {
      type = types.attrs;
      default = { };
      example = lib.literalExpression "{ inherit emacs-overlay; }";
      description = ''
        Extra `specialArgs` passed to Home Manager. This
        option can be used to pass additional arguments to all modules.
      '';
    };

    minimal = mkEnableOption ''
      only the necessary modules that allow home-manager to function.

      This can be used to allow vendoring a minimal list of modules yourself, rather than
      importing every single module.

      THIS IS FOR ADVANCED USERS, AND WILL DISABLE ALMOST EVERY MODULE.
      THIS SHOULD NOT BE ENABLED UNLESS YOU KNOW THE IMPLICATIONS.
    '';

    sharedModules = mkOption {
      type = with types; listOf raw;
      default = [ ];
      example = lib.literalExpression "[ { home.packages = [ nixpkgs-fmt ]; } ]";
      description = ''
        Extra modules added to all users.
      '';
    };

    verbose = mkEnableOption "verbose output on activation";

    enableLegacyProfileManagement = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable legacy profile management during activation. When
        enabled, the Home Manager activation will produce a per-user
        `home-manager` Nix profile, just like in the standalone installation of
        Home Manager. Typically, this is not desired when Home Manager is
        embedded in the system configuration.
      '';
    };

    users = mkOption {
      type = types.attrsOf hmModule;
      default = { };
      # Prevent the entire submodule being included in the documentation.
      visible = "shallow";
      description = ''
        Per-user Home Manager configuration.
      '';
    };
  };

  config = lib.mkMerge [
    # Fix potential recursion when configuring home-manager users based on values in users.users #594
    (mkIf (usersUsingUserPackages != { }) {
      users.users = lib.mapAttrs (_username: usercfg: { packages = [ usercfg.home.path ]; }) usersUsingUserPackages;
      environment.pathsToLink = [ "/etc/profile.d" ];
    })
    (mkIf (cfg.users != { }) {
      warnings = lib.flatten (
        flip lib.mapAttrsToList cfg.users (
          user: config: flip map config.warnings (warning: "${user} profile: ${warning}")
        )
      );

      assertions = lib.flatten (
        flip lib.mapAttrsToList cfg.users (
          user: config:
          flip map config.assertions (assertion: {
            inherit (assertion) assertion;
            message = "${user} profile: ${assertion.message}";
          })
        )
      );
    })
  ];
}
