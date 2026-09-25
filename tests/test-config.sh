#!/usr/bin/env bash
set -euo pipefail

# Configuration-only tests: never install packages or touch the real home.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "$repo_dir/.toolsetup-test.XXXXXXXX")"
cleanup() {
    local resolved_test_root
    resolved_test_root="$(cd -- "$test_root" && pwd -P)" || return 1
    if [[ "${resolved_test_root%/*}" == "$repo_dir" &&
          "${resolved_test_root##*/}" == .toolsetup-test.* ]]; then
        rm -rf -- "$resolved_test_root"
    else
        printf 'Refusing cleanup outside the expected repository test directory: %s\n' "$resolved_test_root" >&2
        return 1
    fi
}
trap cleanup EXIT
export HOME="$test_root/home"
unset ZDOTDIR
mkdir -p -- "$HOME"

sudo() { printf 'FAIL: test attempted to run sudo\n' >&2; return 1; }
# shellcheck source=../tools.sh
source "$repo_dir/tools.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_same() { cmp -s -- "$1" "$2" || fail "$3"; }
assert_block() {
    local file="$1" marker count
    for marker in '# >>> toolsetup >>>' '# <<< toolsetup <<<'; do
        count="$(grep -Fxc -- "$marker" "$file" || true)"
        [[ "$count" == 1 ]] || fail "expected one $marker in $file, found $count"
    done
}
new_home() {
    export HOME="$test_root/$1"
    unset ZDOTDIR
    mkdir -p -- "$HOME"
}

new_home missing-zsh
printf 'export PERSONAL_SETTING=untouched\n' > "$HOME/.zshrc"
cp -- "$HOME/.zshrc" "$test_root/preflight-original"
find "$HOME" -print | sort > "$test_root/preflight-files-before"
preflight_bin="$test_root/preflight-bin"
mkdir -p -- "$preflight_bin"
# Only recording stubs are on PATH, so this also works on hosts with Zsh installed.
for executable in sudo apt apt-get add-apt-repository dpkg git tldr mkdir mktemp dirname awk cat cp rm; do
    printf '#!%s\n' "$BASH" > "$preflight_bin/$executable"
    cat >> "$preflight_bin/$executable" <<'SH'
printf '%s\n' "$0 $*" >> "$TOOLSETUP_TEST_CALLS"
exit 99
SH
    chmod +x "$preflight_bin/$executable"
done
if PATH="$preflight_bin" BASH_ENV= ENV= TOOLSETUP_TEST_CALLS="$test_root/preflight-calls" \
    "$BASH" --noprofile --norc "$repo_dir/tools.sh" > "$test_root/preflight-output" 2>&1; then
    fail 'installer should fail when Zsh is missing'
fi
grep -Fq Zsh "$test_root/preflight-output" || fail 'missing-Zsh error does not name Zsh'
grep -Fq 'sudo apt-get install zsh' "$test_root/preflight-output" || fail 'missing-Zsh error does not explain how to install it'
[[ ! -e "$test_root/preflight-calls" ]] || fail 'installer ran commands before rejecting missing Zsh'
assert_same "$test_root/preflight-original" "$HOME/.zshrc" 'missing-Zsh failure modified user configuration'
find "$HOME" -print | sort > "$test_root/preflight-files-after"
assert_same "$test_root/preflight-files-before" "$test_root/preflight-files-after" 'missing-Zsh failure changed files in HOME'
printf 'PASS: missing Zsh stops the entrypoint before commands or configuration changes\n'

new_home fresh
configure_zsh >/dev/null
assert_block "$HOME/.zshrc"
cp -- "$HOME/.zshrc" "$test_root/first-run"
configure_zsh >/dev/null
configure_zsh >/dev/null
assert_same "$test_root/first-run" "$HOME/.zshrc" 'repeated runs changed the configuration'
backups=("$HOME"/.zshrc.toolsetup-backup.*)
[[ "${#backups[@]}" == 2 ]] || fail 'each repeated run should create a distinct backup'
for backup in "${backups[@]}"; do
    assert_same "$test_root/first-run" "$backup" 'backup differs from previous configuration'
done
printf 'PASS: fresh configuration, repeated runs and distinct backups\n'

new_home legacy
cat > "$test_root/legacy-block" <<'ZSH'
# 🧁 Cositas kawaii añadidas por Spark-chan
neofetch
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
alias cat="batcat"
alias ls="eza -lh --icons"
alias please="sudo"
fortune | cowsay | lolcat
ZSH
printf 'export PERSONAL_SETTING=before\n' > "$HOME/.zshrc"
cat "$test_root/legacy-block" "$test_root/legacy-block" >> "$HOME/.zshrc"
printf 'alias personal="echo after"\n' >> "$HOME/.zshrc"
cp -- "$HOME/.zshrc" "$test_root/legacy-original"
configure_zsh >/dev/null
assert_block "$HOME/.zshrc"
if grep -Fxq neofetch "$HOME/.zshrc"; then fail 'legacy neofetch call remains'; fi
grep -Fxq 'export PERSONAL_SETTING=before' "$HOME/.zshrc" || fail 'leading personal setting was lost'
grep -Fxq 'alias personal="echo after"' "$HOME/.zshrc" || fail 'trailing personal setting was lost'
backups=("$HOME"/.zshrc.toolsetup-backup.*)
assert_same "$test_root/legacy-original" "${backups[0]}" 'legacy backup lost original contents'
printf 'PASS: duplicated original blocks migrate while preserving personal settings\n'

new_home customized
sed 's/^neofetch$/neofetch --off/' "$test_root/legacy-block" > "$HOME/.zshrc"
cp -- "$HOME/.zshrc" "$test_root/custom-original"
configure_zsh >/dev/null
assert_block "$HOME/.zshrc"
head -n 8 "$HOME/.zshrc" > "$test_root/custom-preserved"
assert_same "$test_root/custom-original" "$test_root/custom-preserved" 'customized legacy block was changed'
printf 'PASS: customized legacy block is preserved\n'

new_home managed
cat > "$HOME/.zshrc" <<'ZSH'
export PERSONAL_SETTING=before
# >>> toolsetup >>>
obsolete_managed_command
# <<< toolsetup <<<
alias personal="echo after"
ZSH
configure_zsh >/dev/null
assert_block "$HOME/.zshrc"
if grep -Fq obsolete_managed_command "$HOME/.zshrc"; then fail 'obsolete managed content remains'; fi
grep -Fxq 'export PERSONAL_SETTING=before' "$HOME/.zshrc" || fail 'setting before managed block was lost'
grep -Fxq 'alias personal="echo after"' "$HOME/.zshrc" || fail 'setting after managed block was lost'
printf 'PASS: managed block replacement preserves surrounding settings\n'

new_home custom-zdotdir
printf 'home configuration must stay untouched\n' > "$HOME/.zshrc"
cp -- "$HOME/.zshrc" "$test_root/home-original"
export ZDOTDIR="$test_root/zsh config/nested"
configure_zsh >/dev/null
assert_block "$ZDOTDIR/.zshrc"
assert_same "$test_root/home-original" "$HOME/.zshrc" 'custom ZDOTDIR changed HOME/.zshrc'
printf 'PASS: custom ZDOTDIR with spaces and missing directories\n'

new_home malformed
printf 'personal setting\n# >>> toolsetup >>>\nunterminated block\n' > "$HOME/.zshrc"
cp -- "$HOME/.zshrc" "$test_root/malformed-original"
if configure_zsh > "$test_root/malformed-output" 2>&1; then
    fail 'unterminated managed block should fail'
fi
assert_same "$test_root/malformed-original" "$HOME/.zshrc" 'failure modified malformed configuration'
grep -Fq 'no tiene marcador de cierre' "$test_root/malformed-output" || fail 'missing actionable malformed-block error'
printf 'PASS: malformed managed block fails without modifying configuration\n'

new_home symlink
printf 'export SYMLINK_SETTING=preserved\n' > "$HOME/zshrc-target"
if ln -s zshrc-target "$HOME/.zshrc" 2>/dev/null && [[ -L "$HOME/.zshrc" ]]; then
    configure_zsh >/dev/null
    [[ -L "$HOME/.zshrc" ]] || fail '.zshrc symlink was replaced'
    assert_block "$HOME/zshrc-target"
    grep -Fxq 'export SYMLINK_SETTING=preserved' "$HOME/zshrc-target" || fail 'symlink target settings were lost'
    printf 'PASS: symlink and target contents are preserved\n'
else
    printf 'SKIP: this environment does not support creating symlinks\n'
fi

printf 'All configuration tests passed.\n'
