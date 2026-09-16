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
    # -a (archive) wajib: preserve ownership/permission asli (mis. storage/
    # yg harusnya www-data). Kalau backup ini sendiri udah salah ownership,
    # restore_pristine() bakal ikut nyalin ownership yg salah juga.
    cp -a "$PANEL_DIR" "$PRISTINE_DIR"
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
  # -a (archive) wajib: cp -r biasa jalan sebagai root bikin SEMUA file
  # hasil copy jadi owner root:root, padahal storage/ & bootstrap/cache/
  # butuh ditulis www-data. Tanpa ini, panel selalu 500 abis restore.
  cp -a "$PRISTINE_DIR" "$PANEL_DIR"
  # Fix ownership LANGSUNG di sini, jangan tunda sampai build selesai.
  # Kalau build gagal di step manapun setelah ini (mis. yarn/webpack error),
  # 'set -e' bikin script berhenti sebelum sempat chown — panel bakal
  # ke-500 walau backup pristine-nya sendiri masih ownership lama/salah
  # (dari sebelum fix ini ada). Dipanggil lagi di build_and_finish sebagai
  # jaring pengaman kedua, aman & murah dijalankan berkali-kali.
  fix_storage_permissions
  echo "[+] Panel sudah dikembalikan ke kondisi pristine."
}

fix_storage_permissions() {
  echo "[+] Pastikan ownership storage/ & bootstrap/cache/ benar (www-data)"
  chown -R www-data:www-data "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
  chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
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
  [ -f webpack.config.js ] || return 0

  # path-browserify (dipakai Stellar & Enigma)
  if ! grep -q "path-browserify" webpack.config.js; then
    echo "[+] Patch webpack.config.js untuk polyfill 'path' (fix Webpack 5)"
    sed -i "s/symlinks: false,/fallback: {\n            path: require.resolve('path-browserify'),\n        },\n        symlinks: false,/" webpack.config.js
  fi

  # crypto/vm/buffer/process + fix resolusi ESM 'process/browser'.
  # Dibutuhkan Enigma (Avatar.tsx pakai 'crypto' utk hash gravatar,
  # yg menarik vm-browserify; framer-motion/axios/pathe versi ESM
  # butuh module.rules fullySpecified:false). Aman dijalankan berkali-kali
  # (idempotent) dan aman juga kalau tema lain gak butuh ini sama sekali.
  if ! grep -q "crypto-browserify" webpack.config.js; then
    echo "[+] Patch webpack.config.js untuk polyfill 'crypto'/'vm'/'process' (fix Webpack 5)"
    node "$SCRIPT_DIR/scripts/patch-webpack-polyfills.js" webpack.config.js
  fi
}

build_and_finish() {
  cd "$PANEL_DIR"
  # WAJIB: jangan asumsikan node_modules hasil restore pristine itu utuh/bisa
  # dipakai build. Kalau pristine backup direkam SEBELUM Node.js 22 terpasang
  # (kejadian di percobaan pertama), node_modules di dalamnya bisa rusak/gak
  # lengkap (mis. binary 'cross-env' hilang) walau ada di package.json.
  # yarn install di sini aman & cepat kalau lockfile gak berubah (cache).
  echo "[+] Pastikan node_modules lengkap & sesuai Node.js aktif"
  yarn install
  echo "[+] Build frontend production (bisa makan waktu beberapa menit)"
  yarn build:production
  fix_storage_permissions
  echo "[+] Bersihkan cache view"
  php artisan optimize:clear
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
  yarn add path-browserify crypto-browserify stream-browserify vm-browserify buffer process
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
