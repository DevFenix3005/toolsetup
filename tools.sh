#!/usr/bin/env bash
set -euo pipefail

configure_zsh() {
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    local config_tmp backup
    mkdir -p -- "$(dirname -- "$zshrc")"
    config_tmp="$(mktemp)"

    if [[ -e "$zshrc" ]]; then
        # Remove only our managed block or an exact copy of the original block.
        # Customized legacy blocks are preserved for manual review.
        if ! awk '
            BEGIN {
                legacy_count = split("# 🧁 Cositas kawaii añadidas por Spark-chan\nneofetch\neval \"$(starship init zsh)\"\neval \"$(zoxide init zsh)\"\nalias cat=\"batcat\"\nalias ls=\"eza -lh --icons\"\nalias please=\"sudo\"\nfortune | cowsay | lolcat", legacy, "\n")
            }
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    if (lines[i] == "# >>> toolsetup >>>") {
                        for (j = i + 1; j <= NR; j++) {
                            if (lines[j] == "# <<< toolsetup <<<") break
                        }
                        if (j > NR) exit 1
                        i = j
                        continue
                    }
                    matches = 1
                    for (j = 1; j <= legacy_count; j++) {
                        if (lines[i + j - 1] != legacy[j]) {
                            matches = 0
                            break
                        }
                    }
                    if (matches) {
                        i += legacy_count - 1
                        continue
                    }
                    print lines[i]
                }
            }
        ' "$zshrc" > "$config_tmp"; then
            rm -f -- "$config_tmp"
            printf 'Error: el bloque toolsetup de %s no tiene marcador de cierre. Revisa el archivo.\n' "$zshrc" >&2
            return 1
        fi

        backup="$(mktemp "${zshrc}.toolsetup-backup.XXXXXXXX")"
        cp -p -- "$zshrc" "$backup"
        printf '📄 Respaldo de configuración: %s\n' "$backup"
    fi

    cat >> "$config_tmp" <<'ZSH'
# >>> toolsetup >>>
# Ubuntu installs fortune/cowsay/lolcat in /usr/games.
typeset -U path
path=(/usr/games $path)

if command -v bat >/dev/null 2>&1; then
    alias cat='bat'
elif command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
    alias cat='batcat'
fi
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi
if command -v eza >/dev/null 2>&1; then
    alias ls='eza -lh --icons'
fi
alias please='sudo'

if command -v delta >/dev/null 2>&1; then
    export GIT_PAGER='delta --line-numbers'
fi
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi
if [[ -o interactive ]] && command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init zsh)"
fi
if [[ -o interactive && -t 1 ]]; then
    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch
    fi
    if command -v fortune >/dev/null 2>&1 &&
       command -v cowsay >/dev/null 2>&1 &&
       command -v lolcat >/dev/null 2>&1; then
        fortune | cowsay | lolcat
    fi
fi

# Load interactive plugins after the other shell integrations.
if [[ -o interactive ]]; then
    if [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
        source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    fi
    # Syntax highlighting must be loaded last, after widgets are defined.
    if [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
        source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    fi
fi
# <<< toolsetup <<<
ZSH

    # Writing through the existing file also preserves a user's .zshrc symlink.
    cat "$config_tmp" > "$zshrc"
    rm -f -- "$config_tmp"
    printf '🧁 Configuración actualizada: %s\n' "$zshrc"
}

main() {
    # This prerequisite must be checked before any installation or file changes.
    if ! command -v zsh >/dev/null 2>&1; then
        printf 'Error: se necesita instalar Zsh antes de continuar.\n' >&2
        printf 'Instálalo primero con: sudo apt-get install zsh\n' >&2
        printf 'Después vuelve a ejecutar: bash tools.sh\n' >&2
        return 1
    fi
    if [[ ! -r /etc/os-release ]]; then
        printf 'Este instalador requiere Ubuntu 26.04 LTS o posterior.\n' >&2
        return 1
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != ubuntu ]] || ! dpkg --compare-versions "${VERSION_ID:-0}" ge 26.04; then
        printf 'Este instalador requiere Ubuntu 26.04 LTS o posterior (detectado: %s).\n' "${PRETTY_NAME:-desconocido}" >&2
        return 1
    fi
    if (( EUID == 0 )); then
        printf 'Ejecuta ./tools.sh como tu usuario habitual, sin sudo; el script pedirá permisos cuando los necesite.\n' >&2
        return 1
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'Se necesita sudo para instalar los paquetes.\n' >&2
        return 1
    fi

    echo '🔄 Actualizando índices de paquetes y habilitando Universe...'
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y universe
    sudo apt-get update

    # Package names differ from command names: batcat, rg, tldr, fortune, fdfind.
    local packages=(
        ca-certificates curl git
        fastfetch bat htop btop eza fzf ripgrep tealdeer
        fortune-mod fortunes-min cowsay lolcat starship zoxide fd-find duf
        git-delta atuin ncdu jq tmux
        zsh-autosuggestions zsh-syntax-highlighting
    )
    echo '📦 Instalando herramientas desde los repositorios de Ubuntu...'
    sudo apt-get install -y "${packages[@]}"

    configure_zsh

    echo '📚 Actualizando las páginas de tldr...'
    if ! tldr --update; then
        echo 'Aviso: no se pudo descargar la caché de tldr. Reintenta con: tldr --update' >&2
    fi

    echo '✅ ¡Listo! Abre Zsh con: zsh'
    echo 'Si ya estás en Zsh, recarga con: source "${ZDOTDIR:-$HOME}/.zshrc"'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
