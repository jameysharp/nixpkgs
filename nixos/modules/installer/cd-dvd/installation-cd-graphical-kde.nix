# This module defines a NixOS installation CD that contains X11 and
# Plasma5.

{ config, lib, pkgs, ... }:

with lib;

{
  imports = [ ./installation-cd-graphical-base.nix ];

  services.xserver = {
    desktopManager.plasma5 = {
      enable = true;
      enableQt4Support = false;
    };

    # Enable touchpad support for many laptops.
    synaptics.enable = true;
  };

  environment.systemPackages = with pkgs; [
    # Graphical text editor
    kate
  ];

  systemd.tmpfiles.rules = let

    manualDesktopFile = pkgs.writeScript "nixos-manual.desktop" ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=NixOS Manual
      Exec=firefox ${config.system.build.manual.manualHTMLIndex}
      Icon=text-html
    '';

  in [
    "L+ /root/Desktop/nixos-manual.desktop - - - - ${manualDesktopFile}"
    "L+ /root/Desktop/org.kde.konsole.desktop - - - - ${pkgs.konsole}/share/applications/org.kde.konsole.desktop"
    "L+ /root/Desktop/gparted.desktop - - - - ${pkgs.gparted}/share/applications/gparted.desktop"
  ];

}
