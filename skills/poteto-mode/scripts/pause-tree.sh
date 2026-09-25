#!/usr/bin/env bash
# Pauses the work under a BB thread. Pauses every automation in the project that
# would re-prompt the thread or a descendant, then stops every descendant,
# hidden ones included. `bb thread stop` does not cascade, `--parent-thread`
# lists one level, and a stopped child's report starts a turn on an idle
# parent, so it walks the whole tree again after each round of stops until one
# pass finds every descendant settled. The thread itself keeps running.
# Prints what it paused and stopped; exits 1 when a thread will not settle.
#
# Usage: pause-tree.sh <thread-id>
set -u
root="${1:?usage: pause-tree.sh <thread-id>}"
project="${BB_PROJECT_ID:?BB_PROJECT_ID is not set}"
# BB batches child reports for 2s before delivering them to the parent.
settle="${PAUSE_TREE_SETTLE:-5}"

# Every descendant as "id<TAB>status<TAB>queuedWork<TAB>busy", parents first.
tree() {
	local kids id
	kids=$(bb thread list --parent-thread "$1" --include-hidden --json) || return 1
	jq -r '.[] | [.id, .status, .queuedWork,
		((.status | IN("pending", "starting", "active", "stopping")) or .queuedWork == "waiting")] | @tsv' <<<"$kids" || return 1
	for id in $(jq -r '.[].id' <<<"$kids"); do tree "$id" || return 1; done
}

rows=$(tree "$root") || { echo "error: cannot list the threads under $root" >&2; exit 1; }
autos=$(bb automation list --project "$project" --json) || { echo "error: cannot list automations in $project" >&2; exit 1; }
targets=$(printf '%s\n%s\n' "$root" "$(cut -f1 <<<"$rows")")
for id in $(jq -r --arg ids "$targets" '.[] | select(.enabled == true)
	| select((.targetThreadId // .execution.targetThreadId // "") | IN($ids | split("\n")[] | select(. != ""))) | .id' <<<"$autos"); do
	bb automation pause "$id" --project "$project" >/dev/null && echo "paused automation $id" \
		|| { echo "error: cannot pause automation $id" >&2; exit 1; }
done

for pass in 1 2 3 4 5 6 7 8 9 10; do
	busy=$(awk -F'\t' '$4 == "true" { print $1 }' <<<"$rows")
	[ -z "$busy" ] && { echo "settled $(grep -c . <<<"$rows") descendants of $root after $((pass - 1)) rounds of stops"; exit 0; }
	for id in $busy; do bb thread stop "$id" >/dev/null && echo "stopped $id" || echo "warn: bb thread stop $id failed" >&2; done
	sleep "$settle"
	rows=$(tree "$root") || { echo "error: cannot list the threads under $root" >&2; exit 1; }
done
echo "error: still running after 10 rounds of stops (id, status, queued work):" >&2
awk -F'\t' '$4 == "true" { print "  " $1, $2, $3 }' <<<"$rows" >&2
exit 1
