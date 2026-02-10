# NixOS System-Konfiguration
# Nachbau des Fedora Sway Spin Setups auf HP Laptop 15-fc0xxx
#
# Installation:
#   1. NixOS ISO booten
#   2. Partitionen beibehalten (btrfs root+home, ext4 boot, vfat EFI)
#   3. Diese Datei nach /etc/nixos/configuration.nix kopieren
#   4. hardware-configuration.nix nach /etc/nixos/ kopieren (UUIDs pruefen!)
#   5. sudo nixos-install
#   6. Nach Reboot: home.nix mit home-manager aktivieren

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ============================================================
  # Boot
  # ============================================================
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = true;
    };
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ============================================================
  # Netzwerk
  # ============================================================
  networking = {
    hostName = "laptop";
    networkmanager.enable = true;
    firewall.enable = true;
  };

  # ============================================================
  # Locale / Zeitzone / Tastatur
  # ============================================================
  time.timeZone = "Europe/Berlin";

  i18n = {
    defaultLocale = "de_DE.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "de_DE.UTF-8";
    };
  };

  console = {
    keyMap = "de";
  };

  # ============================================================
  # Benutzer
  # ============================================================
  users.users.laptop = {
    isNormalUser = true;
    description = "laptop";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    shell = pkgs.bash;
  };

  # ============================================================
  # Nix-Einstellungen
  # ============================================================
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nixpkgs.config.allowUnfree = true;

  # ============================================================
  # Desktop: Sway (SwayFX)
  # ============================================================
  programs.sway = {
    enable = true;
    package = pkgs.swayfx;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      swaybg
      waybar
      wl-clipboard
      grim
      slurp
      rofi-wayland
      dunst
      kanshi
      wlr-randr
      wlsunset
      brightnessctl
      playerctl
      wev
      imv
      foot
    ];
  };

  # XDG Desktop Portal fuer Wayland
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # SDDM als Display-Manager (wie Fedora Sway Spin)
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # ============================================================
  # Audio: PipeWire
  # ============================================================
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;

  # ============================================================
  # Bluetooth
  # ============================================================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # ============================================================
  # Drucken (CUPS)
  # ============================================================
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  # ============================================================
  # Verschiedene System-Services
  # ============================================================
  services.fwupd.enable = true;
  services.udisks2.enable = true;
  services.upower.enable = true;
  services.gvfs.enable = true;
  services.openssh.enable = true;
  services.thermald.enable = false; # AMD, nicht Intel
  powerManagement.powertop.enable = true;

  # Gnome Keyring fuer Secrets
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Polkit
  security.polkit.enable = true;

  # Flatpak nicht mehr noetig - Anki, Signal, Bitwarden sind native Nix-Pakete

  # ============================================================
  # Schriften
  # ============================================================
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      inter
      jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
      font-awesome
      google-fonts
      roboto
      open-sans
    ];
    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Inter" ];
        monospace = [ "JetBrains Mono" ];
        serif = [ "Noto Serif" ];
      };
    };
  };

  # ============================================================
  # System-Pakete
  # ============================================================
  environment.systemPackages = with pkgs; [

    # --- Terminal & Shell ---
    foot
    tmux
    bash-completion
    fastfetch

    # --- Editoren ---
    neovim
    nano
    zed-editor

    # --- Browser ---
    brave
    firefox
    chromium
    qutebrowser

    # --- Dateimanager ---
    xfce.thunar
    xfce.thunar-archive-plugin
    pcmanfm
    xarchiver

    # --- PDF / Dokumente ---
    okular
    evince
    mupdf
    pdfpc

    # --- Medien ---
    mpv
    vlc
    imv
    pavucontrol

    # --- Grafik ---
    inkscape
    imagemagick
    graphicsmagick

    # --- Office ---
    libreoffice

    # --- Apps (ersetzt Flatpaks/Snaps) ---
    anki
    signal-desktop
    bitwarden-desktop

    # --- VPN ---
    protonvpn-gui

    # --- AI ---
    claude-code

    # --- E-Mail ---
    claws-mail

    # --- Entwicklung ---
    git
    gcc
    gnumake
    binutils
    pkg-config
    openssl
    openssl.dev
    nodejs
    cargo
    rustc
    python3

    # --- CLI-Tools ---
    ripgrep
    jq
    tree
    htop
    curl
    wget
    unzip
    zip
    p7zip
    rsync
    lsof
    pciutils
    usbutils
    ethtool
    nmap
    whois
    bind
    traceroute
    mtr
    dos2unix
    bc
    minicom
    bat

    # --- LaTeX (volle Installation wie auf Fedora) ---
    texliveFull

    # --- OCR ---
    ocrmypdf
    tesseract
    unpaper

    # --- Netzwerk / VPN ---
    wireguard-tools
    openvpn
    openconnect

    # --- Sway-Oekosystem (zusaetzlich zu extraPackages) ---
    scenefx
    libnotify
    xdg-utils
    xdg-user-dirs

    # --- Theming ---
    adw-gtk3
    papirus-icon-theme
    bibata-cursors

    # --- Medien-Codecs ---
    ffmpeg
    yt-dlp

    # --- Cloud ---
    seafile-client

    # --- Sonstiges ---
    powertop
    gdb
    ctags
    bison
    flex
    man-db
    man-pages
  ];

  # ============================================================
  # Programme
  # ============================================================
  programs.bash.completion.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  # ============================================================
  # Umgebungsvariablen
  # ============================================================
  environment.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";
    NIXOS_OZONE_WL = "1";
  };

  # ============================================================
  # System-Version
  # ============================================================
  system.stateVersion = "24.11";
}
