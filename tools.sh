#!/bin/bash
set -e

echo "🔄 Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

# Herramientas visuales y estéticas
sudo apt install -y neofetch bat htop exa fzf ripgrep tldr fortune cowsay fd-find duf ruby curl

echo "🌈 Instalando lolcat"
sudo gem install lolcat

echo "🐉 Instalando btop (snap)"
sudo snap install btop

echo "⚡ Instalando Starship prompt"
curl -sS https://starship.rs/install.sh | sh -s -- -y

echo "🧭 Instalando zoxide"
curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash

# Configuración en .zshrc
ZSHRC="$HOME/.zshrc"
echo -e "\n# 🧁 Cositas kawaii añadidas por Spark-chan" >> "$ZSHRC"
echo "neofetch" >> "$ZSHRC"
echo "eval \"\$(starship init zsh)\"" >> "$ZSHRC"
echo "eval \"\$(zoxide init zsh)\"" >> "$ZSHRC"
echo "alias cat=\"batcat\"" >> "$ZSHRC"
echo "alias ls=\"exa -lh --icons\"" >> "$ZSHRC"
echo "alias please=\"sudo\"" >> "$ZSHRC"
echo "fortune | cowsay | lolcat" >> "$ZSHRC"

echo "✅ ¡Listo, Robert-tan! Tu terminal está ahora más sugoi que nunca~ 🌸✨"
