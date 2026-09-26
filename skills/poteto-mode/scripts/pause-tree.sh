#!/usr/bin/env bash
# Pauses the work under a BB thread. Pauses every automation that would
# re-prompt the thread or a descendant, then settles every descendant, hidden
# ones included. `bb thread stop` does not cascade, `--parent-thread` lists one
# level and crosses projects, a stopped child's report starts a turn on an idle
# parent, and a stop leaves queued messages to dispatch later, so each pass
# walks the whole tree again, pauses the automations aimed at it in every
# project a thread of it lives in, discards the queued wake-ups this program
# created on the thread and every descendant, and stops what still runs, until
# one pass finds every descendant settled. A queued message is the program's
# when a thread in this tree sent it or it is the due notice of an automation a
# thread in this tree created. Before a message is discarded, it is saved as one
# JSON line, one per message id, to $BB_THREAD_STORAGE/pause-tree-<thread-id>.jsonl
# for the resume note, and read back. When that save fails, the script stops
# there and discards nothing more. Any other queued message (the user's, a
# retry, a system notice, another program's) stays queued and its thread is
# never stopped. The thread itself is
# never stopped, so such a message on it wakes only it: it is named but does
# not fail the run. Prints what it paused (with the project to resume it in),
# discarded, stopped and left queued on the thread; exits 1 when a descendant
# will not settle or holds queued messages this program did not create.
#
# Usage: pause-tree.sh <thread-id>
set -u
root="${1:?usage: pause-tree.sh <thread-id>}"
saved="${BB_THREAD_STORAGE:?BB_THREAD_STORAGE is not set}/pause-tree-$root.jsonl"
# BB batches child reports for 2s before delivering them to the parent.
settle="${PAUSE_TREE_SETTLE:-5}"
root_project=$(bb thread show "$root" --json | jq -er '.thread.projectId') \
	|| { echo "error: cannot read the project of $root" >&2; exit 1; }

# Every descendant as "id<TAB>status<TAB>queuedWork<TAB>projectId", parents first.
tree() {
	local kids id
	kids=$(bb thread list --parent-thread "$1" --include-hidden --json) || return 1
	jq -r '.[] | [.id, .status, .queuedWork, .projectId] | @tsv' <<<"$kids" || return 1
	for id in $(jq -r '.[].id' <<<"$kids"); do tree "$id" || return 1; done
}

# Leaves exactly one row for message $1 in $saved: the JSON row $2, or none when
# $2 is empty. It writes a temp file and renames it over $saved, so a failed
# write leaves the old file intact. Then it reads $saved back and fails unless
# the row there matches.
record() {
	local tmp="$saved.tmp.$$"
	{ [ ! -e "$saved" ] || jq -c --arg m "$1" 'select(.id != $m)' "$saved"; } > "$tmp" \
		&& { [ -z "${2:-}" ] || printf '%s\n' "$2" >> "$tmp"; } \
		&& mv -f "$tmp" "$saved" \
		&& jq -en --arg m "$1" --slurpfile s "$saved" '[$s[] | select(.id == $m)] == [inputs]' <<<"${2:-}" >/dev/null \
		|| { rm -f "$tmp"; return 1; }
}

# Pauses every enabled automation aimed at a thread of the tree, in the root's
# project, the caller's, and each descendant's, since an automation lists only
# under the project that owns it. Leaves every automation of those projects in
# $autos for the due-notice rule.
pause_automations() {
	local p list id
	autos="[]"
	for p in $(printf '%s\n%s\n%s\n' "$root_project" "${BB_PROJECT_ID:-}" "$(cut -f4 <<<"$rows")" | sed '/^$/d' | sort -u); do
		list=$(bb automation list --project "$p" --json) && autos=$(jq -c --argjson more "$list" '. + $more' <<<"$autos") \
			|| { echo "error: cannot list automations in $p" >&2; return 1; }
		for id in $(jq -r --arg ids "$tree_ids" '.[] | select(.enabled == true)
			| select((.targetThreadId // .execution.targetThreadId // "") | IN($ids | split("\n")[] | select(. != ""))) | .id' <<<"$list"); do
			bb automation pause "$id" --project "$p" >/dev/null || { echo "error: cannot pause automation $id in $p" >&2; return 1; }
			echo "paused automation $id in $p"
			acted=yes
		done
	done
}

rows=$(tree "$root") || { echo "error: cannot list the threads under $root" >&2; exit 1; }
held=""; settled=no
for pass in 1 2 3 4 5 6 7 8 9 10; do
	tree_ids=$(printf '%s\n%s\n' "$root" "$(cut -f1 <<<"$rows")")
	acted=no
	pause_automations || exit 1
	# The root's queue too: a wake-up queued behind its turn restarts the program.
	for id in "$root" $(awk -F'\t' '$3 != "none" { print $1 }' <<<"$rows"); do
		grep -qxF "$id" <<<"$held" && continue
		queue=$(bb thread queue list "$id" --json) || { echo "error: cannot list the queued messages of $id" >&2; exit 1; }
		while IFS=$'\t' read -r mid ours; do
			[ -z "$mid" ] && continue
			if [ "$ours" = false ]; then [ "$id" = "$root" ] || held=$(printf '%s\n%s' "$held" "$id"); continue; fi
			row=$(jq -c --arg m "$mid" '.[] | select(.id == $m)' <<<"$queue")
			record "$mid" "$row" || { echo "error: cannot save queued message $mid on $id to $saved, so it stays queued and nothing more is discarded" >&2; exit 1; }
			acted=yes
			if bb thread queue delete "$id" "$mid" >/dev/null; then
				echo "discarded queued message $mid on $id, saved to $saved"
			# Still queued, so not discarded: drop its row, and the next pass retries it.
			elif q=$(bb thread queue list "$id" --json) && jq -e --arg m "$mid" 'any(.[]; .id == $m)' <<<"$q" >/dev/null && record "$mid"; then
				echo "warn: cannot discard $mid on $id; it stays queued" >&2
			else
				echo "warn: cannot discard $mid on $id, and it may have left the queue, so its row stays in $saved" >&2
			fi
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

# Each message queued on a thread as "  thread status message initiator sender waiting-on".
queued_rows() {
	local queue
	queue=$(bb thread queue list "$1" --json) || { echo "error: cannot list the queued messages of $1" >&2; return 1; }
	jq -r --arg id "$1" --arg st "$2" \
		'.[] | "  \($id) \($st) \(.id) \(.initiator) \(.senderThreadId // "-") \(.waitingOn.kind // "turn")"' <<<"$queue"
}

left=$(queued_rows "$root" "$(bb thread show "$root" --json | jq -r '.thread.status')") || exit 1
[ -n "$left" ] && printf '%s\n%s\n' \
	"left queued on $root, which this script never stops, so each wakes only $root (thread, status, message, initiator, sender, waiting on):" "$left"

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
		queued_rows "$id" "$(awk -F'\t' -v id="$id" '$1 == id { print $2 }' <<<"$rows")" >&2
	done
}
exit 1
