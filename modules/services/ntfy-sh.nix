{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  cfg = config.services.ntfy-sh;
  prog = config.programs.ntfy-sh;
in {
  meta.maintainers = [ lib.hm.maintainers.tomeon ];

  options.services.ntfy-sh = {
    enable = lib.mkEnableOption ''
      the ntfy.sh notification client service.

      This will run {command}`ntfy subscribe` as a background service using the
      settings from {option}`programs.ntfy-sh`
    '';

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Additional arguments to pass to the `ntfy` CLI client.
      '';
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Extra packages whose {file}`/bin/` subdirectory will be added to the
        `ntfy-sh` service's {env}`PATH` environment variable.
      '';
    };

    script = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      default = pkgs.writeShellScript "ntfy-sh-start" ''
        set -euo pipefail

        config="''${RUNTIME_DIRECTORY?}"/${
          lib.escapeShellArg prog.configFileName
        }

        ${lib.escapeShellArg prog.writeConfig} "''${config%/*}" || exit

        # Preserve existing `PATH`
        export PATH=${lib.makeBinPath cfg.extraPackages}"''${PATH:+:''${PATH}}"

        exec ${prog.wrapper}/bin/ntfy subscribe \
          --config "$config" --from-config ${lib.escapeShellArgs cfg.extraArgs}
      '';
      description = ''
        Script for launching the {command}`ntfy subscribe` process for
        `ntfy-sh.service`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.ntfy-sh = {
      Unit = {
        Description = "ntfy.sh notification client service";

        X-Restart-Triggers =
          [ (builtins.hashString "md5" (builtins.toJSON prog.config)) ];
      };

      Install.WantedBy = [ "default.target" ];

      Service = {
        ExecStart = cfg.script;
        Restart = "always";
        RuntimeDirectory = "ntfy-sh";
      };
    };
  };
}
