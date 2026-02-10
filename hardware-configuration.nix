# Hardware-Konfiguration fuer HP Laptop 15-fc0xxx (AMD Cezanne/Barcelo)
# Anpassen nach: sudo nixos-generate-config --show-hardware-config

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # --- Kernel & Initrd ---
  boot.initrd.availableKernelModules = [
    "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # --- Dateisysteme (btrfs + EFI) ---
  # WICHTIG: UUIDs nach Installation mit `blkid` pruefen und anpassen!
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/e6ab3d9e-b5a7-4306-aa18-873c352e3e88";
    fsType = "btrfs";
    options = [ "subvol=root" "compress=zstd:1" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/e6ab3d9e-b5a7-4306-aa18-873c352e3e88";
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd:1" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/832b5d4a-570b-468a-8105-26c1ce3de3fa";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/BDAA-CAD0";
    fsType = "vfat";
    options = [ "umask=0077" "shortname=winnt" ];
  };

  # --- Swap ---
  swapDevices = [
    { device = "/swapfile"; size = 35 * 1024; }
  ];

  # --- zram ---
  zramSwap = {
    enable = true;
    memoryPercent = 25;   # ~8GB bei 32GB RAM
    algorithm = "lzo-rle";
  };

  # --- AMD GPU ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      amdvlk
      mesa
    ];
  };

  # --- CPU ---
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
