#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/pause-tree.sh.
# A stub `bb` holds a coordinator, sub-coordinator and worker tree with a hidden
# worker and a worker in another project, and behaves the way BB does: a stop
# leaves the queue alone, a message queued behind a turn dispatches when that
# turn ends, a stopped child's report wakes its idle parent, a machine can
# still run a turn for a thread listed idle or error until a stop interrupts
# it, a thread list
# derives queuedWork from the queue, and automations are listed and paused one
# project at a time.
# Asserts the end state of every thread, queued message and automation.
# Usage: pause-tree.test.sh <path to pause-tree.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/pause-tree-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub" "$S/storage"

cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
state="$S/threads.json" queue="$S/queue.json" autos="$S/automations.json" calls="$S/calls"
update() { f="\$1"; shift; jq "\$@" "\$f" > "\$f.new" && mv "\$f.new" "\$f"; }
case "\$1 \$2" in
	"thread list")
		parent=""; hidden=""; prev=""
		for a in "\$@"; do [ "\$prev" = --parent-thread ] && parent="\$a"; [ "\$a" = --include-hidden ] && hidden=1; prev="\$a"; done
		jq --arg p "\$parent" --arg h "\$hidden" --slurpfile q "\$queue" '[.[] | select(.parentThreadId == \$p) | select(\$h != "" or .visibility == "visible")
			| .id as \$id | .queuedWork = (if any(\$q[0][]; .threadId == \$id) then "waiting" else "none" end)]' "\$state" ;;
	"thread queue")
		case "\$3" in
			list) jq --arg t "\$4" '[.[] | select(.threadId == \$t)]' "\$queue" ;;
			delete) jq -e --arg t "\$4" --arg m "\$5" 'any(.[]; .threadId == \$t and .id == \$m)' "\$queue" >/dev/null || { echo "no queued message \$5" >&2; exit 1; }
				[ "\$5" = "\${REFUSE:-}" ] && { echo "refused \$5" >&2; exit 1; }
				echo "delete \$5" >> "\$calls"
				update "\$queue" --arg m "\$5" 'map(select(.id != \$m))'
				# LOST: the delete lands but the call still fails.
				if [ "\$5" = "\${LOST:-}" ]; then exit 1; fi ;;
			*) exit 2 ;;
		esac ;;
	"thread stop")
		id="\$3"
		echo "stop \$id" >> "\$calls"
		# STOPFAIL: the stop call fails and nothing changes.
		[ "\$id" = "\${STOPFAIL:-}" ] && { echo "cannot stop \$id" >&2; exit 1; }
		[ "\$id" = "\${STUCK:-}" ] && { update "\$state" --arg id "\$id" 'map(if .id == \$id then .status = "stopping" else . end)'; exit 0; }
		# machineTurn: the machine still runs a turn that the listed status (idle, error) does not show.
		busy=\$(jq -r --arg id "\$id" '.[] | select(.id == \$id) | (.status | IN("pending", "starting", "active", "stopping")) or .machineTurn == true' "\$state")
		[ "\$busy" = true ] || exit 0
		update "\$state" --arg id "\$id" 'map(if .id == \$id then .status = "idle" | del(.machineTurn) else . end)'
		parent=\$(jq -r --arg id "\$id" '.[] | select(.id == \$id) | .parentThreadId // ""' "\$state")
		[ -n "\$parent" ] && update "\$state" --arg p "\$parent" 'map(if .id == \$p and .status == "idle" then .status = "active" else . end)'
		next=\$(jq -r --arg id "\$id" '[.[] | select(.threadId == \$id and (.waitingOn == null or .waitingOn.kind == "thread-busy"))][0].id // ""' "\$queue")
		if [ -n "\$next" ]; then
			echo "dispatch \$next" >> "\$calls"
			update "\$queue" --arg m "\$next" 'map(select(.id != \$m))'
			update "\$state" --arg id "\$id" 'map(if .id == \$id then .status = "active" else . end)'
		fi
		exit 0 ;;
	"thread show") jq -e --arg id "\$3" '.[] | select(.id == \$id) | {thread: .}' "\$state" ;;
	"automation list") [ "\$3" = --project ] || exit 2
		jq --arg p "\$4" '[.[] | select(.projectId == \$p)]' "\$autos" ;;
	"automation pause") [ "\$4" = --project ] || exit 2
		jq -e --arg id "\$3" --arg p "\$5" 'any(.[]; .id == \$id and .projectId == \$p)' "\$autos" >/dev/null || { echo "no automation \$3 in \$5" >&2; exit 1; }
		echo "pause \$3 \$5" >> "\$calls"
		update "\$autos" --arg id "\$3" 'map(if .id == \$id then .enabled = false else . end)' ;;
	*) exit 2 ;;
esac
EOF
chmod +x "$S/stub/bb"

msg() { # id thread initiator sender origin waiting-on text
	jq -nc --arg id "$1" --arg t "$2" --arg i "$3" --arg s "$4" --arg o "$5" --arg w "$6" --arg text "$7" \
		'{id: $id, threadId: $t, initiator: $i, senderThreadId: (if $s == "" then null else $s end), origin: (if $o == "" then null else $o end),
		originPluginId: (if $o == "plugin" then "automations" else null end), waitingOn: (if $w == "" then null else {kind: $w} end),
		content: [{type: "text", text: $text}]}'
}
seed() {
	cat > "$S/threads.json" <<'EOF'
[{"id":"thr_root","projectId":"proj","parentThreadId":null,"status":"active","visibility":"visible"},
 {"id":"thr_sub","projectId":"proj","parentThreadId":"thr_root","status":"active","visibility":"visible"},
 {"id":"thr_w1","projectId":"proj","parentThreadId":"thr_sub","status":"active","visibility":"visible"},
 {"id":"thr_w2","projectId":"proj","parentThreadId":"thr_sub","status":"active","visibility":"hidden"},
 {"id":"thr_far","projectId":"proj_other","parentThreadId":"thr_sub","status":"active","visibility":"visible"},
 {"id":"thr_told","projectId":"proj","parentThreadId":"thr_root","status":"idle","visibility":"visible"},
 {"id":"thr_woken","projectId":"proj","parentThreadId":"thr_sub","status":"idle","visibility":"visible"},
 {"id":"thr_behind","projectId":"proj","parentThreadId":"thr_root","status":"active","visibility":"visible"},
 {"id":"thr_done","projectId":"proj","parentThreadId":"thr_root","status":"idle","visibility":"visible"},
 {"id":"thr_elsewhere","projectId":"proj","parentThreadId":null,"status":"active","visibility":"visible"},
 {"id":"thr_stranger","projectId":"proj_other","parentThreadId":null,"status":"idle","visibility":"visible"}]
EOF
	{
		msg msg_tell thr_told agent thr_sub cli time "Phase 2 brief."
		msg msg_due thr_woken user "" plugin interaction $'[bb automation due:auto_worker]\n\nAudit tick.'
		msg msg_behind thr_behind agent thr_root cli "" "Next slice."
		msg msg_else thr_elsewhere user "" app time "Not this tree."
		msg msg_fardue thr_far user "" plugin thread-busy $'[bb automation due:auto_far]\n\nFar tick.'
		msg msg_rootdue thr_root user "" plugin interaction $'[bb automation due:auto_tick]\n\nResume the run.'
		msg msg_roottell thr_root agent thr_sub cli thread-busy "Slice done, start the next."
	} | jq -s . > "$S/queue.json"
	cat > "$S/automations.json" <<'EOF'
[{"id":"auto_tick","projectId":"proj","enabled":true,"createdByThreadId":"thr_root","execution":{"mode":"agent","targetThreadId":"thr_root"}},
 {"id":"auto_worker","projectId":"proj","enabled":true,"createdByThreadId":"thr_sub","targetThreadId":"thr_w2"},
 {"id":"auto_user","projectId":"proj","enabled":true,"createdByThreadId":null,"execution":{"mode":"agent","targetThreadId":"thr_held"}},
 {"id":"auto_spawner","projectId":"proj","enabled":true,"createdByThreadId":"thr_root","execution":{"mode":"agent"}},
 {"id":"auto_other","projectId":"proj","enabled":true,"createdByThreadId":"thr_elsewhere","execution":{"mode":"agent","targetThreadId":"thr_elsewhere"}},
 {"id":"auto_far","projectId":"proj_other","enabled":true,"createdByThreadId":"thr_far","execution":{"mode":"agent","targetThreadId":"thr_far"}},
 {"id":"auto_stranger","projectId":"proj_other","enabled":true,"createdByThreadId":null,"execution":{"mode":"agent","targetThreadId":"thr_stranger"}}]
EOF
	: > "$S/calls"
	rm -f "$S/storage"/*
}
run() { env PATH="$S/stub:$PATH" BB_PROJECT_ID=proj BB_THREAD_STORAGE="$S/storage" PAUSE_TREE_SETTLE=0 "$@" bash "$script" thr_root 2>&1; }
status() { jq -r --arg id "$1" --slurpfile q "$S/queue.json" '.[] | select(.id == $id)
	| "\(.status)/\(if any($q[0][]; .threadId == $id) then "waiting" else "none" end)"' "$S/threads.json"; }
enabled() { jq -r --arg id "$1" '.[] | select(.id == $id) | .enabled' "$S/automations.json"; }
queued() { jq -r --arg t "$1" '[.[] | select(.threadId == $t) | .id] | sort | join(" ")' "$S/queue.json"; }
calls() { grep -c "^$1\$" "$S/calls" || true; }

fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1 = $2"; else echo "FAIL $1 got '$2' want '$3'"; fail=1; fi; }

echo "# the program's own queued tells and automation wake-ups are discarded, saved, and never dispatched, the root's too"
seed
out=$(run) && code=0 || code=$?
expect "exit" "$code" 0
for id in thr_sub thr_w1 thr_w2 thr_far thr_told thr_woken thr_behind thr_done; do expect "$id" "$(status "$id")" idle/none; done
expect "thr_root keeps running with an empty queue" "$(status thr_root)" active/none
expect "thr_root never stopped" "$(calls "stop thr_root")" 0
expect "thr_elsewhere untouched" "$(status thr_elsewhere)" active/waiting
expect "saved" "$(jq -rs '[.[].id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" \
	"msg_behind msg_due msg_fardue msg_rootdue msg_roottell msg_tell"
expect "saved text" "$(jq -rs '.[] | select(.id == "msg_tell") | .content[0].text' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" "Phase 2 brief."
expect "dispatched" "$(grep -c '^dispatch ' "$S/calls" || true)" 0
expect "auto_tick" "$(enabled auto_tick)" false
expect "auto_worker" "$(enabled auto_worker)" false
expect "auto_spawner untouched" "$(enabled auto_spawner)" true
expect "auto_other untouched" "$(enabled auto_other)" true
echo "# a descendant in another project has its automations paused in that project"
expect "auto_far" "$(enabled auto_far)" false
expect "auto_far named with its project" "$(grep -c '^paused automation auto_far in proj_other$' <<<"$out" || true)" 1
expect "auto_stranger untouched" "$(enabled auto_stranger)" true
expect "idempotent rerun exit" "$(run >/dev/null && echo 0 || echo $?)" 0

echo "# the root's own project holds its automations, whatever project the caller is in"
seed
run BB_PROJECT_ID=proj_caller >/dev/null && code=0 || code=$?
expect "other-project caller exit" "$code" 0
expect "auto_tick paused from the root's project" "$(enabled auto_tick)" false
expect "thr_root queue emptied" "$(queued thr_root)" ""

echo "# a message on the root from outside the program stays queued and is named, but exit 0 still holds: it wakes only the root, which the script never stops"
seed
{
	jq '.[]' "$S/queue.json"
	msg msg_rootuser thr_root user "" app time "Also update the docs."
} | jq -s . > "$S/queue.new" && mv "$S/queue.new" "$S/queue.json"
out=$(run) && code=0 || code=$?
expect "root-only exit" "$code" 0
expect "root's own message left queued" "$(queued thr_root)" "msg_rootuser"
expect "root's own message named" "$(grep -c '^  thr_root active msg_rootuser user' <<<"$out" || true)" 1
expect "root never stopped" "$(calls "stop thr_root")" 0
expect "root's program wake-ups still discarded" "$(jq -rs '[.[] | select(.threadId == "thr_root") | .id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" "msg_rootdue msg_roottell"
for id in thr_sub thr_w1 thr_w2 thr_far thr_told thr_woken thr_behind thr_done; do expect "$id" "$(status "$id")" idle/none; done

echo "# queued work the program did not create on a descendant is left in place, its thread is not stopped, and the script stops"
seed
cat > "$S/extra.json" <<'EOF'
[{"id":"thr_held","parentThreadId":"thr_root","status":"idle","visibility":"visible"}]
EOF
jq -s add "$S/threads.json" "$S/extra.json" > "$S/threads.new" && mv "$S/threads.new" "$S/threads.json"
{
	jq '.[]' "$S/queue.json"
	msg msg_user thr_held user "" app time "Also check the migration."
	msg msg_retry thr_held system "" "" plugin "Retry."
	msg msg_outside thr_held agent thr_elsewhere cli time "From another program."
	msg msg_userauto thr_held user "" plugin interaction $'[bb automation due:auto_user]\n\nNightly.'
	msg msg_rootuser thr_root user "" app time "Also update the docs."
} | jq -s . > "$S/queue.new" && mv "$S/queue.new" "$S/queue.json"
jq '(.[] | select(.id == "thr_held")).projectId = "proj"' "$S/threads.json" > "$S/threads.new" && mv "$S/threads.new" "$S/threads.json"
out=$(run) && code=0 || code=$?
expect "held exit" "$code" 1
expect "held left queued" "$(queued thr_held)" "msg_outside msg_retry msg_user msg_userauto"
expect "held never stopped" "$(calls "stop thr_held")" 0
expect "held named" "$(grep -c '^  thr_held idle msg_user user' <<<"$out" || true)" 1
expect "root's own message left queued" "$(queued thr_root)" "msg_rootuser"
expect "root's own message named" "$(grep -c '^  thr_root active msg_rootuser user' <<<"$out" || true)" 1
expect "root never stopped" "$(calls "stop thr_root")" 0
expect "auto_user paused" "$(enabled auto_user)" false
for id in thr_sub thr_w1 thr_w2 thr_told thr_woken thr_behind thr_done; do expect "$id" "$(status "$id")" idle/none; done

echo "# a thread that will not stop is named"
seed
out=$(run STUCK=thr_w1) && code=0 || code=$?
expect "stuck exit" "$code" 1
expect "stuck thread named" "$(grep -c 'thr_w1 stopping' <<<"$out")" 1

echo "# every descendant takes a stop whatever its listed status: a turn still running on the machine of a thread listed idle or error is interrupted"
seed
cat > "$S/extra.json" <<'EOF'
[{"id":"thr_failed","projectId":"proj","parentThreadId":"thr_sub","status":"error","visibility":"visible","machineTurn":true}]
EOF
jq -s add "$S/threads.json" "$S/extra.json" > "$S/threads.new" && mv "$S/threads.new" "$S/threads.json"
jq '(.[] | select(.id == "thr_done")).machineTurn = true' "$S/threads.json" > "$S/threads.new" && mv "$S/threads.new" "$S/threads.json"
out=$(run) && code=0 || code=$?
expect "listed-idle exit" "$code" 0
expect "no machine turn left running" "$(jq -r '[.[] | select(.machineTurn == true) | .id] | join(" ")' "$S/threads.json")" ""
for id in thr_sub thr_w1 thr_w2 thr_far thr_told thr_woken thr_behind thr_done thr_failed; do
	expect "$id stopped at least once" "$([ "$(calls "stop $id")" -ge 1 ] && echo yes || echo no)" yes
done
expect "root never stopped" "$(calls "stop thr_root")" 0
expect "thr_elsewhere never stopped" "$(calls "stop thr_elsewhere")" 0

echo "# a descendant whose stop fails is not settled, whatever its listed status"
seed
out=$(run STOPFAIL=thr_done) && code=0 || code=$?
expect "stop-failed exit" "$code" 1
expect "stop-failed thread named" "$(grep -c '^  thr_done idle none never-stopped$' <<<"$out" || true)" 1
expect "stop-failed never reports settled" "$(grep -c '^settled ' <<<"$out" || true)" 0

echo "# nothing is discarded unless its recovery row is saved first: a missing, read-only or unreadable recovery file stops the run"
for setup in missing readonly corrupt; do
	seed
	storage="$S/storage"
	case "$setup" in
		missing) storage="$S/missing" ;;
		readonly) [ "$(id -u)" = 0 ] && continue; chmod 555 "$S/storage" ;;
		corrupt) printf '{"id":"msg_tell","threadId":"thr_t' > "$S/storage/pause-tree-thr_root.jsonl" ;;
	esac
	out=$(run BB_THREAD_STORAGE="$storage") && code=0 || code=$?
	chmod 755 "$S/storage"
	expect "$setup exit" "$code" 1
	expect "$setup deletes nothing" "$(grep -c '^delete ' "$S/calls" || true)" 0
	expect "$setup queue intact" "$(jq -r 'map(.id) | sort | join(" ")' "$S/queue.json")" \
		"msg_behind msg_due msg_else msg_fardue msg_rootdue msg_roottell msg_tell"
	expect "$setup names the save failure" "$(grep -c '^error: cannot save queued message' <<<"$out" || true)" 1
	expect "$setup never reports settled" "$(grep -c '^settled ' <<<"$out" || true)" 0
done

echo "# the recovery file holds one row per message id, with the content the message had when discarded"
seed
jq -c '.[] | select(.id == "msg_tell") | .content[0].text = "Stale brief."' "$S/queue.json" > "$S/storage/pause-tree-thr_root.jsonl"
jq -c '.[] | select(.id == "msg_behind")' "$S/queue.json" >> "$S/storage/pause-tree-thr_root.jsonl"
run >/dev/null && code=0 || code=$?
expect "rerun exit" "$code" 0
expect "one row per id" "$(jq -rs '[.[].id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl")" \
	"msg_behind msg_due msg_fardue msg_rootdue msg_roottell msg_tell"
expect "newest content wins" "$(jq -rs '.[] | select(.id == "msg_tell") | .content[0].text' "$S/storage/pause-tree-thr_root.jsonl")" "Phase 2 brief."

echo "# a delete that fails while the message stays queued leaves it unsaved; one that fails after it left the queue keeps its row"
seed
out=$(run REFUSE=msg_tell) && code=0 || code=$?
expect "refused exit" "$code" 1
expect "refused message still queued" "$(queued thr_told)" "msg_tell"
expect "refused message unsaved" "$(jq -rs '[.[].id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl")" \
	"msg_behind msg_due msg_fardue msg_rootdue msg_roottell"
seed
out=$(run LOST=msg_tell) && code=0 || code=$?
expect "lost exit" "$code" 0
expect "lost message kept" "$(jq -rs '[.[] | select(.id == "msg_tell") | .content[0].text] | join(" ")' "$S/storage/pause-tree-thr_root.jsonl")" "Phase 2 brief."

echo
echo "$out"
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
