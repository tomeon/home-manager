{ config, lib, ... }:

let
  parentPath = "parent";

  childPath = "${parentPath}/with/child";
  childText = toString (builtins.placeholder "child");

  configHome = "/config";
in
{
  config = {
    xdg = {
      inherit configHome;

      configFile = {
        ${parentPath}.source = ./parent;
        ${childPath}.text = childText;
      };
    };

    nmt.script = ''
      parentPath=home-files/${lib.escapeShellArg "${configHome}/${parentPath}"}
      childPath=home-files/${lib.escapeShellArg "${configHome}/${childPath}"}

      assertDirectoryExists "$parentPath"
      assertLinkExists "$parentPath/other-child"
      assertLinkExists "$childPath"
      assertFileContains "$childPath" ${lib.escapeShellArg childText}
    '';
  };
}
