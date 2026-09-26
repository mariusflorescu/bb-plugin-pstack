#!/usr/bin/env bash
# Rerunnable check for skills/show-me-your-work/scripts/descendants.sh.
# A stub `bb` holds a three-level tree (coordinator, sub-coordinator, worker,
# verifier) with hidden threads at every level, an archived worker, a child in
# another project and an unrelated tree, and lists threads the way BB does: one
# level per --parent-thread, hidden threads only with --include-hidden. A second
# tree was cleared: it has children from before the clear, one of them messaged
# after it, and children made after it. The stub serves raw event logs the way
# `bb thread log --format json` does, paged by --after-seq and --limit.
# Usage: descendants.test.sh <path to descendants.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/descendants-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub" "$S/logs"

cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
state="$S/threads.json" calls="$S/calls"
echo "\$*" >> "\$calls"
if [ "\$1 \$2" = "thread log" ]; then
	id="\$3"; after=-1; limit=""; prev=""
	for a in "\$@"; do [ "\$prev" = --after-seq ] && after="\$a"; [ "\$prev" = --limit ] && limit="\$a"; prev="\$a"; done
	[ "\$id" = "\${FAIL:-}" ] && { echo '{"ok": false, "error": {"code": "unavailable", "message": "server unreachable"}}'; exit 1; }
	[ -f "$S/logs/\$id.json" ] || { echo '{"ok": false, "error": {"code": "http_404", "message": "unknown thread"}}'; exit 1; }
	jq --argjson a "\$after" --arg l "\$limit" '[.[] | select(.seq > \$a)] | if \$l == "" then . else .[0:(\$l | tonumber)] end' "$S/logs/\$id.json"
	exit 0
fi
[ "\$1 \$2" = "thread list" ] || exit 2
parent=""; hidden=""; prev=""
for a in "\$@"; do [ "\$prev" = --parent-thread ] && parent="\$a"; [ "\$a" = --include-hidden ] && hidden=1; prev="\$a"; done
[ "\$parent" = "\${FAIL:-}" ] && { echo '{"ok": false, "error": {"code": "unavailable", "message": "server unreachable"}}'; exit 1; }
jq --arg p "\$parent" --arg h "\$hidden" '[.[] | select(.parentThreadId == \$p) | select(\$h != "" or .visibility == "visible")]' "\$state"
EOF
chmod +x "$S/stub/bb"

# thr_c was cleared at seq 50 (t=5000). Before the clear it spawned thr_old
# (with thr_old_kid) and thr_told; after it, it spawned thr_new (with
# thr_new_kid) and messaged thr_told at thr_told's seq 30 (t=6000). thr_told
# spawned thr_told_old before that message and thr_told_new after it, and
# messaged thr_told_old at t=6500. Messages from anyone else, or from thr_c
# before the clear, do not count.
cat > "$S/threads.json" <<'EOF'
[{"id":"thr_root","projectId":"proj","parentThreadId":null,"title":"coordinator","visibility":"visible","archivedAt":null,"createdAt":100},
 {"id":"thr_sub","projectId":"proj","parentThreadId":"thr_root","title":"sub-coordinator: track A","visibility":"visible","archivedAt":null,"createdAt":200},
 {"id":"thr_w1","projectId":"proj","parentThreadId":"thr_sub","title":"worker:\tone","visibility":"hidden","archivedAt":null,"createdAt":300},
 {"id":"thr_v1","projectId":"proj","parentThreadId":"thr_w1","title":null,"visibility":"hidden","archivedAt":null,"createdAt":400},
 {"id":"thr_w2","projectId":"proj","parentThreadId":"thr_sub","title":"worker: two","visibility":"visible","archivedAt":1790000000000,"createdAt":500},
 {"id":"thr_rev","projectId":"proj_other","parentThreadId":"thr_root","title":"reviewer","visibility":"hidden","archivedAt":null,"createdAt":600},
 {"id":"thr_rev_kid","projectId":"proj_other","parentThreadId":"thr_rev","title":"reviewer\nhelper","visibility":"visible","archivedAt":null,"createdAt":700},
 {"id":"thr_elsewhere","projectId":"proj","parentThreadId":null,"title":"unrelated chat","visibility":"visible","archivedAt":null,"createdAt":800},
 {"id":"thr_elsewhere_kid","projectId":"proj","parentThreadId":"thr_elsewhere","title":"unrelated child","visibility":"visible","archivedAt":null,"createdAt":900},
 {"id":"thr_loop","projectId":"proj","parentThreadId":"thr_loop2","title":"loop a","visibility":"visible","archivedAt":null,"createdAt":1000},
 {"id":"thr_loop2","projectId":"proj","parentThreadId":"thr_loop","title":"loop b","visibility":"visible","archivedAt":null,"createdAt":1100},
 {"id":"thr_c","projectId":"proj","parentThreadId":null,"title":"cleared coordinator","visibility":"visible","archivedAt":null,"createdAt":1000},
 {"id":"thr_old","projectId":"proj","parentThreadId":"thr_c","title":"old worker","visibility":"hidden","archivedAt":null,"createdAt":2000},
 {"id":"thr_old_kid","projectId":"proj","parentThreadId":"thr_old","title":"old helper","visibility":"visible","archivedAt":null,"createdAt":5500},
 {"id":"thr_told","projectId":"proj","parentThreadId":"thr_c","title":"resumed worker","visibility":"hidden","archivedAt":null,"createdAt":3000},
 {"id":"thr_told_old","projectId":"proj","parentThreadId":"thr_told","title":"resumed helper","visibility":"visible","archivedAt":null,"createdAt":5800},
 {"id":"thr_told_new","projectId":"proj","parentThreadId":"thr_told","title":"new helper","visibility":"visible","archivedAt":null,"createdAt":6200},
 {"id":"thr_new","projectId":"proj","parentThreadId":"thr_c","title":"new worker","visibility":"visible","archivedAt":null,"createdAt":5000},
 {"id":"thr_new_kid","projectId":"proj","parentThreadId":"thr_new","title":"new verifier","visibility":"hidden","archivedAt":1790000000000,"createdAt":5200}]
EOF

ev() { # seq createdAt type [source sender]
	jq -nc --argjson s "$1" --argjson t "$2" --arg ty "$3" --arg src "${4:-}" --arg snd "${5:-}" \
		'{seq: $s, createdAt: $t, type: $ty, threadId: "x", data: (if $src == "" then {} else {source: $src, initiator: "agent", senderThreadId: (if $snd == "" then null else $snd end)} end)}'
}
{ ev 1 1000 client/turn/requested spawn; ev 49 4900 turn/completed; ev 50 5000 system/operation; ev 51 5100 client/turn/requested tell; } | jq -s . > "$S/logs/thr_c.json"
{ ev 1 2000 client/turn/requested spawn; ev 2 3500 client/turn/requested tell thr_c; ev 3 5600 client/turn/requested tell thr_other; } | jq -s . > "$S/logs/thr_old.json"
{ ev 1 3000 client/turn/requested spawn; ev 10 4000 client/turn/requested tell thr_c; ev 20 5900 client/turn/requested tell thr_other; ev 30 6000 client/turn/requested tell thr_c; ev 31 6100 turn/started; ev 40 7000 client/turn/requested tell thr_c; } | jq -s . > "$S/logs/thr_told.json"
{ ev 1 5800 client/turn/requested spawn; ev 7 5900 client/turn/requested tell thr_told; ev 12 6500 client/turn/requested tell thr_told; } | jq -s . > "$S/logs/thr_told_old.json"

run() { : > "$S/calls"; env PATH="$S/stub:$PATH" "$@" 2>"$S/err"; }

fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else printf 'FAIL %s\n got:\n%s\n want:\n%s\n' "$1" "$2" "$3"; fail=1; fi; }

echo "# a run from the thread's start: every descendant at every depth, hidden and archived included, parents first"
out=$(run bash "$script" thr_root 0) && code=0 || code=$?
expect "exit" "$code" 0
expect "tree" "$out" "$(printf '%s\t%s\t%s\t%s\n' \
	thr_sub thr_root 0 "sub-coordinator: track A" \
	thr_w1 thr_sub 0 "worker: one" \
	thr_v1 thr_w1 0 "-" \
	thr_w2 thr_sub 0 "worker: two" \
	thr_rev thr_root 0 "reviewer" \
	thr_rev_kid thr_rev 0 "reviewer helper")"
expect "one list per thread in the tree and nothing else" "$(grep -c . "$S/calls")" 7
expect "every list passes --include-hidden" "$(grep -c 'thread list' "$S/calls")" "$(grep -c -- '--include-hidden' "$S/calls")"
expect "no project filter" "$(grep -c -- '--project' "$S/calls" || true)" 0

echo "# a run after a clear: children made in it in full, an older child it messaged from that message, nothing else"
out=$(run bash "$script" thr_c 50) && code=0 || code=$?
expect "cleared exit" "$code" 0
expect "cleared tree" "$out" "$(printf '%s\t%s\t%s\t%s\n' \
	thr_told thr_c 29 "resumed worker" \
	thr_told_old thr_told 11 "resumed helper" \
	thr_told_new thr_told 0 "new helper" \
	thr_new thr_c 0 "new worker" \
	thr_new_kid thr_new 0 "new verifier")"
expect "reads the run's first event, not the whole log" "$(grep -c -- 'thread log thr_c --format json --after-seq 49 --limit 1' "$S/calls")" 1
expect "reads no log of a thread made in the run" "$(grep -cE 'thread log thr_(new|told_new)' "$S/calls" || true)" 0

echo "# a leaf, or a run that delegated nothing, prints nothing"
out=$(run bash "$script" thr_v1 0) && code=0 || code=$?
expect "leaf exit" "$code" 0
expect "leaf output" "$out" ""

echo "# a level or a log that does not load fails the whole walk and prints no partial list"
out=$(run env FAIL=thr_w1 bash "$script" thr_root 0) && code=0 || code=$?
expect "failed list exit" "$code" 1
expect "failed list output" "$out" ""
expect "failed list names the root" "$(cat "$S/err")" "descendants: cannot list the threads under thr_root"
out=$(run env FAIL=thr_old bash "$script" thr_c 50) && code=0 || code=$?
expect "failed child log exit" "$code" 1
expect "failed child log output" "$out" ""
out=$(run env FAIL=thr_c bash "$script" thr_c 50) && code=0 || code=$?
expect "failed run start exit" "$code" 1
expect "failed run start output" "$out" ""
expect "failed run start names the event" "$(cat "$S/err")" "descendants: cannot read event 50 of thr_c"
out=$(run bash "$script" thr_c 52) && code=0 || code=$?
expect "missing run start event exit" "$code" 1

echo "# a parent loop ends"
out=$(run bash "$script" thr_loop 0) && code=0 || code=$?
expect "loop exit" "$code" 0
expect "loop output" "$out" "$(printf 'thr_loop2\tthr_loop\t0\tloop b')"

echo "# a missing or malformed run start is a usage error"
run bash "$script" thr_root >/dev/null && code=0 || code=$?
expect "no seq exit" "$code" 1
run bash "$script" thr_root abc >/dev/null && code=0 || code=$?
expect "bad seq exit" "$code" 1
run bash "$script" >/dev/null && code=0 || code=$?
expect "usage exit" "$code" 1

[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
