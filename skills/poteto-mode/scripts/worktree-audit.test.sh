#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/worktree-audit.sh.
# Builds a scratch repo with six worktrees and a stub `bb`, runs the audit, and
# asserts each row's ENV, LAST_THREAD flags and BUCKET. Stub paths use the
# non-canonical $TMPDIR form while git lists canonical paths, so a pass also
# proves the path canonicalization.
# Usage: worktree-audit-test.sh <path to worktree-audit.sh>
set -eu
audit="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/wt-audit-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub"
cd "$S"

git init -q --bare origin.git
git init -q -b main repo
cd repo
git config user.email t@t
git config user.name t
echo a > a.txt && git add a.txt && git commit -qm init
git remote add origin "$S/origin.git" && git push -q origin main
wt() { git worktree add -q -b "$1" "$S/wt-$1" && (cd "$S/wt-$1" && echo "$1" > "$1.txt" && git add . && git commit -qm "$1"); }
wt merged && git merge -q --ff-only merged && git push -q origin main
for name in wip inuse running child recent; do wt "$name"; done
echo edited >> "$S/wt-wip/a.txt"

now=$(( $(date +%s) * 1000 )); old=$(( now - 10 * 86400 * 1000 ))
envrow() { printf '{"id":"env_%s","path":"%s"}' "$1" "$S/wt-$1"; }
printf '[%s,%s,%s,%s,%s]\n' "$(envrow merged)" "$(envrow inuse)" "$(envrow running)" "$(envrow child)" "$(envrow recent)" > "$S/stub/envs.json"
cat > "$S/stub/threads.json" <<EOF
[{"id":"thr_a","environmentId":"env_merged","status":"idle","pinnedAt":null,"parentThreadId":null,"updatedAt":$old},
 {"id":"thr_b","environmentId":"env_inuse","status":"idle","pinnedAt":$old,"parentThreadId":null,"updatedAt":$old},
 {"id":"thr_c","environmentId":"env_running","status":"stopping","pinnedAt":null,"parentThreadId":null,"updatedAt":$old},
 {"id":"thr_d","environmentId":"env_child","status":"idle","pinnedAt":null,"parentThreadId":"thr_b","updatedAt":$old},
 {"id":"thr_e","environmentId":"env_recent","status":"idle","pinnedAt":null,"parentThreadId":null,"updatedAt":$now}]
EOF
cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
[ -n "\${BB_STUB_FAIL:-}" ] && { echo '{"ok":false,"error":{"code":"down","message":"down"}}'; exit 1; }
case "\$1 \$2" in
	"environment list") cat "$S/stub/envs.json" ;;
	"thread list") cat "$S/stub/threads.json" ;;
	*) exit 2 ;;
esac
EOF
chmod +x "$S/stub/bb"

fail=0
check() {
	local out="$1" name="$2" want="$3"
	local got
	got=$(awk -F'\t' -v n="/wt-$name" 'substr($10, length($10) - length(n) + 1) == n { print $7 "|" $9 }' <<<"$out" | sed "s/[0-9-]\{10\}/DATE/")
	if [ "$got" = "$want" ]; then echo "ok   $name $got"; else echo "FAIL $name got '$got' want '$want'"; fail=1; fi
}

out=$(PATH="$S/stub:$PATH" bash "$audit" "$S/repo" 2>/dev/null)
check "$out" wip "-|hold-wip"
check "$out" merged "env_merged|safe"
check "$out" inuse "env_inuse|hold-in-use"
check "$out" running "env_running|hold-in-use"
check "$out" child "env_child|hold-in-use"
check "$out" recent "env_recent|verify-recent-chat"
grep -q $'env_child\tDATE,pinned' <<<"$(sed "s/[0-9-]\{10\}/DATE/" <<<"$out")" && echo "ok   child inherits pinned from its parent" || { echo "FAIL child LAST_THREAD lacks pinned"; fail=1; }

down=$(BB_STUB_FAIL=1 PATH="$S/stub:$PATH" bash "$audit" "$S/repo" 2>&1)
grep -q '^warn: bb unavailable' <<<"$down" && echo "ok   bb down warns" || { echo "FAIL bb down did not warn"; fail=1; }
check "$down" inuse "-|review"

echo
echo "$out"
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
