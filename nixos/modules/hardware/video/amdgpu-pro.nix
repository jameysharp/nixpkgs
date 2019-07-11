# This module provides the proprietary AMDGPU-PRO drivers.

{ config, lib, pkgs, ... }:

with lib;

let

  drivers = config.services.xserver.videoDrivers;

  enabled = elem "amdgpu-pro" drivers;

  package = config.boot.kernelPackages.amdgpu-pro;
  package32 = pkgs.pkgsi686Linux.linuxPackages.amdgpu-pro.override { libsOnly = true; kernel = null; };

  opengl = config.hardware.opengl;

  kernel = pkgs.linux_4_9.override {
    extraConfig = ''
      KALLSYMS_ALL y
    '';
  };

in

{

  config = mkIf enabled {

    nixpkgs.config.xorg.abiCompat = "1.19";

    services.xserver.drivers = singleton
      { name = "amdgpu"; modules = [ package ]; libPath = [ package ]; };

    hardware.opengl.package = package;
    hardware.opengl.package32 = package32;

    boot.extraModulePackages = [ package ];

    boot.kernelPackages =
      pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor kernel);

    boot.blacklistedKernelModules = [ "radeon" ];

    hardware.firmware = [ package ];

    systemd.tmpfiles.rules = [
      "L+ ${package.libCompatDir} - - - - ${package}/lib"
      "L+ /run/amdgpu-pro - - - - ${package}"
    ] ++ optionals opengl.driSupport32Bit [
      "L+ ${package32.libCompatDir} - - - - ${package32}/lib"
    ];

    system.requiredKernelConfig = with config.lib.kernelConfig; [
      (isYes "KALLSYMS_ALL")
    ];

    environment.etc = {
      "amd/amdrc".source = package + "/etc/amd/amdrc";
      "amd/amdapfxx.blb".source = package + "/etc/amd/amdapfxx.blb";
      "gbm/gbm.conf".source = package + "/etc/gbm/gbm.conf";
    };

  };

}
