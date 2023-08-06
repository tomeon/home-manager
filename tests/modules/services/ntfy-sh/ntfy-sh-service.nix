{ config, pkgs, ... }:

let cfg = config.services.ntfy-sh;
in {
  programs.ntfy-sh = {
    package = config.lib.test.mkStubPackage { outPath = "@ntfy-sh@"; };
  };

  services.ntfy-sh = {
    enable = true;
    extraArgs = [ "--foo-bar" ];
  };

  nmt.script = ''
    stripUnpredictable() {
      grep -v -e '^ExecStart=' -e '^X-Restart-Triggers=' "$@"
    }

    serviceFile=home-files/.config/systemd/user/ntfy-sh.service

    assertFileExists "$serviceFile"
    assertFileRegex "$serviceFile" '^X-Restart-Triggers=[[:xdigit:]]\{32\}$'

    script=${cfg.script}
    assertFileRegex "$script" "'--foo-bar'"
    assertFileRegex "$serviceFile" "^ExecStart=''${script}$"

    actual="$PWD/actual"
    stripUnpredictable "$TESTED/$serviceFile" > "$actual"

    expected="$PWD/expected"
    stripUnpredictable ${./ntfy-sh-expected.service} > "$expected"

    assertFileContent "$actual" "$expected"
  '';
}
