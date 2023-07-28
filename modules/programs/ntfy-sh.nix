{ config, lib, options, pkgs, ... }:

let
  inherit (lib) mkOption types;

  cfg = config.programs.ntfy-sh;
  opts = options.programs.ntfy-sh;

  utils = import "${toString pkgs.path}/nixos/lib/utils.nix" {
    inherit lib pkgs;
    config = { };
  };

  jsonFormat = pkgs.formats.json { };

  # A type that looks like the supplied type but also accepts functions.
  # Functions are not serializable as JSON; we can use this to filter out
  # omitted/undefined types from the user-supplied configuration, and do so
  # *without* making legal values (like `null`) unusable.
  unserializableType = types.functionTo types.raw;
  omittableType = type:
    (types.either type unserializableType) // {
      inherit (type) description descriptionClass name;
    };

  mkOmittableOption =
    { type, default ? (lib.const null), defaultText ? "<omitted>", ... }@args:
    mkOption args // {
      inherit default;
      type = omittableType type;
    };

  mkExampleFromSubOptions = subOptions:
    let
      filtered =
        lib.filterAttrs (name: _: !(lib.hasPrefix "_" name)) subOptions;
    in lib.mapAttrs (name: value: value.example) filtered;

  mkExampleFromSubmodule = type:
    mkExampleFromSubOptions (type.getSubOptions { });

  commandType = types.nullOr
    (types.coercedTo (types.nonEmptyListOf types.str) lib.escapeShellArgs
      types.nonEmptyStr);

  filterType = types.nullOr
    (types.coercedTo (types.listOf types.str) (lib.concatStringsSep ",")
      (types.separatedString ","));

  conditionType = types.submodule ({ config, options, ... }: {
    # Escape hatch in case this module doesn't capture all available `if`
    # settings for a given `ntfy` release.
    freeformType = jsonFormat.type;

    options = {
      id = mkOmittableOption {
        type = types.nullOr types.nonEmptyStr;
        description = ''
          Match only messages that have this exact message ID.
        '';
        example = "pbkiz8SD7ZxG";
      };

      title = mkOmittableOption {
        type = types.nullOr types.nonEmptyStr;
        description = ''
          Match only messages that have this exact title string.
        '';
        example = "oh dear :(";
      };

      message = mkOmittableOption {
        type = types.nullOr types.nonEmptyStr;
        description = ''
          Match only messages that have this exact message string.
        '';
        example = "not again...";
      };

      # https://github.com/binwiederhier/ntfy/blob/0ab61719626cdca933512db118ebbd6772096818/util/util.go#L148-L187
      priority = mkOmittableOption {
        type = let
          intType = types.ints.between 0 5;
          strings = [ "default" "min" "low" "default" "high" "max" "urgent" ];
          stringType = types.enum strings;
        in types.coercedTo intType (lib.elemAt strings) stringType;
        description = ''
          Match only messages that have _any_ of the given priorities.
        '';
        example = [ "high" "urgent" ];
      };

      tags = mkOmittableOption {
        type = filterType;
        description = ''
          Match only messages that have _all_ of the given tags.
        '';
        example = [ "alert" "error" ];
      };
    };
  });

  subscriptionType = types.submodule ({ name, config, options, ... }: {
    # Escape hatch in case this module doesn't capture all available
    # `subscribe` settings for a given `ntfy` release.
    freeformType = jsonFormat.type;

    options = {
      topic = mkOmittableOption {
        type = lib.hm.types.secretOr types.nonEmptyStr;
        default = name;
        description = ''
          Name of the notification topic -- the unique textual identifier of a
          feed of notifications.

          ::: {.tip}
          As a convenience, {option}`topic` defaults to the corresponding
          attribute name in the {option}`subscribe` attribute set.  However,
          quoting the landing page of <https://docs.ntfy.sh/>: "topic names are
          public, so it's wise to choose something that cannot be guessed
          easily." If you'd like to avoid leaking your topic name into the Nix
          store, instead enable {option}`enableSecretsReplacement` and declare
          the topic using `{ _secret = "/path/containing/topic"; }`, which will
          set the topic name to the contents of {file}`/path/containing/topic`.
          :::
        '';
        example = {
          _secret = "/topics/are/public/so/choose/one/that/is/tough/to/guess";
        };
      };

      token = tokenOption { };
      user = userOption { };
      password = passwordOption { };
      command = commandOption { };

      condition = mkOption {
        type = conditionType;
        default = { };
        description = ''
          Criteria for selecting or rejecting notifications within the given
          topic.

          See <https://docs.ntfy.sh/subscribe/api/#filter-messages>.
        '';
        example = mkExampleFromSubmodule options.condition.type;
      };
    };
  });

  tokenOption = { description ? "" }:
    mkOmittableOption {
      type = types.nullOr (lib.hm.types.secretOr types.str);
      example = { _secret = "/store/tokens/somewhere/safe"; };
      description = ''
        Access token for authenticating with the `ntfy` server when running
        {command}`ntfy publish` and {command}`ntfy subscribe`.

        See <https://docs.ntfy.sh/config/#access-tokens> for information on
        creating tokens and <https://docs.ntfy.sh/publish/#access-tokens> for
        information on using them.
      '' + description;
    };

  userOption = { description ? "" }:
    mkOmittableOption {
      type = types.nullOr (lib.hm.types.secretOr types.str);
      description = ''
        Authentication username to use with {command}`ntfy publish` and
        {command}`ntfy subscribe`.
      '' + description;
      example = "my-user";
    };

  passwordOption = { description ? "" }:
    mkOmittableOption {
      type = types.nullOr (lib.hm.types.secretOr types.str);
      description = ''
        Authentication password to use with {command}`ntfy publish` and
        {command}`ntfy subscribe`.  For an empty password, use empty
        double-quotes (`""`).
      '' + description;
      example = { _secret = "/file/containing/the/password"; };
    };

  commandOption = { description ? "" }:
    mkOmittableOption {
      type = commandType;
      description = ''
        Command to run in response to incoming messages.  See
        <https://docs.ntfy.sh/subscribe/cli/#run-command-for-every-message>,
        which includes a specification of the message fields passed to the
        command as environment variables.

        Note that commands are interpreted by a shell.

        Leaving this option undefined will cause {command}`ntfy subscribe` to
        print incoming messages as JSON objects.
      '' + description;
      example = ''
        notify-send "Received message: $m"
      '';
    };
in {
  meta.maintainers = [ lib.hm.maintainers.tomeon ];

  options.programs.ntfy-sh = {
    enable = lib.mkEnableOption "the ntfy.sh client program";

    package = lib.mkPackageOption pkgs "ntfy-sh" { };

    shell = mkOption {
      type = types.shellPackage;
      default = pkgs.stdenv.shellPackage;
      defaultText = "pkgs.stdenv.shellPackage";
      description = ''
        Package providing an implementation of `sh` for use with the `ntfy` CLI
        client.

        This is required for running commands in response to incoming messages.
      '';
    };

    enableSecretsReplacement = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When enabled, all instances of `{ _secret = "/path/to/secret"; }` in
        {option}`settings` will be replaced with the contents of the file
        {file}`/path/to/secret` in the output JSON.
      '';
    };

    settings = mkOption {
      default = { };
      description = ''
        Settings for the `ntfy` CLI client.

        ::: {.tip}
        When {option}`enableSecretsReplacement` is enabled, some settings
        (e.g., usernames, passwords, and topic names) support secrets
        replacement: instead of defining (say) a literal password, you may do
        `{ default-password = { _secret = "/path/to/password/file"; }; }` and,
        in the generated configuration file, {option}`default-password` will be
        set to the contents of {file}`/path/to/password/file`.
        :::
      '';
      example = mkExampleFromSubmodule opts.settings.type;
      type = types.submodule ({ config, options, ... }: {
        # Escape hatch in case this module doesn't capture all available
        # settings for a given `ntfy` release.
        freeformType = jsonFormat.type;

        options = let
          wrapOption = opt: fn:
            fn {
              description = ''

                This is the default ${opt} `ntfy` uses when not overridden by
                {option}`${opt}` in a particular topic subscription.
              '';
            };
        in {
          default-token = wrapOption "token" tokenOption;
          default-user = wrapOption "user" userOption;
          default-password = wrapOption "password" passwordOption;
          default-command = wrapOption "command" commandOption;

          default-host = mkOmittableOption {
            type = types.nullOr (lib.hm.types.secretOr types.nonEmptyStr);
            description = ''
              Base URL used to expand short topic names in the {command}`ntfy
              publish` and {command}`ntfy subscribe` commands.  If you
              self-host a `ntfy` server, you'll likely want to change this.
            '';
            example = "https://ntfy.local.net";
          };

          subscribe = mkOption {
            type = types.attrsOf subscriptionType;
            default = { };
            description = ''
              Attribute set specifying topic subscriptions.
            '';
            example = let
              subOptions =
                options.subscribe.type.nestedTypes.elemType.getSubOptions { };
            in {
              just-log-json = { topic = subOptions.topic.example; };

              private-instance = {
                topic = "https://ntfy.pet.rocks/miscellaneous";
                command = ''
                  printf -- '[%s] [id=%s] [priority=%d] [tags=%s] %s: %s\n' \
                    "$(date +'%F-%t')" \
                    "$id" "$priority" "$tags" \
                    "$title" "$message"
                '';
              };

              full-example = mkExampleFromSubOptions subOptions;
            };
          };
        };
      });
    };

    config = mkOption {
      type = jsonFormat.type;
      internal = true;
      readOnly = true;
      default = let
        serializable =
          lib.filterAttrsRecursive (_: value: !(unserializableType.check value))
          cfg.settings;
      in serializable // {
        subscribe = map (subscription:
          let
            condition = subscription.condition or { };
            tags = subscription.priority or [ ];
          in (builtins.removeAttrs subscription [ "condition" ])
          // lib.optionalAttrs (condition != { }) { "if" = condition; }
          // lib.optionalAttrs (tags != [ ]) {
            tags = lib.concatStringsSep "," tags;
          }) (builtins.attrValues serializable.subscribe);
      };

      description = ''
        The final `ntfy` configuration to be serialized as YAML.
      '';
    };

    # The `ntfy` CLI client requires `sh` for executing the commands specified
    # under `subscribe`; prepend our `sh` wrapper to `PATH`.
    wrapper = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      default = pkgs.writeShellScriptBin "ntfy" ''
        PATH=${cfg.shellWrapper}/bin"''${PATH:+:''${PATH}}" exec ${cfg.package}/bin/ntfy "$@"
      '';
    };

    # Ensure that the selected shell appears as `sh` in PATH within the wrapper
    # script, above.
    shellWrapper = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      default = pkgs.runCommand "ntfy-shell-wrapper" { } ''
        mkdir -p "$out/bin"
        ${pkgs.coreutils}/bin/ln -s ${cfg.shell}/${
          lib.escapeShellArg cfg.shell.shellPath
        } "$out/bin/sh"
      '';
    };

    configFileName = mkOption {
      type = types.nonEmptyStr;
      internal = true;
      readOnly = true;
      default = "client.yml";
    };

    configFile = mkOption {
      type = types.path;
      internal = true;
      readOnly = true;
      default = jsonFormat.generate cfg.configFileName cfg.config;
    };

    writeConfig = mkOption {
      type = types.path;
      internal = true;
      readOnly = true;
      default = pkgs.writeShellScript "write-ntfy-sh-config" ''
        set -euo pipefail

        if (( "$#" != 1 )); then
          printf 1>&2 -- 'Usage: %s <config-output-directory>' "$0"
          exit 1
        fi

        umask 027

        ${pkgs.coreutils}/bin/install -dm0750 "$1"

        cd "$1"

        ${lib.optionalString cfg.enableSecretsReplacement
        (utils.genJqSecretsReplacementSnippet cfg.config cfg.configFileName)}

        ${lib.optionalString (!cfg.enableSecretsReplacement) ''
          ${pkgs.coreutils}/bin/install -Dm0640 ${
            lib.escapeShellArgs [ cfg.configFile cfg.configFileName ]
          }
        ''}
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.wrapper ];

    home.activation.ntfy-sh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${cfg.writeConfig} "$XDG_CONFIG_HOME/ntfy"
    '';
  };
}
