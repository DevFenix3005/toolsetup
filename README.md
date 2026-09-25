# ✨ Robert-tan's Sugoi Terminal Setup ✨

My personal setup script for a colorful, productive Ubuntu terminal 🐧💻✨

Targets **Ubuntu 26.04 LTS (Resolute Raccoon)**. Package availability was checked against Ubuntu's package listings on **2026-09-25**, when [Ubuntu 26.04.1 LTS](https://ubuntu.com/download/desktop) was the latest stable release. The script requires Ubuntu 26.04 or newer, **Zsh already installed**, an internet connection, and a regular user with `sudo` access.

## 💾 What's Included

All CLI tools are installed through Ubuntu's APT repositories, with Universe enabled by the script.

| Command | APT package | Description |
|---------|-------------|-------------|
| `fastfetch` | [fastfetch](https://packages.ubuntu.com/resolute/fastfetch) | System info with ASCII art; replaces Neofetch |
| `bat`, `cat` | [bat](https://packages.ubuntu.com/resolute/bat) | Syntax highlighting through the Ubuntu `batcat` command |
| `htop` | [htop](https://packages.ubuntu.com/resolute/htop) | Interactive process viewer |
| `btop` | [btop](https://packages.ubuntu.com/resolute/btop) | Resource monitor with graphs |
| `eza`, `ls` | [eza](https://packages.ubuntu.com/resolute/eza) | Enhanced file listing with icons |
| `fzf` | [fzf](https://packages.ubuntu.com/resolute/fzf) | Fuzzy finder for the terminal |
| `rg` | [ripgrep](https://packages.ubuntu.com/resolute/ripgrep) | Fast text search |
| `tldr` | [tealdeer](https://packages.ubuntu.com/resolute/tealdeer) | Simplified command examples |
| `fortune` | [fortune-mod](https://packages.ubuntu.com/resolute/fortune-mod), [fortunes-min](https://packages.ubuntu.com/resolute/fortunes-min) | Fortune command and a small collection of quotes |
| `cowsay` | [cowsay](https://packages.ubuntu.com/resolute/cowsay) | Talking ASCII cows |
| `lolcat` | [lolcat](https://packages.ubuntu.com/resolute/lolcat) | Rainbow terminal output |
| `starship` | [starship](https://packages.ubuntu.com/resolute/starship) | Customizable prompt |
| `zoxide` | [zoxide](https://packages.ubuntu.com/resolute/zoxide) | Smarter directory navigation |
| `fd` | [fd-find](https://packages.ubuntu.com/resolute/fd-find) | Fast file finder through Ubuntu's `fdfind` command |
| `duf` | [duf](https://packages.ubuntu.com/resolute/duf) | Disk usage overview |
| `delta` | [git-delta](https://packages.ubuntu.com/resolute/git-delta) | Git diffs with syntax highlighting and line numbers |
| `atuin` | [atuin](https://packages.ubuntu.com/resolute/atuin) | Searchable shell history with directory and session filters |
| `ncdu` | [ncdu](https://packages.ubuntu.com/resolute/ncdu) | Interactive disk usage explorer |
| `jq` | [jq](https://packages.ubuntu.com/resolute/jq) | Format and filter JSON |
| `tmux` | [tmux](https://packages.ubuntu.com/resolute/tmux) | Terminal sessions and split panes |
| Zsh autosuggestions | [zsh-autosuggestions](https://packages.ubuntu.com/resolute/zsh-autosuggestions) | Suggest commands from shell history as you type |
| Zsh syntax highlighting | [zsh-syntax-highlighting](https://packages.ubuntu.com/resolute/zsh-syntax-highlighting) | Highlight commands while you type |

[Neofetch was archived](https://github.com/dylanaraps/neofetch), so Fastfetch now provides the startup system summary. Tealdeer supplies the `tldr` command; Resolute includes version 1.8.1. `fortune-mod` is the package name for `fortune`, and `fortunes-min` supplies its data.

`btop`, `lolcat`, Starship, and zoxide now use APT too. The tools script no longer requires Snap, RubyGems, or downloaded shell installers. APT installs Ruby automatically as a dependency of `lolcat`.

## 🛠️ Installation

The script checks for the `zsh` executable **before anything else**. If it is missing, the script stops before requesting `sudo`, installing packages, or changing configuration, and asks you to run `sudo apt-get install zsh` first. Zsh is a prerequisite; the script does not install it for you.

1. Install the prerequisites:

   ```bash
   sudo apt-get update
   sudo apt-get install -y zsh git curl ca-certificates software-properties-common
   ```

2. Optionally install [Oh My Zsh](https://ohmyz.sh/) **before** running this setup. It is not required; skip this step if it is already installed.

   ```bash
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
   ```

3. Clone the repository and run the script as your regular user:

   ```bash
   git clone https://github.com/DevFenix3005/toolsetup
   cd toolsetup
   chmod +x tools.sh
   ./tools.sh
   ```

   The script uses `sudo` for package installation, refreshes the package index, and enables Universe. It does not run a full system upgrade.

4. Start Zsh to load the configuration:

   ```bash
   exec zsh
   ```

   If you are already in Zsh, you can instead run `source "${ZDOTDIR:-$HOME}/.zshrc"`. The script does not change your default shell. Use a font with icon support to display the `eza` icons.

## ⌨️ Using the New Tools

The managed Zsh configuration sets `GIT_PAGER='delta --line-numbers'` when Delta is available, so paged Git output such as `git diff` uses Delta in that shell. It does not edit `~/.gitconfig`.

Atuin is initialized in interactive Zsh sessions; use `Ctrl+R` to search history. Account registration, synchronization, and importing existing history are optional manual steps; the installer does not perform them.

The two Zsh plugins load from their APT-installed files under `/usr/share`. Autosuggestions lets you accept a suggested command with `→`; syntax highlighting loads last in the managed block. If you add other plugins yourself, keep syntax highlighting after them.

```bash
ncdu ~                 # Find large files and directories
jq '.scripts' package.json
tmux new -s trabajo    # Start a named terminal session
```

## 🔄 Updating an Existing Setup

Pull the repository changes and run `./tools.sh` again. The script backs up an existing `${ZDOTDIR:-$HOME}/.zshrc` beside the original as `.zshrc.toolsetup-backup.<unique suffix>` before updating it. If you use a custom `ZDOTDIR`, export it before running the script.

The configuration lives in one managed block, which is replaced on subsequent runs instead of duplicated. Unmodified blocks from the original installer are migrated automatically; other custom configuration is preserved. Keep personal settings outside the managed block, and review any customized old block for leftover `neofetch` calls.

Previous copies installed with Snap, RubyGems, or the upstream Starship/zoxide installers are not uninstalled. If a command still reports an old version, use `type -a starship zoxide btop lolcat` in Zsh to check whether a copy in `/usr/local/bin`, `~/.local/bin`, or `/snap/bin` takes precedence over the APT version in `/usr/bin` or `/usr/games`.

## 🧪 Development Checks

```bash
bash -n tools.sh
bash tests/test-config.sh
```

The tests use temporary homes and do not install packages. They verify that missing Zsh stops the installer without changes, and cover configuration migration, repeated runs, backups, custom `ZDOTDIR`, and preservation of personal settings.

## 📸 Screenshot

Historical screenshot from the original setup; it still shows Neofetch, which has now been replaced by Fastfetch.

![Original terminal setup](https://github.com/DevFenix3005/toolsetup/blob/main/Screenshot%20from%202025-04-30%2016-37-47.png)
