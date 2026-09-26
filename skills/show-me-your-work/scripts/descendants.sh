#!/usr/bin/env bash
# List the threads a BB thread's current run delegated to, at any depth,
# parents first: its children, their children, and so on. The run starts after
# <run-start-seq>, which run-start.sh prints (0 for a thread never cleared). A
# clear keeps the thread's children, so a child from an earlier run is left out
# unless this run messaged it with `bb thread tell`; then it counts from that
# message. A child created in the run counts in full, with every thread under
# it. The same rule applies one level down, from the time the child was
# created or messaged. `bb thread list --parent-thread` returns one level and
# skips hidden threads without --include-hidden, so this walks each level with
# that flag. Archived threads are listed too, since bb lists them unless asked
# for archived ones only. No project filter, so a descendant in another project
# is still found. Prints nothing when the run delegated to no thread; exits 1,
# printing nothing, when a level or a log it needs does not load.
# Usage: descendants.sh <thread-id> <run-start-seq>
# Output (TSV): thread	parent	after-seq	title
# `bb thread log <thread> --format json --all --after-seq <after-seq>` reads
# the part of each thread that belongs to the run.
set -euo pipefail

if [ "$#" -ne 2 ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
	printf 'usage: descendants.sh <thread-id> <run-start-seq>\n' >&2
	exit 1
fi

fail() { printf 'descendants: %s\n' "$1" >&2; exit 1; }

# The run's start time: when the event at <run-start-seq> was written. Nothing
# is filtered for a run that starts at the thread's beginning.
since=""
if [ "$2" -gt 0 ]; then
	# bb notes on stderr that more events exist; a failure is JSON on stdout.
	ev=$(bb thread log "$1" --format json --after-seq "$(($2 - 1))" --limit 1 2>/dev/null) || fail "cannot read event $2 of $1"
	since=$(jq -e --argjson s "$2" '.[0] | select(.seq == $s) | .createdAt' <<<"$ev") || fail "cannot read event $2 of $1"
fi

seen="$1"
# walk <parent> <since>: an empty <since> keeps every child in full.
walk() {
	local kids id created log tell
	kids=$(bb thread list --parent-thread "$1" --include-hidden --json) || return 1
	jq -e 'type == "array"' >/dev/null <<<"$kids" || return 1
	for id in $(jq -r '.[].id' <<<"$kids"); do
		# A parent loop would otherwise walk forever.
		grep -qxF "$id" <<<"$seen" && continue
		created=$(jq --arg id "$id" '.[] | select(.id == $id) | .createdAt' <<<"$kids")
		if [ -z "$2" ] || [ "$created" -ge "$2" ]; then
			tell="0 "
		else
			# An older child: the first message the parent sent it in the run.
			log=$(bb thread log "$id" --format json --all) || return 1
			jq -e 'type == "array"' >/dev/null <<<"$log" || return 1
			tell=$(jq -r --arg p "$1" --argjson since "$2" 'first(.[]
				| select(.type == "client/turn/requested" and .data.source == "tell"
					and .data.senderThreadId == $p and .createdAt >= $since))
				| "\(.seq - 1) \(.createdAt)"' <<<"$log")
			[ -n "$tell" ] || continue
		fi
		seen=$(printf '%s\n%s' "$seen" "$id")
		jq -r --arg id "$id" --arg after "${tell%% *}" '.[] | select(.id == $id)
			| [.id, .parentThreadId, $after, ((.title // "-") | gsub("[\t\r\n]"; " "))] | @tsv' <<<"$kids" || return 1
		walk "$id" "${tell#* }" || return 1
	done
}

out=$(walk "$1" "$since") || fail "cannot list the threads under $1"
[ -z "$out" ] || printf '%s\n' "$out"
