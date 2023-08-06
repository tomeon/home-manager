{ config, lib, pkgs, ... }:

let
  inherit (config.lib.test) mkStubPackage;

  cfg = config.programs.ntfy-sh;
in {
  programs.ntfy-sh = {
    enable = true;
    package = mkStubPackage { outPath = "@ntfy-sh@"; };
    shell = pkgs.dash;
    settings = {
      default-user = "foo";
      default-password = { _secret = "/build/pw"; };
      subscribe = {
        this = {
          command = [ "frob" ];

          # Test `freeformType`
          arbitrary.thing = [ 1 "two" false ];
        };

        that = {
          command = ''
            bleep bloop
          '';

          condition = {
            priority = 1;
            tags = [ "blue" "red" ];
          };
        };
      };
    };
  };

  nmt.script = let
    expected = {
      inherit (cfg.settings) default-user;
      default-password = "bar";
      subscribe = [
        {
          topic = "that";
          inherit (cfg.settings.subscribe.that) command;
          "if" = {
            inherit (cfg.settings.subscribe.that.condition) priority tags;
          };
        }

        {
          topic = "this";
          command = "'frob'"; # escaped with `lib.escapeShellArgs`
          arbitrary.thing = [ 1 "two" false ];
        }
      ];
    };
  in ''
    wrapper=${lib.escapeShellArg cfg.wrapper}
    shellWrapper=${lib.escapeShellArg cfg.shellWrapper}
    shell=${lib.escapeShellArg cfg.shell}

    assertFileExists "$wrapper/bin/ntfy"
    assertLinkPointsTo "$shellWrapper/bin/sh" "$shell"/${
      lib.escapeShellArg cfg.shell.shellPath
    }
    assertFileRegex "$wrapper/bin/ntfy" "PATH=$shellWrapper/bin"

    echo ${lib.escapeShellArg expected.default-password} > ${
      lib.escapeShellArg
      (builtins.baseNameOf cfg.settings.default-password._secret)
    }

    errmsg="$(${lib.escapeShellArg cfg.writeConfig} 2>&1)" \
      && fail 'Expected writeConfig script to error if called without arguments, but it did not.'

    case "$errmsg" in
      'Usage:'*'<config-output-directory>'*)
        # NOP
        ;;
      *)
        fail "Got unexpected error message from writeConfig script: $errmsg"
        ;;
    esac

    export DRY_RUN_CMD=""
    export XDG_CONFIG_HOME="$PWD"

    {
      ${config.home.activation.ntfy-sh.data}
    } || fail 'Expected configuration file to serialize successfully but it did not.'

    config="$XDG_CONFIG_HOME/ntfy"/${lib.escapeShellArg cfg.configFileName}

    mode="$(${pkgs.coreutils}/bin/stat --printf='%#a' "$config")" \
      || fail 'Failed to stat configuration file.'

    [[ "$mode" = 0640 ]] || fail "Got unexpected mode $mode on configuration file."

    actual="$PWD/actual"
    ${pkgs.jq}/bin/jq --sort-keys . < "$config" > "$actual" \
      || fail 'Expected configuration file to contain valid JSON but it did not.'

    expected="$PWD/expected"
    ${pkgs.jq}/bin/jq --sort-keys . < ${
      (pkgs.formats.json { }).generate "expected" expected
    } > "$expected"

    assertFileContent "$actual" "$expected"
  '';
}
