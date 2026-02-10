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
  boot.initrd.kernelModules = [ "amdgpu" ];
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
  # Swapfile auf btrfs ist problematisch - erstmal nur zram verwenden
  # Swap-Partition kann später eingerichtet werden
  swapDevices = [ ];

  # --- zram (komprimierter RAM-Swap) ---
  zramSwap = {
    enable = true;
    memoryPercent = 50;   # Mehr zram da kein swapfile
    algorithm = "zstd";
  };

  # --- AMD GPU ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # Mesa reicht aus - amdvlk kann Konflikte verursachen
  };

  # --- CPU ---
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
