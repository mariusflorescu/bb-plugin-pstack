#!/usr/bin/env bash
# Pauses the work under a BB thread. Pauses every automation in the project that
# would re-prompt the thread or a descendant, then settles every descendant,
# hidden ones included. `bb thread stop` does not cascade, `--parent-thread`
# lists one level, a stopped child's report starts a turn on an idle parent, and
# a stop leaves queued messages to dispatch later, so each pass walks the whole
# tree again, discards the queued wake-ups this program created, and stops what
# still runs, until one pass finds every descendant settled. A queued message is
# the program's when a thread in this tree sent it or it is the due notice of an
# automation a thread in this tree created. Each discarded message is appended
# as one JSON line to $BB_THREAD_STORAGE/pause-tree-<thread-id>.jsonl for the
# resume note. Any other queued message (the user's, a retry, another program's)
# stays queued and its thread is never stopped. The thread itself keeps running.
# Prints what it paused, discarded and stopped; exits 1 when a thread will not
# settle or holds queued messages this program did not create.
#
# Usage: pause-tree.sh <thread-id>
set -u
root="${1:?usage: pause-tree.sh <thread-id>}"
project="${BB_PROJECT_ID:?BB_PROJECT_ID is not set}"
saved="${BB_THREAD_STORAGE:?BB_THREAD_STORAGE is not set}/pause-tree-$root.jsonl"
# BB batches child reports for 2s before delivering them to the parent.
settle="${PAUSE_TREE_SETTLE:-5}"

# Every descendant as "id<TAB>status<TAB>queuedWork", parents first.
tree() {
	local kids id
	kids=$(bb thread list --parent-thread "$1" --include-hidden --json) || return 1
	jq -r '.[] | [.id, .status, .queuedWork] | @tsv' <<<"$kids" || return 1
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

held=""; settled=no
for pass in 1 2 3 4 5 6 7 8 9 10; do
	tree_ids=$(printf '%s\n%s\n' "$root" "$(cut -f1 <<<"$rows")")
	acted=no
	for id in $(awk -F'\t' '$3 != "none" { print $1 }' <<<"$rows"); do
		grep -qxF "$id" <<<"$held" && continue
		queue=$(bb thread queue list "$id" --json) || { echo "error: cannot list the queued messages of $id" >&2; exit 1; }
		while IFS=$'\t' read -r mid ours; do
			[ -z "$mid" ] && continue
			if [ "$ours" = false ]; then held=$(printf '%s\n%s' "$held" "$id"); continue; fi
			row=$(jq -c --arg m "$mid" '.[] | select(.id == $m)' <<<"$queue")
			bb thread queue delete "$id" "$mid" >/dev/null || { echo "warn: cannot discard $mid on $id" >&2; acted=yes; continue; }
			printf '%s\n' "$row" >> "$saved"
			echo "discarded queued message $mid on $id, saved to $saved"
			acted=yes
		done < <(jq -r --arg ids "$tree_ids" --argjson autos "$autos" '
			($ids | split("\n") | map(select(. != ""))) as $tree
			| [$autos[] | select((.createdByThreadId // "") | IN($tree[])) | .id] as $own
			| .[] | ([.content[]? | select(.type == "text") | .text][0] // "") as $text
			| [.id, ((.initiator == "agent" and ((.senderThreadId // "") | IN($tree[])))
				or (.origin == "plugin" and ([$text | capture("^\\[bb automation due:(?<a>[^\\]]+)\\]") | .a][0] // "" | IN($own[]))))]
			| @tsv' <<<"$queue")
	done
	busy=$(HELD="$held" awk -F'\t' 'BEGIN { n = split(ENVIRON["HELD"], h, "\n"); for (i = 1; i <= n; i++) skip[h[i]] = 1 }
		$2 ~ /^(pending|starting|active|stopping)$/ && !($1 in skip) { print $1 }' <<<"$rows")
	[ -z "$busy" ] && [ "$acted" = no ] && { settled=yes; break; }
	for id in $busy; do bb thread stop "$id" >/dev/null && echo "stopped $id" || echo "warn: bb thread stop $id failed" >&2; done
	sleep "$settle"
	rows=$(tree "$root") || { echo "error: cannot list the threads under $root" >&2; exit 1; }
done

if [ "$settled" = yes ] && [ -z "$held" ]; then
	echo "settled $(grep -c . <<<"$rows") descendants of $root after $((pass - 1)) rounds"
	exit 0
fi
[ "$settled" = no ] && {
	echo "error: not settled after 10 rounds of stops (thread, status, queued work):" >&2
	BUSY="$busy" HELD="$held" awk -F'\t' 'BEGIN { n = split(ENVIRON["BUSY"], b, "\n"); for (i = 1; i <= n; i++) show[b[i]] = 1
			n = split(ENVIRON["HELD"], h, "\n"); for (i = 1; i <= n; i++) skip[h[i]] = 1 }
		$1 in show || ($3 != "none" && !($1 in skip)) { print "  " $1, $2, $3 }' <<<"$rows" >&2
}
[ -n "$held" ] && {
	echo "error: left queued messages this program did not create, and never stopped their threads (thread, status, message, initiator, sender, waiting on):" >&2
	for id in $(printf '%s\n' "$held" | sed '/^$/d' | sort -u); do
		st=$(awk -F'\t' -v id="$id" '$1 == id { print $2 }' <<<"$rows")
		bb thread queue list "$id" --json | jq -r --arg id "$id" --arg st "$st" \
			'.[] | "  \($id) \($st) \(.id) \(.initiator) \(.senderThreadId // "-") \(.waitingOn.kind // "turn")"' >&2
	done
}
exit 1
