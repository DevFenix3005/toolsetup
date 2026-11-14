#!/usr/bin/env bash
set -euo pipefail

# Exercise real directory modes in a temporary filesystem. All privileged calls
# and Atuin initialization are stubs: no real chown, package install or history.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_parent="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
test_root="$(mktemp -d "$test_parent/toolsetup-atuin-test.XXXXXXXX")"
cleanup() {
    local resolved_test_root
    resolved_test_root="$(cd -- "$test_root" && pwd -P)" || return 1
    if [[ "${resolved_test_root%/*}" == "$test_parent" &&
          "${resolved_test_root##*/}" == toolsetup-atuin-test.* ]]; then
        command chmod -R u+rwX -- "$resolved_test_root"
        rm -rf -- "$resolved_test_root"
    else
        printf 'Refusing cleanup outside the expected temporary test directory: %s\n' "$resolved_test_root" >&2
        return 1
    fi
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
test_sudo_calls="$test_root/sudo-calls"
test_atuin_calls="$test_root/atuin-calls"
test_root_owned_directory=''
test_other_owned_directory=''
test_failed_mkdir_directory=''
test_failed_chmod_directory=''
test_fail_sudo=0
test_fail_atuin=0
test_user_uid="$(id -u)"
test_user_gid="$(id -g)"

sudo() {
    printf '%q ' "$@" >> "$test_sudo_calls"
    printf '\n' >> "$test_sudo_calls"
    [[ "$#" == 4 && "$1" == chown && "$2" == -- &&
       "$3" == "$test_user_uid:$test_user_gid" ]] ||
        fail 'unexpected privileged command'
    [[ "$test_fail_sudo" == 0 ]]
}
stat() {
    local test_stat_target="${!#}"
    if [[ "$test_stat_target" == "$test_root_owned_directory" ]]; then
        printf '0\n'
    elif [[ "$test_stat_target" == "$test_other_owned_directory" ]]; then
        printf '424242\n'
    else
        command stat "$@"
    fi
}
mkdir() {
    [[ "${!#}" != "$test_failed_mkdir_directory" ]] || return 1
    command mkdir "$@"
}
chmod() {
    [[ "${!#}" != "$test_failed_chmod_directory" ]] || return 1
    command chmod "$@"
}
atuin() {
    [[ "$#" == 2 && "$1" == init && "$2" == zsh ]] ||
        fail 'unexpected Atuin invocation'
    printf 'init zsh\n' >> "$test_atuin_calls"
    [[ "$test_fail_atuin" == 0 ]] || return 1
    printf 'export TOOLSETUP_TEST_ATUIN_LOADED=yes\n'
}

# shellcheck source=../tools.sh
source "$repo_dir/tools.sh"

new_home() {
    export HOME="$test_root/$1"
    unset ATUIN_CONFIG_DIR XDG_CONFIG_HOME XDG_DATA_HOME ZDOTDIR
    test_root_owned_directory=''
    test_other_owned_directory=''
    test_failed_mkdir_directory=''
    test_failed_chmod_directory=''
    test_fail_sudo=0
    test_fail_atuin=0
    : > "$test_sudo_calls"
    : > "$test_atuin_calls"
    command mkdir -p -- "$HOME"
}
assert_no_sudo() {
    [[ ! -s "$test_sudo_calls" ]] || fail "$1"
}
assert_mode() {
    [[ "$(command stat -c %a -- "$1")" == "$2" ]] || fail "$3"
}
expect_directory_failure() {
    if prepare_atuin_directory "$1" > "$test_root/error" 2>&1; then
        fail "$2"
    fi
}

new_home fresh
prepare_atuin > "$test_root/output" 2>&1
[[ -d "$HOME/.config/atuin" && -d "$HOME/.local/share/atuin" ]] ||
    fail 'default Atuin directories were not created'
assert_mode "$HOME/.config/atuin" 700 'new config directory is not private'
assert_mode "$HOME/.local/share/atuin" 700 'new data directory is not private'
prepare_atuin > "$test_root/output" 2>&1
assert_no_sudo 'fresh or repeated setup attempted a privileged change'
[[ "$(wc -l < "$test_atuin_calls")" -eq 2 ]] ||
    fail 'each setup should validate Atuin once'
printf 'PASS: fresh/repeated setup creates private Atuin directories and validates initialization\n'

new_home overrides
export XDG_CONFIG_HOME="$HOME/config with spaces"
export XDG_DATA_HOME="$HOME/data with spaces"
prepare_atuin > "$test_root/output" 2>&1
[[ -d "$XDG_CONFIG_HOME/atuin" && -d "$XDG_DATA_HOME/atuin" ]] ||
    fail 'XDG directory overrides were ignored'
[[ ! -e "$HOME/.config" && ! -e "$HOME/.local" ]] ||
    fail 'unused default directories were created with XDG overrides'
assert_no_sudo 'writable XDG overrides requested a privileged change'

new_home config-priority
export ATUIN_CONFIG_DIR="$HOME/atuin settings"
export XDG_CONFIG_HOME="$HOME/unused XDG config"
prepare_atuin > "$test_root/output" 2>&1
[[ -d "$ATUIN_CONFIG_DIR" ]] || fail 'ATUIN_CONFIG_DIR was ignored'
[[ ! -e "$XDG_CONFIG_HOME" && ! -e "$HOME/.config" ]] ||
    fail 'ATUIN_CONFIG_DIR did not take priority over XDG_CONFIG_HOME'
printf 'PASS: XDG paths with spaces and ATUIN_CONFIG_DIR precedence\n'

new_home invalid-path
printf 'preserve this file\n' > "$HOME/not-a-directory"
expect_directory_failure "$HOME/not-a-directory" 'a file was accepted as a directory'
[[ "$(< "$HOME/not-a-directory")" == 'preserve this file' ]] ||
    fail 'invalid-path check modified an existing file'
assert_no_sudo 'invalid-path check attempted a privileged change'

test_failed_mkdir_directory="$HOME/cannot-create"
expect_directory_failure "$test_failed_mkdir_directory" 'mkdir failure was ignored'
[[ ! -e "$test_failed_mkdir_directory" ]] || fail 'failed mkdir created a directory'
printf 'PASS: file paths and directory-creation failures are rejected\n'

new_home init-failure
test_fail_atuin=1
if prepare_atuin > "$test_root/error" 2>&1; then
    fail 'Atuin initialization failure was ignored'
fi
grep -Fq Atuin "$test_root/error" || fail 'initialization failure has no actionable Atuin error'
[[ ! -e "$HOME/.zshrc" ]] || fail 'Atuin validation modified Zsh configuration'

# Main must stop at the failed validation, even when called in an if condition.
if (( EUID != 0 )); then
    if (
        zsh() { return 0; }
        detect_platform() { platform_id=debian; platform_name='Test Debian'; }
        install_packages() { return 0; }
        configure_zsh() { printf 'unexpected configuration write\n' > "$HOME/.zshrc"; }
        main
    ) > "$test_root/error" 2>&1; then
        fail 'main ignored an Atuin initialization failure'
    fi
    [[ ! -e "$HOME/.zshrc" ]] || fail 'main configured Zsh after Atuin failed'
else
    printf 'SKIP: main requires a non-root user\n'
fi
printf 'PASS: Atuin initialization failures stop before Zsh configuration\n'

# Root and Windows filesystems can bypass/ignore mode bits. Keep the portable
# tests above, but only claim permission-repair coverage when mode checks work.
test_mode_probe="$test_root/mode-probe"
command mkdir -- "$test_mode_probe"
command chmod 500 -- "$test_mode_probe"
if (( EUID == 0 )) || [[ -w "$test_mode_probe" ]]; then
    printf 'SKIP: directory-permission tests require non-root POSIX mode enforcement\n'
    printf 'All supported Atuin tests passed.\n'
    exit 0
fi

new_home root-config
command mkdir -- "$HOME/.config"
printf 'personal configuration\n' > "$HOME/.config/personal"
command chmod 500 -- "$HOME/.config"
test_root_owned_directory="$HOME/.config"
prepare_atuin > "$test_root/output" 2>&1
printf '%q ' chown -- "$test_user_uid:$test_user_gid" "$HOME/.config" > "$test_root/expected-sudo"
printf '\n' >> "$test_root/expected-sudo"
cmp -s "$test_root/expected-sudo" "$test_sudo_calls" ||
    fail 'repair must chown only the blocked .config directory, without recursion'
[[ "$(< "$HOME/.config/personal")" == 'personal configuration' ]] ||
    fail 'repair modified personal configuration'
[[ -w "$HOME/.config" && -x "$HOME/.config" ]] || fail 'repair did not restore access'
: > "$test_sudo_calls"
prepare_atuin > "$test_root/output" 2>&1
assert_no_sudo 'repeated setup attempted another ownership repair'
printf 'PASS: root-owned .config gets a single nonrecursive ownership repair\n'

for test_mode in 500 000; do
    new_home "owned-mode-$test_mode"
    command mkdir -- "$HOME/blocked"
    command chmod "$test_mode" -- "$HOME/blocked"
    prepare_atuin_directory "$HOME/blocked" > "$test_root/output" 2>&1
    [[ -w "$HOME/blocked" && -x "$HOME/blocked" ]] ||
        fail "own directory with mode $test_mode was not repaired"
    assert_no_sudo 'repair of a user-owned directory attempted sudo'
done

new_home root-mode-000
command mkdir -- "$HOME/blocked"
command chmod 000 -- "$HOME/blocked"
test_root_owned_directory="$HOME/blocked"
prepare_atuin_directory "$HOME/blocked" > "$test_root/output" 2>&1
[[ -w "$HOME/blocked" && -x "$HOME/blocked" ]] ||
    fail 'root-owned directory with mode 000 was not repaired'
printf 'PASS: blocked user-owned/root-owned directories, including mode 000, regain access\n'

new_home repair-failures
command mkdir -- "$HOME/blocked"
command chmod 500 -- "$HOME/blocked"
test_root_owned_directory="$HOME/blocked"
test_fail_sudo=1
expect_directory_failure "$HOME/blocked" 'sudo failure was ignored'
assert_mode "$HOME/blocked" 500 'sudo failure was followed by chmod'

test_fail_sudo=0
test_root_owned_directory=''
test_failed_chmod_directory="$HOME/blocked"
expect_directory_failure "$HOME/blocked" 'chmod failure was ignored'
assert_mode "$HOME/blocked" 500 'failed chmod unexpectedly changed the directory'

test_failed_chmod_directory=''
test_other_owned_directory="$HOME/blocked"
: > "$test_sudo_calls"
expect_directory_failure "$HOME/blocked" 'a blocked directory owned by another user was repaired'
assert_no_sudo "another user's directory received a privileged change"
assert_mode "$HOME/blocked" 500 "another user's directory mode was changed"
printf 'PASS: sudo/chmod failures propagate and other owners are preserved\n'

new_home boundary
test_outside_directory="$test_root/boundary-other"
command mkdir -- "$test_outside_directory"
command chmod 500 -- "$test_outside_directory"
test_root_owned_directory="$test_outside_directory"
expect_directory_failure "$test_outside_directory" 'HOME-similar prefix was accepted as within HOME'
assert_no_sudo 'an external directory received a privileged change'
assert_mode "$test_outside_directory" 500 'external directory permissions changed'

if ln -s "$test_outside_directory" "$HOME/external-link" 2>/dev/null &&
   [[ -L "$HOME/external-link" ]]; then
    expect_directory_failure "$HOME/external-link" 'a symlink outside HOME was repaired'
    assert_no_sudo 'a symlink to an external directory received a privileged change'
    assert_mode "$test_outside_directory" 500 'symlink target permissions changed'
else
    printf 'SKIP: this environment does not support creating symlinks\n'
fi
command chmod 500 -- "$HOME"
expect_directory_failure "$HOME" 'the HOME directory itself was repaired'
assert_no_sudo 'HOME itself received a privileged change'
printf 'PASS: external paths, HOME-similar prefixes and symlink targets are protected\n'

printf 'All Atuin tests passed.\n'
