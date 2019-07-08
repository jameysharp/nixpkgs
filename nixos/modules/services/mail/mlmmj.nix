{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.mlmmj;
  stateDir = "/var/lib/mlmmj";
  spoolDir = "/var/spool/mlmmj";
  listDir = domain: list: "${spoolDir}/${domain}/${list}";
  listSubdirs = [
    "incoming" "queue" "queue/discarded" "archive" "text"
    "subconf" "unsubconf" "bounce" "control" "moderation"
    "subscribers.d" "digesters.d" "requeue" "nomailsubs.d"
  ];
  transport = domain: list: "${domain}--${list}@local.list.mlmmj mlmmj:${domain}/${list}";
  virtual = domain: list: "${list}@${domain} ${domain}--${list}@local.list.mlmmj";
  alias = domain: list: "${list}: \"|${pkgs.mlmmj}/bin/mlmmj-receive -L ${listDir domain list}/\"";
  subjectPrefix = list: "[${list}]";
  listAddress = domain: list: "${list}@${domain}";
  customHeaders = domain: list: [ "List-Id: ${list}" "Reply-To: ${list}@${domain}" ];
  footer = domain: list: "To unsubscribe send a mail to ${list}+unsubscribe@${domain}";
  createList = d: l:
    let
      listRoot = listDir d l;
      makeSubdir = dir: "d ${listRoot}/${dir} - ${cfg.user} ${cfg.group}";
    in [
      "d ${listRoot} - ${cfg.user} ${cfg.group}"
    ] ++ map makeSubdir listSubdirs ++ [
      # force listaddress to the correct value even if it exists
      "F ${listRoot}/control/listaddress - ${cfg.user} ${cfg.group} - \"${listAddress d l}\""

      # only set the other control files if they don't already exist
      "C ${listRoot}/control/customheaders - ${cfg.user} ${cfg.group} - ${
        pkgs.writeText "${l}-customheaders" (concatStringsSep "\n" (customHeaders d l))}"
      "f ${listRoot}/control/footer - ${cfg.user} ${cfg.group} - \"${footer d l}\""
      "f ${listRoot}/control/prefix - ${cfg.user} ${cfg.group} - \"${subjectPrefix l}\""
    ];
in

{

  ###### interface

  options = {

    services.mlmmj = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable mlmmj";
      };

      user = mkOption {
        type = types.str;
        default = "mlmmj";
        description = "mailinglist local user";
      };

      group = mkOption {
        type = types.str;
        default = "mlmmj";
        description = "mailinglist local group";
      };

      listDomain = mkOption {
        type = types.str;
        default = "localhost";
        description = "Set the mailing list domain";
      };

      mailLists = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "The collection of hosted maillists";
      };

      maintInterval = mkOption {
        type = types.str;
        default = "20min";
        description = ''
          Time interval between mlmmj-maintd runs, see
          <citerefentry><refentrytitle>systemd.time</refentrytitle>
          <manvolnum>7</manvolnum></citerefentry> for format information.
        '';
      };

    };

  };

  ###### implementation

  config = mkIf cfg.enable {

    users.users = singleton {
      name = cfg.user;
      description = "mlmmj user";
      home = stateDir;
      uid = config.ids.uids.mlmmj;
      group = cfg.group;
      useDefaultShell = true;
    };

    users.groups = singleton {
      name = cfg.group;
      gid = config.ids.gids.mlmmj;
    };

    services.postfix = {
      enable = true;
      recipientDelimiter= "+";
      extraMasterConf = ''
        mlmmj unix - n n - - pipe flags=ORhu user=mlmmj argv=${pkgs.mlmmj}/bin/mlmmj-receive -F -L ${spoolDir}/$nexthop
      '';

      extraAliases = concatMapStringsSep "\n" (alias cfg.listDomain) cfg.mailLists;
      transport = concatMapStringsSep "\n" (transport cfg.listDomain) cfg.mailLists;
      virtual = concatMapStringsSep "\n" (virtual cfg.listDomain) cfg.mailLists;
      virtualMapType = "hash";

      extraConfig = ''
        propagate_unmatched_extensions = virtual
      '';
    };

    environment.systemPackages = [ pkgs.mlmmj ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 700 ${cfg.user} ${cfg.group}"
      "d ${spoolDir} - ${cfg.user} ${cfg.group}"
      "d ${spoolDir}/${cfg.listDomain} - ${cfg.user} ${cfg.group}"
    ] ++ concatMap (createList cfg.listDomain) cfg.mailLists;

    systemd.services."mlmmj-maintd" = {
      description = "mlmmj maintenance daemon";
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${pkgs.mlmmj}/bin/mlmmj-maintd -F -d ${spoolDir}/${cfg.listDomain}";
      };
    };

    systemd.timers."mlmmj-maintd" = {
      description = "mlmmj maintenance timer";
      timerConfig.OnUnitActiveSec = cfg.maintInterval;
      wantedBy = [ "timers.target" ];
    };
  };

}
