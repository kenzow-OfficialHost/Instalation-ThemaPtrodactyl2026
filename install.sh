#!/bin/bash
set -e

# ============================================================
# Multi-Theme Installer untuk Pterodactyl Panel
# Stellar & Enigma — by Kenxzo Official
# ============================================================

PANEL_DIR="/var/www/pterodactyl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRISTINE_DIR="${PANEL_DIR}-pristine-backup"
STATE_FILE="/root/.kenxzo-theme-state"

# ------------------------------------------------------------
# Util
# ------------------------------------------------------------
banner() {
  echo ""
  echo "=================================================="
  echo " $1"
  echo "=================================================="
}

require_panel() {
  if [ ! -d "$PANEL_DIR" ]; then
    echo "[!] Direktori panel tidak ditemukan di $PANEL_DIR"
    echo "    Edit variabel PANEL_DIR di awal script ini kalau path panel kamu beda."
    exit 1
  fi
}

ensure_pristine_backup() {
  if [ ! -d "$PRISTINE_DIR" ]; then
    banner "Membuat backup pristine (hanya sekali, dipakai untuk ganti/uninstall tema nanti)"
    cp -r "$PANEL_DIR" "$PRISTINE_DIR"
    echo "[+] Backup pristine tersimpan di $PRISTINE_DIR"
  else
    echo "[+] Backup pristine sudah ada di $PRISTINE_DIR, skip."
  fi
}

restore_pristine() {
  banner "Restore panel ke kondisi pristine (sebelum tema apapun terpasang)"
  if [ ! -d "$PRISTINE_DIR" ]; then
    echo "[!] Backup pristine tidak ditemukan di $PRISTINE_DIR."
    echo "    Tidak bisa restore otomatis. Cek manual backup lama (*.bak-*) kalau ada."
    exit 1
  fi
  rm -rf "$PANEL_DIR"
  cp -r "$PRISTINE_DIR" "$PANEL_DIR"
  echo "[+] Panel sudah dikembalikan ke kondisi pristine."
}

ensure_node22() {
  echo "[+] Cek versi Node.js (butuh >=22)"
  NODE_MAJOR=0
  if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
  fi
  if [ "$NODE_MAJOR" -lt 22 ]; then
    echo "    -> Node.js terdeteksi v$NODE_MAJOR, upgrade ke Node 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
  else
    echo "    -> Node.js sudah >=22 (v$NODE_MAJOR), skip."
  fi
  npm i -g yarn >/dev/null 2>&1 || true
}

patch_webpack_fallback() {
  cd "$PANEL_DIR"
  if [ -f webpack.config.js ] && ! grep -q "path-browserify" webpack.config.js; then
    echo "[+] Patch webpack.config.js untuk polyfill 'path' (fix Webpack 5)"
    sed -i "s/symlinks: false,/fallback: {\n            path: require.resolve('path-browserify'),\n        },\n        symlinks: false,/" webpack.config.js
  fi
}

build_and_finish() {
  cd "$PANEL_DIR"
  echo "[+] Build frontend production (bisa makan waktu beberapa menit)"
  yarn build:production
  echo "[+] Bersihkan cache view"
  php artisan view:clear
}

# ------------------------------------------------------------
# Install Stellar
# ------------------------------------------------------------
install_stellar() {
  banner "Install Tema Stellar"
  ensure_pristine_backup
  restore_pristine

  echo "[+] Menyalin file tema Stellar ke panel"
  cp -rf "$SCRIPT_DIR/themes/stellar/pterodactyl"/. "$PANEL_DIR"/

  ensure_node22
  cd "$PANEL_DIR"
  echo "[+] Install dependency tema"
  yarn add react-feather path-browserify
  patch_webpack_fallback

  echo "[+] Jalankan migration"
  php artisan migrate --force

  build_and_finish
  echo "stellar" > "$STATE_FILE"

  banner "STELLAR SELESAI DIPASANG"
  echo "Langkah terakhir (manual, lewat browser):"
  echo "1. Buka https://domain-panel-kamu/admin/theme"
  echo "2. Isi 'Small logo' & 'Background Image' dengan URL LENGKAP (wajib diawali https://)"
  echo "3. Klik Save, refresh dashboard."
}

# ------------------------------------------------------------
# Install Enigma
# ------------------------------------------------------------
install_enigma() {
  banner "Install Tema Enigma"
  ensure_pristine_backup
  restore_pristine

  echo "[+] Menyalin file tema Enigma ke panel"
  cp -rf "$SCRIPT_DIR/themes/enigma/pterodactyl"/. "$PANEL_DIR"/

  DASH_FILE="$PANEL_DIR/resources/scripts/components/dashboard/DashboardContainer.tsx"
  if [ -f "$DASH_FILE" ]; then
    echo ""
    read -p "Masukkan link WhatsApp (https://wa.me/...): " LINK_WA
    read -p "Masukkan link Group (https://...): " LINK_GROUP
    read -p "Masukkan link Channel (https://...): " LINK_CHNL
    sed -i "s|LINK_WA|${LINK_WA}|g" "$DASH_FILE"
    sed -i "s|LINK_GROUP|${LINK_GROUP}|g" "$DASH_FILE"
    sed -i "s|LINK_CHNL|${LINK_CHNL}|g" "$DASH_FILE"
    echo "[+] Link WA/Group/Channel sudah disisipkan ke tema."
  fi

  ensure_node22
  cd "$PANEL_DIR"
  echo "[+] Install dependency tema"
  yarn add path-browserify
  patch_webpack_fallback

  build_and_finish
  echo "enigma" > "$STATE_FILE"

  banner "ENIGMA SELESAI DIPASANG"
}

# ------------------------------------------------------------
# Uninstall (kembalikan ke panel bersih, tanpa tema apapun)
# ------------------------------------------------------------
uninstall_theme() {
  banner "Uninstall Tema (kembali ke panel bersih)"
  if [ ! -d "$PRISTINE_DIR" ]; then
    echo "[!] Belum pernah ada tema yang terpasang lewat installer ini (tidak ada backup pristine)."
    exit 1
  fi
  restore_pristine
  ensure_node22
  cd "$PANEL_DIR"
  build_and_finish
  rm -f "$STATE_FILE"
  banner "UNINSTALL SELESAI — panel kembali ke kondisi bersih tanpa tema."
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------
require_panel

CURRENT="belum ada tema terpasang"
if [ -f "$STATE_FILE" ]; then
  CURRENT="$(cat "$STATE_FILE")"
fi

echo ""
echo "=================================================="
echo "   Pterodactyl Theme Installer — Kenxzo Official"
echo "=================================================="
echo " Tema aktif saat ini: $CURRENT"
echo ""
echo " 1. Install tema Stellar"
echo " 2. Install tema Enigma"
echo " 3. Uninstall tema (kembali ke panel bersih)"
echo " x. Batal"
echo ""
read -p "Pilih (1/2/3/x): " CHOICE

case "$CHOICE" in
  1) install_stellar ;;
  2) install_enigma ;;
  3) uninstall_theme ;;
  x) echo "Dibatalkan." ; exit 0 ;;
  *) echo "Pilihan tidak valid." ; exit 1 ;;
esac
