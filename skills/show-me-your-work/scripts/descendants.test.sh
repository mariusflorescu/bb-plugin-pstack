#!/usr/bin/env bash
# Rerunnable check for skills/show-me-your-work/scripts/descendants.sh.
# A stub `bb` holds a three-level tree (coordinator, sub-coordinator, worker,
# verifier) with hidden threads at every level, an archived worker, a child in
# another project and an unrelated tree, and lists threads the way BB does: one
# level per --parent-thread, hidden threads only with --include-hidden.
# Usage: descendants.test.sh <path to descendants.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/descendants-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub"

cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
state="$S/threads.json" calls="$S/calls"
[ "\$1 \$2" = "thread list" ] || exit 2
echo "\$*" >> "\$calls"
parent=""; hidden=""; prev=""
for a in "\$@"; do [ "\$prev" = --parent-thread ] && parent="\$a"; [ "\$a" = --include-hidden ] && hidden=1; prev="\$a"; done
[ "\$parent" = "\${FAIL:-}" ] && { echo '{"ok": false, "error": {"code": "unavailable", "message": "server unreachable"}}'; exit 1; }
jq --arg p "\$parent" --arg h "\$hidden" '[.[] | select(.parentThreadId == \$p) | select(\$h != "" or .visibility == "visible")]' "\$state"
EOF
chmod +x "$S/stub/bb"

cat > "$S/threads.json" <<'EOF'
[{"id":"thr_root","projectId":"proj","parentThreadId":null,"title":"coordinator","visibility":"visible","archivedAt":null},
 {"id":"thr_sub","projectId":"proj","parentThreadId":"thr_root","title":"sub-coordinator: track A","visibility":"visible","archivedAt":null},
 {"id":"thr_w1","projectId":"proj","parentThreadId":"thr_sub","title":"worker:\tone","visibility":"hidden","archivedAt":null},
 {"id":"thr_v1","projectId":"proj","parentThreadId":"thr_w1","title":null,"visibility":"hidden","archivedAt":null},
 {"id":"thr_w2","projectId":"proj","parentThreadId":"thr_sub","title":"worker: two","visibility":"visible","archivedAt":1790000000000},
 {"id":"thr_rev","projectId":"proj_other","parentThreadId":"thr_root","title":"reviewer","visibility":"hidden","archivedAt":null},
 {"id":"thr_rev_kid","projectId":"proj_other","parentThreadId":"thr_rev","title":"reviewer\nhelper","visibility":"visible","archivedAt":null},
 {"id":"thr_elsewhere","projectId":"proj","parentThreadId":null,"title":"unrelated chat","visibility":"visible","archivedAt":null},
 {"id":"thr_elsewhere_kid","projectId":"proj","parentThreadId":"thr_elsewhere","title":"unrelated child","visibility":"visible","archivedAt":null},
 {"id":"thr_loop","projectId":"proj","parentThreadId":"thr_loop2","title":"loop a","visibility":"visible","archivedAt":null},
 {"id":"thr_loop2","projectId":"proj","parentThreadId":"thr_loop","title":"loop b","visibility":"visible","archivedAt":null}]
EOF

run() { : > "$S/calls"; env PATH="$S/stub:$PATH" "$@" 2>"$S/err"; }

fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else printf 'FAIL %s\n got:\n%s\n want:\n%s\n' "$1" "$2" "$3"; fail=1; fi; }

echo "# every descendant at every depth, hidden and archived included, parents first"
out=$(run bash "$script" thr_root) && code=0 || code=$?
expect "exit" "$code" 0
expect "tree" "$out" "$(printf '%s\t%s\t%s\n' \
	thr_sub thr_root "sub-coordinator: track A" \
	thr_w1 thr_sub "worker: one" \
	thr_v1 thr_w1 "-" \
	thr_w2 thr_sub "worker: two" \
	thr_rev thr_root "reviewer" \
	thr_rev_kid thr_rev "reviewer helper")"
expect "one list per thread in the tree" "$(grep -c . "$S/calls")" 7
expect "every level passes --include-hidden" "$(grep -vc -- '--include-hidden' "$S/calls" || true)" 0
expect "no project filter" "$(grep -c -- '--project' "$S/calls" || true)" 0

echo "# a thread with no children prints nothing"
out=$(run bash "$script" thr_v1) && code=0 || code=$?
expect "leaf exit" "$code" 0
expect "leaf output" "$out" ""

echo "# a level that does not list fails the whole walk and prints no partial list"
out=$(run env FAIL=thr_w1 bash "$script" thr_root) && code=0 || code=$?
expect "failed exit" "$code" 1
expect "failed output" "$out" ""
expect "failed names the root" "$(cat "$S/err")" "descendants: cannot list the threads under thr_root"

echo "# a parent loop ends"
out=$(run bash "$script" thr_loop) && code=0 || code=$?
expect "loop exit" "$code" 0
expect "loop output" "$out" "$(printf 'thr_loop2\tthr_loop\tloop b')"

echo "# no thread id is a usage error"
run bash "$script" >/dev/null && code=0 || code=$?
expect "usage exit" "$code" 1

[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
