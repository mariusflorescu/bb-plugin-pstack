#!/usr/bin/env bash
# List every thread under a BB thread at any depth, parents first: its
# children, their children, and so on. `bb thread list --parent-thread` returns
# one level and skips hidden threads without --include-hidden, so this walks
# each level with that flag. Archived threads are listed too, since bb lists
# them unless asked for archived ones only. No project filter, so a descendant
# in another project is still found. Prints nothing when the thread has no
# children; exits 1, printing nothing, when a level does not list.
# Usage: descendants.sh <thread-id>
# Output (TSV): thread	parent	title
set -euo pipefail

if [ "$#" -ne 1 ]; then
	printf 'usage: descendants.sh <thread-id>\n' >&2
	exit 1
fi

seen="$1"
walk() {
	local kids id
	kids=$(bb thread list --parent-thread "$1" --include-hidden --json) || return 1
	jq -e 'type == "array"' >/dev/null <<<"$kids" || return 1
	for id in $(jq -r '.[].id' <<<"$kids"); do
		# A parent loop would otherwise walk forever.
		grep -qxF "$id" <<<"$seen" && continue
		seen=$(printf '%s\n%s' "$seen" "$id")
		jq -r --arg id "$id" '.[] | select(.id == $id)
			| [.id, .parentThreadId, ((.title // "-") | gsub("[\t\r\n]"; " "))] | @tsv' <<<"$kids" || return 1
		walk "$id" || return 1
	done
}

out=$(walk "$1") || { printf 'descendants: cannot list the threads under %s\n' "$1" >&2; exit 1; }
[ -z "$out" ] || printf '%s\n' "$out"
