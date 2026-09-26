#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/read-from-trunk.sh.
# Builds scratch plugin origins and path-source checkouts that sit on a feature
# branch with different content, stubs `bb plugin source` with the response
# shapes BB 0.44 returns, and asserts the script prints trunk, follows trunk when
# it moves, reads a plugin nested in its repository under its own prefix, reads
# the published repository from a machine without the server's install path, and
# fails loud on a source with no trunk.
# Usage: read-from-trunk.test.sh <path to read-from-trunk.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/read-from-trunk-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub" "$S/storage"
cd "$S"

playbook=skills/poteto-mode/playbooks/autopilot-full.md
nest=plugins/pstack
commit() { git -C "$1" add . && git -C "$1" -c user.email=t@t -c user.name=t commit -qm "$2"; }
git init -q --bare -b main origin.git
git init -q -b main plugin
mkdir -p "plugin/$(dirname "$playbook")" "plugin/sub/$(dirname "$playbook")"
echo "trunk v1" > "plugin/$playbook"
echo "sub v1" > "plugin/sub/$playbook"
commit plugin v1
git -C plugin remote add origin "$S/origin.git" && git -C plugin push -q origin main
git -C plugin checkout -qb release/v2 && echo "release v2" > "plugin/$playbook" && commit plugin release && git -C plugin push -q origin release/v2
git -C plugin checkout -qb feature main && echo "local edit" > "plugin/$playbook" && commit plugin local
git clone -q origin.git relative
git -C relative remote set-url origin ../origin.git
git init -q -b main lonely

# A path install of a plugin nested in its repository (`bb plugin install
# path:<repo> --plugin pstack`) stores the plugin directory, not the repository.
git init -q --bare -b main nested-origin.git
git init -q -b main nested
mkdir -p "nested/$(dirname "$playbook")" "nested/$nest/$(dirname "$playbook")"
echo "repo root v1" > "nested/$playbook"
echo "nested trunk v1" > "nested/$nest/$playbook"
commit nested v1
git -C nested remote add origin ../nested-origin.git && git -C nested push -q origin main
git -C nested checkout -qb feature && echo "nested local edit" > "nested/$nest/$playbook" && commit nested local
git clone -q nested-origin.git nested-abs

# BB installs plugins on its server, and a thread may run on another machine.
# server-host/ is the server's filesystem: a nested path install on a feature
# branch with its own origin, and a bare repository for a git install from a
# local path. The execution host does not have server-host/ (on_other_host moves
# it away), so the script reads the published repository that trunk-url names,
# where the plugin sits at the root. The mapping below keeps that fetch offline.
published=$(head -n 1 "$(dirname "$script")/trunk-url")
git init -q --bare -b main published.git
git init -q -b main pub
mkdir -p "pub/$(dirname "$playbook")" "pub/$nest/$(dirname "$playbook")"
echo "published trunk v1" > "pub/$playbook"
echo "published nested decoy" > "pub/$nest/$playbook"
commit pub v1
git -C pub remote add origin "$S/published.git" && git -C pub push -q origin main
git init -q --bare -b main server-origin.git
git init -q -b main server-host/src
mkdir -p "server-host/src/$nest/$(dirname "$playbook")"
echo "server trunk v1" > "server-host/src/$nest/$playbook"
commit server-host/src v1
git -C server-host/src remote add origin "$S/server-origin.git" && git -C server-host/src push -q origin main
git -C server-host/src checkout -qb feature && echo "server local edit" > "server-host/src/$nest/$playbook" && commit server-host/src local
git clone -q --bare server-origin.git server-host/pstack.git
on_other_host() { mv "$S/server-host" "$S/server-host.away"; "$@"; mv "$S/server-host.away" "$S/server-host"; }

cat > "$S/stub/bb" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "plugin source pstack --json" ] || exit 2
printf '%s\n' "$STUB_SOURCE"
EOF
chmod +x "$S/stub/bb"

# `bb plugin source pstack --json` as BB 0.44 prints it. A path install repeats
# its source in both fields (captured from a path install). A git install keeps
# the source as the user typed it in `requested` and prints `<url>@<ref>
# (<commit>)` in `resolved` (installedUpdateVersion in plugin-registration.ts,
# gitResolvedVersion in update-resolver.ts); `subdirectory` appears only when set.
path_source() {
	jq -cn --arg s "path:$1" '{requested: $s, resolved: $s, engines: {bb: ">=0.43", bbPluginSdk: ">=0.4.84"},
		installedAt: 1790375158949, history: [{version: "32f7908198aae515bc477802de3b52ebb0914796", activatedAt: 1790371567761}]}'
}
git_source() {
	jq -cn --arg req "$1" --arg res "$2 (32f7908198aa)" --arg sub "${3:-}" '{requested: $req, resolved: $res}
		+ (if $sub == "" then {} else {subdirectory: $sub} end)
		+ {engines: {}, installedAt: 1790375158949, history: [{version: "32f7908198aae515bc477802de3b52ebb0914796", activatedAt: 1790371567761}]}'
}

fail=0
run() {
	# BB turns a scheme-less git source into https://; this maps that host to the scratch origins,
	# and the published repository to its scratch stand-in.
	STUB_SOURCE="$1" PATH="$S/stub:$PATH" BB_THREAD_STORAGE="$S/storage" \
		GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.$S/.insteadOf" GIT_CONFIG_VALUE_0="https://git.example.test/" \
		GIT_CONFIG_KEY_1="url.$S/published.git.insteadOf" GIT_CONFIG_VALUE_1="$published" \
		bash "$script" "${2:-$playbook}" 2>"$S/err"
}
expect() {
	local name="$1" source="$2" want="$3" got
	got=$(run "$source") || got="exit $? ($(cat "$S/err"))"
	if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name got '$got' want '$want'"; fail=1; fi
}
expect_fail() {
	local name="$1" source="$2" want="$3" file="${4:-$playbook}"
	if run "$source" "$file" >/dev/null; then echo "FAIL $name exited 0"; fail=1
	elif grep -q "$want" "$S/err"; then echo "ok   $name"
	else echo "FAIL $name stderr '$(cat "$S/err")' lacks '$want'"; fail=1; fi
}

expect "path source reads trunk, not the checkout" "$(path_source "$S/plugin")" "trunk v1"
trunk=$(git -C "$S/origin.git" rev-parse main)
if grep -q "@$trunk\$" "$S/err"; then echo "ok   revision on stderr"; else echo "FAIL revision '$(cat "$S/err")' lacks $trunk"; fail=1; fi

git -C plugin checkout -q main && echo "trunk v2" > "plugin/$playbook" && commit plugin v2 && git -C plugin push -q origin main
expect "follows trunk when it moves" "$(path_source "$S/plugin")" "trunk v2"
expect "path source with a relative origin" "$(path_source "$S/relative")" "trunk v2"
expect "nested path install reads under its prefix" "$(path_source "$S/nested-abs/$nest")" "nested trunk v1"
expect "nested path install with a relative origin" "$(path_source "$S/nested/$nest")" "nested trunk v1"

expect "git source as a bare path" "$(git_source "git:$S/origin.git" "$S/origin.git@HEAD")" "trunk v2"
expect "git source with a ref containing /" "$(git_source "git:$S/origin.git@release/v2" "$S/origin.git@release/v2")" "trunk v2"
expect "git source without a scheme" "$(git_source "git:git.example.test/origin.git@ref:release/v2" "https://git.example.test/origin.git@release/v2")" "trunk v2"
expect "bare https source" "$(git_source "https://git.example.test/origin.git@main" "https://git.example.test/origin.git@main")" "trunk v2"
expect "git source pinned to a semver range" "$(git_source "git:$S/origin.git@semver:^1.0.0" "$S/origin.git@v1.2.0")" "trunk v2"
expect "git source with a subdirectory" "$(git_source "git:$S/origin.git" "$S/origin.git@HEAD" sub)" "sub v1"

expect "server path install read on the server's host" "$(path_source "$S/server-host/src/$nest")" "server trunk v1"
on_other_host expect "server path install read from another host" "$(path_source "$S/server-host/src/$nest")" "published trunk v1"
if grep -q "@$(git -C "$S/published.git" rev-parse main)\$" "$S/err"; then echo "ok   published revision on stderr"; else echo "FAIL revision '$(cat "$S/err")' is not the published trunk"; fail=1; fi
expect "server git path read on the server's host" "$(git_source "git:$S/server-host/pstack.git" "$S/server-host/pstack.git@HEAD" "$nest")" "server trunk v1"
on_other_host expect "server git path read from another host" "$(git_source "git:$S/server-host/pstack.git" "$S/server-host/pstack.git@HEAD" "$nest")" "published trunk v1"
repo_url=$(jq -r '.repository.url | sub("^git\\+"; "")' "$(dirname "$script")/../../../package.json")
if [ "$published" = "$repo_url" ]; then echo "ok   trunk-url is package.json's repository"; else echo "FAIL trunk-url '$published' is not package.json's '$repo_url'"; fail=1; fi

expect_fail "path source without origin" "$(path_source "$S/lonely")" "no origin remote"
expect_fail "npm source" '{"requested":"npm:pstack@1.0.0","resolved":"pstack@1.0.0","integrity":"sha512-x","registry":"https://registry.npmjs.org","engines":{},"installedAt":1,"history":[]}' "no git trunk"
expect_fail "builtin source" '{"requested":"builtin:pstack","resolved":"builtin:pstack","engines":{},"installedAt":1,"history":[]}' "no git trunk"
expect_fail "file missing on trunk" "$(path_source "$S/plugin")" "is not on trunk" skills/poteto-mode/playbooks/nope.md
exit $fail
