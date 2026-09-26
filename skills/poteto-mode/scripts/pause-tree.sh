#!/usr/bin/env bash
# Pauses the work under a BB thread. Pauses every automation that would
# re-prompt the thread or a descendant, whichever project owns it, then settles
# every descendant, hidden ones included. A descendant is any thread BB's
# archive of the thread reaches: its children, its lifecycle dependents and its
# hidden forks, at any depth and in any project. A fork reuses its source's
# environment by default and reports to no one, so nothing else notices it
# running. `bb thread stop` does not cascade, a stopped child's report starts a
# turn on an idle parent, and a stop leaves queued messages to dispatch later,
# so each pass walks the whole tree again, pauses the automations aimed at it
# in every project, the personal one included, discards the queued wake-ups
# this program created on the thread and every descendant, and stops each
# descendant, until one pass finds every descendant settled. A machine can
# still run a turn for a thread BB lists as idle or error, and only an explicit
# stop interrupts it, so every descendant takes at least one stop that succeeds
# whatever its status, and one that runs again takes another. A stop leaves a
# thread's terminals running, so a CLI a stopped descendant started keeps
# writing: each pass closes every live thread-scoped terminal of each stopped
# descendant, the thread's own only under --stop-target, with `bb terminal
# close --if-clean`, which closes only a terminal no input was ever sent to.
# One that took input (typed in the UI, or sent with `bb terminal send`) stays
# open, is never force-closed, and is named for the operator to decide. A
# descendant is settled once it has taken such a stop and a later pass lists it
# idle or error with no queued work of the program and no live terminal. A
# queued message is the program's when a thread in this tree sent it or it is
# the due notice of an automation a thread in this tree created. Before a
# message is discarded, it is saved as one JSON line, one per message id, to
# $BB_THREAD_STORAGE/pause-tree-<thread-id>.jsonl for the resume note, and read
# back. A terminal is saved the same way before it is closed, as a row with
# "kind": "terminal" and its threadId, title and initialCwd, so the resume can
# restart what is still needed. Every row carries the route the pause reached
# its thread by, and every stop prints it, so the resume can walk the same
# graph. When a save fails, the script stops there and discards or closes
# nothing more. Any other queued message (the user's, a retry, a system notice,
# another program's) stays queued and its thread is never stopped. Without
# --stop-target the thread itself is never stopped, so such a message on it
# wakes only it: it is named but does not fail the run.
# With --stop-target the thread itself is stood down too, since it keeps
# running through the shutdown and can spawn or restart a child after the last
# pass. Each pass first discards its program wake-ups and stops it, then lists
# the tree again, so a child it made before that stop is caught. Its queue and
# its terminals are then handled like a descendant's: another program's message
# holds it unstopped, and its terminals close with --if-clean. The run settles
# only when one pass finds the thread and every descendant settled together.
# Prints what it paused (with the project to resume it in), discarded, stopped
# (with its route), closed and left queued on the thread; exits 1 when a
# descendant, or the thread under --stop-target, will not settle (a terminal
# that will not close included), keeps a terminal that took input, or holds
# queued messages this program did not create. It exits 1 before stopping
# anything when it cannot list the projects or one project's automations, since
# an automation there may still re-prompt the tree.
#
# Usage: pause-tree.sh [--stop-target] <thread-id>
set -u
stop_target=no
[ "${1:-}" = --stop-target ] && { stop_target=yes; shift; }
[ $# = 1 ] && [ "${1#-}" = "$1" ] || { echo "usage: pause-tree.sh [--stop-target] <thread-id>" >&2; exit 1; }
root="$1"
saved="${BB_THREAD_STORAGE:?BB_THREAD_STORAGE is not set}/pause-tree-$root.jsonl"
# BB batches child reports for 2s before delivering them to the parent.
settle="${PAUSE_TREE_SETTLE:-5}"
bb thread show "$root" --json | jq -e '.thread.id' >/dev/null \
	|| { echo "error: cannot read $root" >&2; exit 1; }

# Every descendant as "id<TAB>status<TAB>queuedWork<TAB>route",
# parents first, each once. `bb thread list` filters by parent alone, so this
# reads every live thread in every project and follows all three links. The
# route is the JSON path from the thread down to the descendant, one
# {threadId, link} per hop, the link being how that hop hangs off the one
# before: child, dependent (lifecycle) or fork (hidden). Reads the thread list
# on stdin.
tree() {
	jq -r --arg root "$1" '
		(reduce .[] as $t ({}; reduce ([$t.parentThreadId, $t.lifecycleOwnerThreadId,
			(if $t.visibility == "hidden" then $t.sourceThreadId else null end)]
			| map(select(. != null)) | unique)[] as $p (.; .[$p] += [$t]))) as $kids
		| {seen: {($root): true}, next: [$root], route: {($root): []}, out: []}
		| until(.next == []; .next[0] as $id | .next |= .[1:]
			| reduce ($kids[$id] // [])[] as $k (.; if .seen[$k.id] then . else
				.seen[$k.id] = true | .next += [$k.id]
				| .route[$k.id] = .route[$id] + [{threadId: $k.id, link: (if $k.parentThreadId == $id then "child"
					elif $k.lifecycleOwnerThreadId == $id then "dependent" else "fork" end)}]
				| .out += [$k + {route: .route[$k.id]}] end))
		| .out[] | [.id, .status, .queuedWork, (.route | tojson)] | @tsv'
}

# Lists every live thread once: the descendants into $rows as tree() prints
# them and, from the same list, the target into $target as
# "id<TAB>status<TAB>queuedWork".
snapshot() {
	local all
	all=$(bb thread list --include-hidden --json) && rows=$(tree "$root" <<<"$all") \
		&& target=$(jq -r --arg root "$root" '.[] | select(.id == $root) | [.id, .status, .queuedWork] | @tsv' <<<"$all")
}

# The route tree() found to thread $1, [] for the root.
route_of() {
	awk -F'\t' -v id="$1" '$1 == id { r = $4 } END { print (r == "" ? "[]" : r) }' <<<"$rows"
}

# Leaves exactly one row for message or terminal $1 in $saved: the JSON row $2,
# or none when $2 is empty. It writes a temp file and renames it over $saved, so
# a failed write leaves the old file intact. Then it reads $saved back and fails
# unless the row there matches.
record() {
	local tmp="$saved.tmp.$$"
	{ [ ! -e "$saved" ] || jq -c --arg m "$1" 'select(.id != $m)' "$saved"; } > "$tmp" \
		&& { [ -z "${2:-}" ] || printf '%s\n' "$2" >> "$tmp"; } \
		&& mv -f "$tmp" "$saved" \
		&& jq -en --arg m "$1" --slurpfile s "$saved" '[$s[] | select(.id == $m)] == [inputs]' <<<"${2:-}" >/dev/null \
		|| { rm -f "$tmp"; return 1; }
}

# Pauses every enabled automation aimed at a thread of the tree, in every
# project, since an automation lists only under the project that owns it and
# BB lets one project's automation target a thread of another. Leaves every
# automation in $autos for the due-notice rule. A project whose automations it
# cannot list fails the run once the others are paused.
pause_automations() {
	local projects p list id unlisted=""
	autos="[]"
	projects=$(bb project list --include-personal --json) \
		&& projects=$(jq -er 'if type == "array" and length > 0 then .[].id else error("no projects") end' <<<"$projects") \
		|| { echo "error: cannot list the projects whose automations could re-prompt the tree" >&2; return 1; }
	for p in $projects; do
		if ! list=$(bb automation list --project "$p" --json) || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$list"; then
			unlisted="$unlisted $p"; continue
		fi
		autos=$(jq -c --argjson more "$list" '. + $more' <<<"$autos")
		for id in $(jq -r --arg ids "$tree_ids" '.[] | select(.enabled == true)
			| select((.targetThreadId // .execution.targetThreadId // "") | IN($ids | split("\n")[] | select(. != ""))) | .id' <<<"$list"); do
			bb automation pause "$id" --project "$p" >/dev/null || { echo "error: cannot pause automation $id in $p" >&2; return 1; }
			echo "paused automation $id in $p"
			acted=yes
		done
	done
	[ -z "$unlisted" ] || { echo "error: cannot list automations in$unlisted, so one there may still re-prompt the tree" >&2; return 1; }
}

# Each live terminal scoped to thread $1, as one JSON row for $saved. `bb
# terminal list` shows only live sessions (starting, running, disconnected), so
# none printed means none is left.
terminals() {
	local list
	list=$(bb terminal list --thread "$1" --json) || return 1
	jq -c --arg id "$1" --argjson route "$(route_of "$1")" '.sessions[] | {kind: "terminal", threadId: $id} + . + {route: $route}' <<<"$list"
}

# Each descendant in $rows whose stop succeeded, and the target under
# --stop-target, bar those holding another program's messages.
stopped_ids() {
	local id
	for id in $([ "$stop_target" = yes ] && echo "$root") $(cut -f1 <<<"$rows"); do
		if grep -qxF "$id" <<<"$stopped" && ! grep -qxF "$id" <<<"$held"; then echo "$id"; fi
	done
}

# Discards each queued message of the program on thread $1, saved first. Another
# program's message there holds the thread, which is then never stopped, bar
# the target without --stop-target, which is never stopped anyway.
drain() {
	local id="$1" queue mid ours row q
	grep -qxF "$id" <<<"$held" && return 0
	queue=$(bb thread queue list "$id" --json) || { echo "error: cannot list the queued messages of $id" >&2; exit 1; }
	while IFS=$'\t' read -r mid ours; do
		[ -z "$mid" ] && continue
		if [ "$ours" = false ]; then { [ "$id" = "$root" ] && [ "$stop_target" = no ]; } || held=$(printf '%s\n%s' "$held" "$id"); continue; fi
		row=$(jq -c --arg m "$mid" --argjson route "$(route_of "$id")" '.[] | select(.id == $m) | . + {route: $route}' <<<"$queue")
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
}

snapshot || { echo "error: cannot list the threads under $root" >&2; exit 1; }
# $stopped holds each thread whose `bb thread stop` succeeded, $kept each
# terminal --if-clean left open because it took input, and $kept_rows its report line.
held=""; stopped=""; kept=""; kept_rows=""; settled=no; target_stopped=no; target_ok=yes
for pass in 1 2 3 4 5 6 7 8 9 10; do
	tree_ids=$(printf '%s\n%s\n' "$root" "$(cut -f1 <<<"$rows")")
	acted=no
	pause_automations || exit 1
	# The target first under --stop-target: its program wake-ups discarded, so
	# its stop dispatches none, then stopped unless another program's message
	# holds it, then the tree listed again to catch a child it made before.
	if [ "$stop_target" = yes ]; then
		target_stopped=no
		drain "$root"
		if ! grep -qxF "$root" <<<"$held"; then
			if bb thread stop "$root" >/dev/null; then
				target_stopped=yes
				grep -qxF "$root" <<<"$stopped" || { echo "stopped $root, the target"; stopped=$(printf '%s\n%s' "$stopped" "$root"); }
			else echo "warn: bb thread stop $root failed" >&2; fi
		fi
		snapshot || { echo "error: cannot list the threads under $root" >&2; exit 1; }
		tree_ids=$(printf '%s\n%s\n' "$root" "$(cut -f1 <<<"$rows")")
	fi
	# The root's queue too: a wake-up queued behind its turn restarts the program.
	for id in "$root" $(awk -F'\t' '$3 != "none" { print $1 }' <<<"$rows"); do drain "$id"; done
	# Each stopped descendant's terminals, and the target's only under
	# --stop-target: saved, closed, and listed again next pass until none is left.
	for id in $(stopped_ids); do
		terms=$(terminals "$id") || { echo "error: cannot list the terminals of $id" >&2; exit 1; }
		while IFS= read -r term; do
			[ -z "$term" ] && continue
			tid=$(jq -r '.id' <<<"$term")
			grep -qxF "$tid" <<<"$kept" && continue
			record "$tid" "$term" || { echo "error: cannot save terminal $tid of $id to $saved, so it stays open and nothing more is closed" >&2; exit 1; }
			acted=yes
			# --if-clean answers with the session either way: exited, or unchanged when input was sent to it.
			closed=$(bb terminal close "$tid" --if-clean --json) || closed='{}'
			if jq -e '.status == "exited"' <<<"$closed" >/dev/null 2>&1; then
				echo "closed terminal $tid of $id ($(jq -r '.title' <<<"$term")) in $(jq -r '.initialCwd // "-"' <<<"$term"), saved to $saved"
			# Someone may be working in it, so only the operator may close it: drop its row and leave it open.
			elif jq -e '.lastUserInputAt != null' <<<"$closed" >/dev/null 2>&1; then
				record "$tid" || { echo "error: cannot drop the row of terminal $tid of $id, which stays open, from $saved" >&2; exit 1; }
				kept=$(printf '%s\n%s' "$kept" "$tid")
				kept_rows=$(printf '%s\n%s' "$kept_rows" "$(jq -r --arg id "$id" '"  \($id) \(.id) \(.status) \(.title) \(.lastUserInputAt / 1000 | floor | todate)"' <<<"$closed")")
				echo "warn: terminal $tid of $id took input, so it stays open for the operator to decide" >&2
			# Still live, so not closed: drop its row, and the next pass retries it.
			elif t=$(terminals "$id") && jq -e --arg t "$tid" 'select(.id == $t)' <<<"$t" >/dev/null && record "$tid"; then
				echo "warn: cannot close terminal $tid of $id; it stays open" >&2
			else
				echo "warn: cannot close terminal $tid of $id, and it may have closed, so its row stays in $saved" >&2
			fi
		done <<<"$terms"
	done
	# Every descendant still running or never stopped, bar those holding another program's messages.
	busy=$(HELD="$held" STOPPED="$stopped" awk -F'\t' 'BEGIN { n = split(ENVIRON["HELD"], h, "\n"); for (i = 1; i <= n; i++) skip[h[i]] = 1
			n = split(ENVIRON["STOPPED"], s, "\n"); for (i = 1; i <= n; i++) done[s[i]] = 1 }
		($2 ~ /^(pending|starting|active|stopping)$/ || !($1 in done)) && !($1 in skip) { print $1 }' <<<"$rows")
	# Under --stop-target the target settles in the same pass: its stop this
	# pass succeeded and the list taken after it shows it idle or error.
	target_ok=yes
	if [ "$stop_target" = yes ] && ! grep -qxF "$root" <<<"$held"; then
		[ "$target_stopped" = yes ] || target_ok=no
		case "$(cut -f2 <<<"$target")" in pending|starting|active|stopping|"") target_ok=no ;; esac
	fi
	[ -z "$busy" ] && [ "$acted" = no ] && [ "$target_ok" = yes ] && { settled=yes; break; }
	for id in $busy; do
		if bb thread stop "$id" >/dev/null; then
			echo "stopped $id via $(route_of "$id" | jq -r 'map("\(.threadId) (\(.link))") | join(" > ")')"
			stopped=$(printf '%s\n%s' "$stopped" "$id")
		else echo "warn: bb thread stop $id failed" >&2; fi
	done
	sleep "$settle"
	snapshot || { echo "error: cannot list the threads under $root" >&2; exit 1; }
done

# Each message queued on a thread as "  thread status message initiator sender waiting-on".
queued_rows() {
	local queue
	queue=$(bb thread queue list "$1" --json) || { echo "error: cannot list the queued messages of $1" >&2; return 1; }
	jq -r --arg id "$1" --arg st "$2" \
		'.[] | "  \($id) \($st) \(.id) \(.initiator) \(.senderThreadId // "-") \(.waitingOn.kind // "turn")"' <<<"$queue"
}

if [ "$stop_target" = no ]; then
	left=$(queued_rows "$root" "$(bb thread show "$root" --json | jq -r '.thread.status')") || exit 1
	[ -n "$left" ] && printf '%s\n%s\n' \
		"left queued on $root, which this script never stops, so each wakes only $root (thread, status, message, initiator, sender, waiting on):" "$left"
fi

if [ "$settled" = yes ] && [ -z "$held" ] && [ -z "$kept" ]; then
	if [ "$stop_target" = yes ]; then echo "settled $root and $(grep -c . <<<"$rows") descendants after $((pass - 1)) rounds"
	else echo "settled $(grep -c . <<<"$rows") descendants of $root after $((pass - 1)) rounds"; fi
	exit 0
fi
[ "$settled" = no ] && {
	echo "error: not settled after 10 rounds of stops (thread, status, queued work, whether a stop succeeded):" >&2
	BUSY="$busy" HELD="$held" STOPPED="$stopped" awk -F'\t' 'BEGIN { n = split(ENVIRON["BUSY"], b, "\n"); for (i = 1; i <= n; i++) show[b[i]] = 1
			n = split(ENVIRON["HELD"], h, "\n"); for (i = 1; i <= n; i++) skip[h[i]] = 1
			n = split(ENVIRON["STOPPED"], s, "\n"); for (i = 1; i <= n; i++) done[s[i]] = 1 }
		$1 in show || ($3 != "none" && !($1 in skip)) { print "  " $1, $2, $3, (($1 in done) ? "stopped" : "never-stopped") }' <<<"$rows" >&2
	[ "$target_ok" = no ] && printf '  %s %s %s %s (the target)\n' "$root" "$(cut -f2 <<<"$target")" "$(cut -f3 <<<"$target")" \
		"$([ "$target_stopped" = yes ] && echo stopped || echo not-stopped-this-pass)" >&2
	open=$(for id in $(stopped_ids); do
		if t=$(terminals "$id"); then jq -r --arg kept "$kept" 'select(.id | IN($kept | split("\n")[]) | not) | "  \(.threadId) \(.id) \(.status) \(.title)"' <<<"$t"
		else echo "  $id ? cannot list its terminals"; fi
	done)
	[ -n "$open" ] && printf '%s\n%s\n' "error: terminals still live under stopped descendants (thread, terminal, status, title):" "$open" >&2
}
[ -n "$kept" ] && printf '%s%s\n' \
	"error: left open terminals that took input, which only the operator may close (thread, terminal, status, title, first input):" "$kept_rows" >&2
[ -n "$held" ] && {
	echo "error: left queued messages this program did not create, and never stopped their threads (thread, status, message, initiator, sender, waiting on):" >&2
	for id in $(printf '%s\n' "$held" | sed '/^$/d' | sort -u); do
		queued_rows "$id" "$(if [ "$id" = "$root" ]; then cut -f2 <<<"$target"; else awk -F'\t' -v id="$id" '$1 == id { print $2 }' <<<"$rows"; fi)" >&2
	done
}
exit 1
