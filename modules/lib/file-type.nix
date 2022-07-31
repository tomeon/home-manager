{ homeDirectory, lib, pkgs }:

let
  inherit (lib) hasPrefix hm literalExpression mkDefault mkIf mkOption removePrefix types;

  cleanPath = path:
    let
      dummy = builtins.placeholder path;
      prefix = "${dummy}/";
      expanded = toString (/. + "${prefix}${path}");
    in
      if hasPrefix "/" path then toString (/. + path)
      else if expanded == dummy then "."
      else if hasPrefix prefix expanded then removePrefix prefix expanded
      else throw "illegal path traversal in `${path}`";

  expandPath = basePath: path:
    if hasPrefix "/" path then cleanPath path
    else cleanPath "${basePath}/${path}";

  normalizePath = path: "${cleanPath path}/";

  normalizedHomeDirectory = normalizePath homeDirectory;

  relativePathFromHomeDirectory = basePath: path:
    removePrefix "/" (removePrefix normalizedHomeDirectory (expandPath basePath path));
in
{
  # Constructs a type suitable for a `home.file` like option. The
  # target path may be either absolute or relative, in which case it
  # is relative the `basePath` argument (which itself must be an
  # absolute path).
  #
  # Arguments:
  #   - basePathDesc   docbook compatible description of the base path
  #   - basePath       the file base path
  fileType = basePathDesc: basePath: types.attrsOf (types.submodule (
    { name, config, options, ... }: {
      options = {
        target = mkOption {
          type = types.str;
          apply = relativePathFromHomeDirectory basePath;
          defaultText = literalExpression "<name>";
          description = ''
            Path to target file relative to ${basePathDesc}.
          '';
        };

        text = mkOption {
          default = null;
          type = types.nullOr types.lines;
          description = ''
            Text of the file. If this option is null then
            <link linkend="opt-home.file._name_.source">home.file.&lt;name?&gt;.source</link>
            must be set.
          '';
        };

        source = mkOption {
          type = types.path;
          description = ''
            Path of the source file or directory. If
            <link linkend="opt-home.file._name_.text">home.file.&lt;name?&gt;.text</link>
            is non-null then this option will automatically point to a file
            containing that text.
          '';
        };

        executable = mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = ''
            Set the execute bit. If <literal>null</literal>, defaults to the mode
            of the <varname>source</varname> file or to <literal>false</literal>
            for files created through the <varname>text</varname> option.
          '';
        };

        recursive = mkOption {
          type = types.bool;
          default = false;
          description = ''
            If the file source is a directory, then this option
            determines whether the directory should be recursively
            linked to the target location. This option has no effect
            if the source is a file.
            </para><para>
            If <literal>false</literal> (the default) then the target
            will be a symbolic link to the source directory. If
            <literal>true</literal> then the target will be a
            directory structure matching the source's but whose leafs
            are symbolic links to the files of the source directory.
          '';
        };

        onChange = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Shell commands to run when file has changed between
            generations. The script will be run
            <emphasis>after</emphasis> the new files have been linked
            into place.
            </para><para>
            Note, this code is always run when <literal>recursive</literal> is
            enabled.
          '';
        };

        force = mkOption {
          type = types.bool;
          default = false;
          visible = false;
          description = ''
            Whether the target path should be unconditionally replaced
            by the managed file source. Warning, this will silently
            delete the target regardless of whether it is a file or
            link.
          '';
        };

        normalizedTarget = mkOption {
          type = options.target.type;
          apply = normalizePath;
          default = config.target;
          internal = true;
          visible = false;
          description = ''
            ${options.target.description}, but normalized.
            That is, the path is cleaned up as follows:
              1. Superfluous "." elements removed,
              2. ".." elements resolved (if possible), and
              3. Duplicate "/" elements removed.
            Additionally, the path is suffixed with a single "/".  Used in
            sorting paths when constructing the `home-files` derivation.
          '';
        };
      };

      config = {
        target = mkDefault name;
        source = mkIf (config.text != null) (
          mkDefault (pkgs.writeTextFile {
            inherit (config) executable text;
            name = hm.strings.storeFileName name;
          })
        );
      };
    }
  ));
}
