{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.services.mattermost;

  defaultConfig = builtins.fromJSON (readFile "${pkgs.mattermost}/config/config.json");

  mattermostConf = foldl recursiveUpdate defaultConfig
    [ { ServiceSettings.SiteURL = cfg.siteUrl;
        ServiceSettings.ListenAddress = cfg.listenAddress;
        TeamSettings.SiteName = cfg.siteName;
        SqlSettings.DriverName = "postgres";
        SqlSettings.DataSource = "postgres://${cfg.localDatabaseUser}:${cfg.localDatabasePassword}@localhost:5432/${cfg.localDatabaseName}?sslmode=disable&connect_timeout=10";
      }
      cfg.extraConfig
    ];

  mattermostConfJSON = pkgs.writeText "mattermost-config-raw.json" (builtins.toJSON mattermostConf);

in

{
  options = {
    services.mattermost = {
      enable = mkEnableOption "Mattermost chat server";

      statePath = mkOption {
        type = types.str;
        default = "/var/lib/mattermost";
        description = "Mattermost working directory";
      };

      siteUrl = mkOption {
        type = types.str;
        example = "https://chat.example.com";
        description = ''
          URL this Mattermost instance is reachable under, without trailing slash.
        '';
      };

      siteName = mkOption {
        type = types.str;
        default = "Mattermost";
        description = "Name of this Mattermost site.";
      };

      listenAddress = mkOption {
        type = types.str;
        default = ":8065";
        example = "[::1]:8065";
        description = ''
          Address and port this Mattermost instance listens to.
        '';
      };

      mutableConfig = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether the Mattermost config.json is writeable by Mattermost.

          Most of the settings can be edited in the system console of
          Mattermost if this option is enabled. A template config using
          the options specified in services.mattermost will be generated
          but won't be overwritten on changes or rebuilds.

          If this option is disabled, changes in the system console won't
          be possible (default). If an config.json is present, it will be
          overwritten!
        '';
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = ''
          Addtional configuration options as Nix attribute set in config.json schema.
        '';
      };

      localDatabaseCreate = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Create a local PostgreSQL database for Mattermost automatically.
        '';
      };

      localDatabaseName = mkOption {
        type = types.str;
        default = "mattermost";
        description = ''
          Local Mattermost database name.
        '';
      };

      localDatabaseUser = mkOption {
        type = types.str;
        default = "mattermost";
        description = ''
          Local Mattermost database username.
        '';
      };

      localDatabasePassword = mkOption {
        type = types.str;
        default = "mmpgsecret";
        description = ''
          Password for local Mattermost database user.
        '';
      };

      user = mkOption {
        type = types.str;
        default = "mattermost";
        description = ''
          User which runs the Mattermost service.
        '';
      };

      group = mkOption {
        type = types.str;
        default = "mattermost";
        description = ''
          Group which runs the Mattermost service.
        '';
      };

      matterircd = {
        enable = mkEnableOption "Mattermost IRC bridge";
        parameters = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "-mmserver chat.example.com" "-bind [::]:6667" ];
          description = ''
            Set commandline parameters to pass to matterircd. See
            https://github.com/42wim/matterircd#usage for more information.
          '';
        };
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      users.users = optionalAttrs (cfg.user == "mattermost") (singleton {
        name = "mattermost";
        group = cfg.group;
        uid = config.ids.uids.mattermost;
        home = cfg.statePath;
      });

      users.groups = optionalAttrs (cfg.group == "mattermost") (singleton {
        name = "mattermost";
        gid = config.ids.gids.mattermost;
      });

      services.postgresql.enable = cfg.localDatabaseCreate;

      systemd.tmpfiles.rules = [
        "d ${cfg.statePath}"
        "d ${cfg.statePath}/data"
        "d ${cfg.statePath}/config"
        "d ${cfg.statePath}/logs"
        "L+ ${cfg.statePath}/bin - - - - ${pkgs.mattermost}/bin"
        "L+ ${cfg.statePath}/fonts - - - - ${pkgs.mattermost}/fonts"
        "L+ ${cfg.statePath}/i18n - - - - ${pkgs.mattermost}/i18n"
        "L+ ${cfg.statePath}/templates - - - - ${pkgs.mattermost}/templates"
        "L+ ${cfg.statePath}/client - - - - ${pkgs.mattermost}/client"
      ] ++ lib.optionals (!cfg.mutableConfig) [
        "L+ ${cfg.statePath}/config/config.json - - - - ${mattermostConfJSON}"
      ] ++ [
        "Z ${cfg.statePath} ~750 ${cfg.user} ${cfg.group}"
      ];

      systemd.services.mattermost = {
        description = "Mattermost chat service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "postgresql.service" ];

        preStart = lib.optionalString cfg.mutableConfig ''
          if ! test -e config/.initial-created; then
            cp -f ${mattermostConfJSON} config/config.json
            touch config/.initial-created
          fi
        '' + lib.optionalString cfg.localDatabaseCreate ''
          if ! test -e .db-created; then
            ${pkgs.sudo}/bin/sudo -u ${config.services.postgresql.superUser} \
              ${config.services.postgresql.package}/bin/psql postgres -c \
                "CREATE ROLE ${cfg.localDatabaseUser} WITH LOGIN NOCREATEDB NOCREATEROLE ENCRYPTED PASSWORD '${cfg.localDatabasePassword}'"
            ${pkgs.sudo}/bin/sudo -u ${config.services.postgresql.superUser} \
              ${config.services.postgresql.package}/bin/createdb \
                --owner ${cfg.localDatabaseUser} ${cfg.localDatabaseName}
            touch .db-created
          fi
        '';

        serviceConfig = {
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${pkgs.mattermost}/bin/mattermost";
          WorkingDirectory = cfg.statePath;
          Restart = "always";
          RestartSec = "10";
          LimitNOFILE = "49152";
        };
        unitConfig.JoinsNamespaceOf = mkIf cfg.localDatabaseCreate "postgresql.service";
      };
    })
    (mkIf cfg.matterircd.enable {
      systemd.services.matterircd = {
        description = "Mattermost IRC bridge service";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "nobody";
          Group = "nogroup";
          ExecStart = "${pkgs.matterircd.bin}/bin/matterircd ${concatStringsSep " " cfg.matterircd.parameters}";
          WorkingDirectory = "/tmp";
          PrivateTmp = true;
          Restart = "always";
          RestartSec = "5";
        };
      };
    })
  ];
}

