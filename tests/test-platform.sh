#!/usr/bin/env bash
set -euo pipefail

# Stubbed platform/package tests: never contact APT or install real packages.
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

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Git Bash has no dpkg. This fallback only models the numeric versions in our
# fixtures; Linux hosts exercise their real dpkg version comparison instead.
if ! command -v dpkg >/dev/null 2>&1; then
    dpkg() {
        [[ "$#" == 4 && "$1" == --compare-versions && "$3" == ge ]] ||
            fail 'unexpected dpkg invocation'
        local actual_major actual_minor minimum_major minimum_minor
        IFS=. read -r actual_major actual_minor <<< "$2"
        IFS=. read -r minimum_major minimum_minor <<< "$4"
        actual_minor="${actual_minor:-0}"
        minimum_minor="${minimum_minor:-0}"
        (( 10#$actual_major > 10#$minimum_major ||
           (10#$actual_major == 10#$minimum_major && 10#$actual_minor >= 10#$minimum_minor) ))
    }
fi

calls="$test_root/calls"
policy_calls="$test_root/policy-calls"
test_missing_packages=''
empty_policy_package=''
failed_policy_package=''
failed_sudo_call=''
test_arch=arm64
sudo() {
    printf '%s\n' "$*" >> "$calls"
    [[ "$*" != "$failed_sudo_call" ]]
}
apt-cache() {
    [[ "$#" == 2 && "$1" == policy ]] || fail 'unexpected apt-cache invocation'
    printf '%s %s %s\n' "${LC_ALL:-unset}" "$1" "$2" >> "$policy_calls"
    if [[ "$2" == "$failed_policy_package" ]]; then
        printf 'simulated APT cache failure\n' >&2
        return 1
    fi
    [[ "$2" != "$empty_policy_package" ]] || return 0
    printf '%s:%s:\n  Installed: (none)\n' "$2" "$test_arch"
    if [[ " $test_missing_packages " == *" $2 "* ]]; then
        printf '  Candidate: (none)\n'
    else
        printf '  Candidate: 1.0-1\n'
    fi
}

# shellcheck source=../tools.sh
source "$repo_dir/tools.sh"

reset_calls() {
    : > "$calls"
    : > "$policy_calls"
    test_missing_packages=''
    empty_policy_package=''
    failed_policy_package=''
    failed_sudo_call=''
}
write_release() {
    printf 'ID=%s\nVERSION_ID=%s\nPRETTY_NAME="%s"\n' "$2" "$3" "$4" > "$test_root/$1"
}
assert_no_tool_install() {
    if grep -E '^apt-get install .*fastfetch' "$calls" >/dev/null; then
        fail "$1"
    fi
}

for platform in ubuntu debian raspbian; do
    case "$platform" in
        ubuntu) minimum=26.04; newer=26.10 ;;
        *) minimum=13; newer=14 ;;
    esac
    for version in "$minimum" "$newer"; do
        write_release supported "$platform" "$version" "Test $platform $version"
        detect_platform "$test_root/supported"
        [[ "$platform_id" == "$platform" ]] || fail 'wrong platform ID'
        [[ "$platform_name" == "Test $platform $version" ]] || fail 'wrong platform display name'
    done
done
printf 'PASS: supported Ubuntu, Debian and Raspbian release versions\n'

for entry in ubuntu:24.04 ubuntu:25.10 debian:12 raspbian:12 fedora:43 linuxmint:26.04; do
    platform="${entry%%:*}"
    version="${entry#*:}"
    write_release unsupported "$platform" "$version" "Unsupported $platform $version"
    printf 'ID_LIKE="ubuntu debian"\n' >> "$test_root/unsupported"
    if detect_platform "$test_root/unsupported" > "$test_root/error" 2>&1; then
        fail "unsupported release was accepted: $entry"
    fi
    grep -Fq "Unsupported $platform $version" "$test_root/error" ||
        fail 'unsupported-release error does not identify the detected system'
done
if detect_platform "$test_root/nonexistent" > "$test_root/error" 2>&1; then
    fail 'missing os-release should be rejected'
fi

# A missing field must not inherit a supported value from the caller.
ID=debian VERSION_ID=13 PRETTY_NAME='Inherited name'
printf 'ID=debian\n' > "$test_root/no-version"
if detect_platform "$test_root/no-version" > "$test_root/error" 2>&1; then
    fail 'missing version inherited VERSION_ID from caller'
fi
printf 'VERSION_ID=13\n' > "$test_root/no-id"
if detect_platform "$test_root/no-id" > "$test_root/error" 2>&1; then
    fail 'missing ID inherited ID from caller'
fi
printf 'ID=debian\nVERSION_ID=13\n' > "$test_root/no-name"
detect_platform "$test_root/no-name"
[[ "$platform_name" == debian ]] || fail 'missing display name did not fall back to ID'
unset ID VERSION_ID PRETTY_NAME
printf 'PASS: old/unknown/incomplete systems are rejected without inherited metadata\n'

expected_packages=(
    ca-certificates curl git
    fastfetch bat htop btop eza fzf ripgrep tealdeer
    fortune-mod fortunes-min cowsay lolcat starship zoxide fd-find duf
    git-delta atuin ncdu jq tmux
    zsh-autosuggestions zsh-syntax-highlighting
)
expected_install="apt-get install -y ${expected_packages[*]}"

# These architecture labels model repository responses; they do not emulate ARM.
for platform in debian raspbian; do
    for test_arch in arm64 armhf; do
        reset_calls
        install_packages "$platform" "Test $platform" > "$test_root/output" 2>&1
        [[ "$(wc -l < "$calls")" -eq 2 ]] || fail "$platform should only update and install"
        [[ "$(head -n 1 "$calls")" == 'apt-get update' ]] || fail 'package indexes must update first'
        grep -Fxq "$expected_install" "$calls" || fail "$platform changed or omitted tool packages"
        if grep -E 'universe|software-properties-common|add-apt-repository' "$calls" >/dev/null; then
            fail "$platform attempted to enable an Ubuntu repository"
        fi
        [[ "$(wc -l < "$policy_calls")" -eq "${#expected_packages[@]}" ]] ||
            fail 'not all desired packages were checked'
        if grep -Ev '^C policy ' "$policy_calls" >/dev/null; then
            fail 'APT policy must use the C locale'
        fi
    done
done
printf 'PASS: Debian/Raspbian ARM repository fixtures install the complete tool list without Universe\n'

reset_calls
install_packages ubuntu 'Test Ubuntu' > "$test_root/output" 2>&1
cat > "$test_root/expected-ubuntu" <<EOF
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y universe
apt-get update
$expected_install
EOF
cmp -s "$test_root/expected-ubuntu" "$calls" || fail 'Ubuntu repository setup or installation changed'
printf 'PASS: Ubuntu still enables Universe and installs the complete tool list\n'

reset_calls
test_missing_packages='starship atuin'
if install_packages raspbian 'Test Raspbian' > "$test_root/error" 2>&1; then
    fail 'missing APT candidates should abort installation'
fi
assert_no_tool_install 'tools were installed despite missing candidates'
for package in starship atuin; do
    grep -Fq "$package" "$test_root/error" || fail "missing package $package was not reported"
done

reset_calls
empty_policy_package=fastfetch
if install_packages debian 'Test Debian' > "$test_root/error" 2>&1; then
    fail 'empty APT policy should abort installation'
fi
assert_no_tool_install 'tools were installed despite empty policy'
grep -Fq fastfetch "$test_root/error" || fail 'empty-policy package was not reported'

reset_calls
failed_policy_package=fastfetch
if install_packages debian 'Test Debian' > "$test_root/error" 2>&1; then
    fail 'APT cache errors should abort installation'
fi
assert_no_tool_install 'tools were installed after an APT cache error'
printf 'PASS: missing/empty candidates and APT cache errors stop before tool installation\n'

for failed_call in 'apt-get update' 'apt-get install -y software-properties-common' 'add-apt-repository -y universe'; do
    reset_calls
    failed_sudo_call="$failed_call"
    if install_packages ubuntu 'Test Ubuntu' > "$test_root/error" 2>&1; then
        fail "repository failure was ignored: $failed_call"
    fi
    assert_no_tool_install "tools were installed after failure: $failed_call"
    [[ ! -s "$policy_calls" ]] || fail 'APT policy was queried after repository setup failed'
done
reset_calls
failed_sudo_call="$expected_install"
if install_packages debian 'Test Debian' > "$test_root/error" 2>&1; then
    fail 'tool installation failure was ignored'
fi
printf 'PASS: repository and package-installation failures propagate\n'

printf 'All platform tests passed.\n'
