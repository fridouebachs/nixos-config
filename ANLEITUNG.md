# NixOS Migration - Anleitung

## Dateien

- `flake.nix` - Nix Flake (Einstiegspunkt)
- `configuration.nix` - System-Konfiguration
- `hardware-configuration.nix` - Hardware-spezifisch (UUIDs anpassen!)
- `home.nix` - Benutzer-Konfiguration (Dotfiles, Themes, etc.)

## Installation

### 1. NixOS-ISO booten
Lade die NixOS Minimal ISO herunter und boote davon.

### 2. Partitionen beibehalten
Dein aktuelles Layout (btrfs root+home, ext4 boot, vfat EFI) kann beibehalten werden.
Falls du frisch partitionierst, passe die UUIDs in `hardware-configuration.nix` an.

### 3. Mounten
```bash
mount -o subvol=root,compress=zstd:1 /dev/nvme0n1p3 /mnt
mkdir -p /mnt/{home,boot,boot/efi}
mount -o subvol=home,compress=zstd:1 /dev/nvme0n1p3 /mnt/home
mount /dev/nvme0n1p2 /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot/efi
```

### 4. Konfiguration kopieren
```bash
mkdir -p /mnt/etc/nixos
cp flake.nix configuration.nix hardware-configuration.nix home.nix /mnt/etc/nixos/
```

### 5. UUIDs pruefen
```bash
blkid
```
Vergleiche die UUIDs mit denen in `hardware-configuration.nix` und passe sie an.

### 6. Installieren
```bash
nixos-install --flake /mnt/etc/nixos#laptop
```

### 7. Passwort setzen
```bash
nixos-enter --root /mnt -c 'passwd laptop'
```

### 8. Reboot

## Nach der Installation

### Automatisch deployt (kein manuelles Kopieren noetig)
- **Skripte** (`~/Skripte/`) — werden via home-manager aus dem Repo deployt
- **git-pp** (`~/.local/bin/git-pp`) — wird via home-manager deployt
- **Anki, Signal, Bitwarden** — native Nix-Pakete (kein Flatpak/Snap)
- **Claude Code** — natives Nix-Paket
- **ProtonVPN** — natives Nix-Paket

### Lazy.nvim (Neovim Plugin Manager)
```bash
git clone --filter=blob:none https://github.com/folke/lazy.nvim.git \
  --branch=stable ~/.local/share/nvim/lazy/lazy.nvim
```

### Rust Toolchain (rustup)
Rustup und Cargo sind in der NixOS-Config enthalten. Falls du rustup bevorzugst:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Zen Browser
```bash
# Fuer NixOS: https://github.com/0xc000022070/zen-browser-flake
# Oder manuell als AppImage/Binary herunterladen.
```
