#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/read-from-trunk.sh.
# Builds a scratch plugin origin and a path-source checkout that sits on a
# feature branch with different content, stubs `bb plugin source`, and asserts
# the script prints trunk, follows trunk when it moves, and fails loud on a
# source with no trunk.
# Usage: read-from-trunk.test.sh <path to read-from-trunk.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/read-from-trunk-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub" "$S/storage"
cd "$S"

playbook=skills/poteto-mode/playbooks/autopilot-full.md
git init -q --bare -b main origin.git
git init -q -b main plugin
cd plugin
git config user.email t@t
git config user.name t
mkdir -p "$(dirname "$playbook")" "sub/$(dirname "$playbook")"
echo "trunk v1" > "$playbook"
echo "sub v1" > "sub/$playbook"
git add . && git commit -qm v1
git remote add origin "$S/origin.git" && git push -q origin main
git checkout -qb feature && echo "local edit" > "$playbook" && git commit -qam local
cd "$S"
git init -q -b main lonely

cat > "$S/stub/bb" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "plugin source pstack --json" ] || exit 2
printf '%s\n' "$STUB_SOURCE"
EOF
chmod +x "$S/stub/bb"

fail=0
run() {
	STUB_SOURCE="$1" PATH="$S/stub:$PATH" BB_THREAD_STORAGE="$S/storage" bash "$script" "${2:-$playbook}" 2>"$S/err"
}
expect() {
	local name="$1" source="$2" want="$3" got
	got=$(run "$source") || got="exit $?"
	if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name got '$got' want '$want'"; fail=1; fi
}
expect_fail() {
	local name="$1" source="$2" want="$3" file="${4:-$playbook}"
	if run "$source" "$file" >/dev/null; then echo "FAIL $name exited 0"; fail=1
	elif grep -q "$want" "$S/err"; then echo "ok   $name"
	else echo "FAIL $name stderr '$(cat "$S/err")' lacks '$want'"; fail=1; fi
}

expect "path source reads trunk, not the checkout" "{\"resolved\":\"path:$S/plugin\"}" "trunk v1"
trunk=$(git -C "$S/origin.git" rev-parse main)
if grep -q "@$trunk\$" "$S/err"; then echo "ok   revision on stderr"; else echo "FAIL revision '$(cat "$S/err")' lacks $trunk"; fail=1; fi

(cd "$S/plugin" && git checkout -q main && echo "trunk v2" > "$playbook" && git commit -qam v2 && git push -q origin main)
expect "follows trunk when it moves" "{\"resolved\":\"path:$S/plugin\"}" "trunk v2"
expect "git source with a ref" "{\"resolved\":\"git:file://$S/origin.git@main\"}" "trunk v2"
expect "git source as a bare path" "{\"resolved\":\"git:$S/origin.git\"}" "trunk v2"
expect "git source with a subdirectory" "{\"resolved\":\"git:$S/origin.git\",\"subdirectory\":\"sub\"}" "sub v1"

expect_fail "path source without origin" "{\"resolved\":\"path:$S/lonely\"}" "no origin remote"
expect_fail "npm source" '{"resolved":"npm:pstack@1.0.0"}' "no git trunk"
expect_fail "file missing on trunk" "{\"resolved\":\"path:$S/plugin\"}" "is not on trunk" skills/poteto-mode/playbooks/nope.md
exit $fail
