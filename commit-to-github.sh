#!/bin/bash
set -e

REPO_URL="https://github.com/kenzow-OfficialHost/Instalation-ThemaPtrodactyl2026.git"
BRANCH="main"

if [ ! -d ".git" ]; then
  echo "[+] Inisialisasi git repo"
  git init
fi

cat > .gitignore <<'EOF'
node_modules/
.DS_Store
*.log
EOF

git add .
git commit -m "Pterodactyl multi-theme installer (Stellar + Enigma) - Kenxzo Official"
git branch -M "$BRANCH"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

git push -u origin "$BRANCH"

echo ""
echo "SELESAI. Cek repo: $REPO_URL"
