#!/usr/bin/env bash
# NixOS Installations-Script
# Nach Boot vom Live-USB: bash <(curl -sL URL) oder ./install.sh

set -e

echo "=== NixOS Installation ==="

echo "[1/6] WLAN verbinden..."
read -p "WLAN SSID: " WIFI_SSID
read -s -p "WLAN Passwort: " WIFI_PASS
echo ""
sudo systemctl start NetworkManager 2>/dev/null || sudo systemctl start wpa_supplicant
sleep 2
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS" 2>/dev/null || {
    wpa_passphrase "$WIFI_SSID" "$WIFI_PASS" | sudo tee /etc/wpa_supplicant.conf > /dev/null
    sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
}
echo "Warte auf Verbindung..."
sleep 5

echo "[2/6] Partitionen mounten..."
sudo mount /dev/disk/by-uuid/e6ab3d9e-b5a7-4306-aa18-873c352e3e88 -o subvol=root /mnt
sudo mkdir -p /mnt/home /mnt/boot /mnt/boot/efi
sudo mount /dev/disk/by-uuid/e6ab3d9e-b5a7-4306-aa18-873c352e3e88 -o subvol=home /mnt/home
sudo mount /dev/disk/by-uuid/832b5d4a-570b-468a-8105-26c1ce3de3fa /mnt/boot
sudo mount /dev/disk/by-uuid/BDAA-CAD0 /mnt/boot/efi

echo "[3/6] Config klonen/aktualisieren..."
if [ -d /mnt/etc/nixos/.git ]; then
    sudo git -C /mnt/etc/nixos pull
else
    sudo rm -rf /mnt/etc/nixos
    sudo git clone https://github.com/fridouebachs/nixos-config.git /mnt/etc/nixos
fi

echo "[4/6] Nix Store reparieren..."
sudo nix-store --verify --repair 2>/dev/null || true

echo "[5/6] NixOS installieren..."
sudo nixos-install --root /mnt

echo "[6/6] Fertig! Jetzt: sudo reboot"
