#!/usr/bin/env bash
# Rerunnable check for skills/show-me-your-work/scripts/run-start.sh.
# A stub `bb` serves a thread's raw event log with the events BB writes: the
# `system/operation` context_clear of `bb thread clear`, the
# `thread/context/cleared` of a provider's conversation reset, a compaction and
# an unrelated operation.
# Usage: run-start.test.sh <path to run-start.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/run-start-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub"

cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$S/call"
[ -n "\${FAIL:-}" ] && { echo '{"ok": false, "error": {"code": "unavailable", "message": "server unreachable"}}'; exit 1; }
cat "$S/events.json"
EOF
chmod +x "$S/stub/bb"

ev() { # seq type [operation status]
	if [ "$#" -eq 4 ]; then
		jq -nc --argjson s "$1" --arg t "$2" --arg o "$3" --arg st "$4" '{seq: $s, type: $t, threadId: "thr_a", data: {operation: $o, status: $st}}'
	else
		jq -nc --argjson s "$1" --arg t "$2" '{seq: $s, type: $t, threadId: "thr_a", data: {}}'
	fi
}
run() { env PATH="$S/stub:$PATH" BB_THREAD_ID=thr_a "$@" 2>/dev/null; }

fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1 = $2"; else echo "FAIL $1 got '$2' want '$3'"; fail=1; fi; }

echo "# a thread never cleared runs from the start"
{ ev 1 client/turn/requested; ev 2 turn/started; ev 3 thread/compacted; ev 4 turn/completed; } | jq -s . > "$S/events.json"
out=$(run bash "$script") && code=0 || code=$?
expect "exit" "$code" 0
expect "seq" "$out" 0
expect "reads its own raw log in full" "$(cat "$S/call")" "thread log --self --format json --all"

echo "# the latest clear wins, whichever kind; compactions, other operations and unfinished clears do not count"
{
	ev 1 client/turn/requested
	ev 5 system/operation context_clear completed
	ev 9 thread/context/cleared
	ev 12 thread/compacted
	ev 14 system/operation ownership_change completed
	ev 15 system/operation context_clear started
	ev 16 turn/completed
} | jq -s . > "$S/events.json"
expect "after a provider reset" "$(run bash "$script")" 9
{ ev 1 client/turn/requested; ev 9 thread/context/cleared; ev 20 system/operation context_clear completed; ev 21 client/turn/requested; } | jq -s . > "$S/events.json"
expect "after bb thread clear" "$(run bash "$script")" 20

echo "# a log that does not load fails and prints no seq"
out=$(run env FAIL=1 bash "$script") && code=0 || code=$?
expect "failed exit is non-zero" "$([ "$code" -ne 0 ] && echo yes || echo no)" yes
expect "failed output" "$out" ""

echo "# outside a BB thread it refuses"
out=$(env -u BB_THREAD_ID PATH="$S/stub:$PATH" bash "$script" 2>/dev/null) && code=0 || code=$?
expect "no thread exit is non-zero" "$([ "$code" -ne 0 ] && echo yes || echo no)" yes

[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
