#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/pause-tree.sh.
# A stub `bb` holds a coordinator, sub-coordinator and worker tree with a hidden
# worker and a worker in another project, and behaves the way BB does: a stop
# leaves the queue and the thread's terminals alone, a terminal list shows only
# live sessions, a terminal close forces unless --if-clean, which answers with
# a terminal that took input unchanged, a message queued behind a turn dispatches when that
# turn ends, a stopped child's report wakes its idle parent, a machine can
# still run a turn for a thread listed idle or error until a stop interrupts
# it, a thread list
# derives queuedWork from the queue and lists every project's threads without
# --parent-thread, a fork has no parent and reports to no one, and automations
# are listed and paused one project at a time.
# Asserts the end state of every thread, queued message and automation.
# Usage: pause-tree.test.sh <path to pause-tree.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/pause-tree-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub" "$S/storage"

cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
state="$S/threads.json" queue="$S/queue.json" autos="$S/automations.json" terms="$S/terminals.json" calls="$S/calls"
update() { f="\$1"; shift; jq "\$@" "\$f" > "\$f.new" && mv "\$f.new" "\$f"; }
case "\$1 \$2" in
	"thread list")
		parent=""; hidden=""; prev=""
		for a in "\$@"; do [ "\$prev" = --parent-thread ] && parent="\$a"; [ "\$a" = --include-hidden ] && hidden=1; prev="\$a"; done
		jq --arg p "\$parent" --arg h "\$hidden" --slurpfile q "\$queue" '[.[] | select(\$p == "" or .parentThreadId == \$p) | select(\$h != "" or .visibility == "visible")
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
	"terminal list") [ "\$3" = --thread ] || exit 2
		# LOCK_ON_TERMINALS: the storage turns read-only before any terminal is saved.
		[ -n "\${LOCK_ON_TERMINALS:-}" ] && chmod 555 "$S/storage"
		jq --arg t "\$4" '{sessions: [.[] | select(.threadId == \$t and (.status | IN("starting", "running", "disconnected")))]}' "\$terms" ;;
	"terminal close")
		id="\$3" mode=force json=""
		for a in "\${@:4}"; do [ "\$a" = --if-clean ] && mode=if-clean; [ "\$a" = --json ] && json=1; done
		echo "close \$id" >> "\$calls"
		[ "\$mode" = force ] && echo "force \$id" >> "\$calls"
		# TERMFAIL: the close call fails and the terminal keeps running.
		[ "\$id" = "\${TERMFAIL:-}" ] && { [ -n "\$json" ] && echo '{"ok":false,"error":{"code":"host_disconnected","message":"Host is not connected"}}'; echo "cannot close \$id" >&2; exit 1; }
		# TYPED: input reaches the terminal after it was listed and before the close.
		[ "\$id" = "\${TYPED:-}" ] && update "\$terms" --arg id "\$id" 'map(if .id == \$id then .lastUserInputAt = 1758844800000 else . end)'
		# Like BB: --if-clean answers with a terminal that took input unchanged, and exit 0.
		update "\$terms" --arg id "\$id" --arg mode "\$mode" 'map(if .id == \$id and .status != "exited" and (\$mode == "force" or .lastUserInputAt == null)
			then .status = "exited" | .closeReason = "user" else . end)'
		[ -n "\$json" ] && jq --arg id "\$id" '.[] | select(.id == \$id)' "\$terms"
		exit 0 ;;
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
	cat > "$S/terminals.json" <<'EOF'
[{"id":"term_dev","threadId":"thr_w1","title":"pnpm dev","initialCwd":"/work/app","status":"running","exitCode":null,"closeReason":null},
 {"id":"term_watch","threadId":"thr_w2","title":"tsc --watch","initialCwd":"/work/app","status":"disconnected","exitCode":null,"closeReason":null},
 {"id":"term_done","threadId":"thr_w1","title":"pnpm test","initialCwd":"/work/app","status":"exited","exitCode":0,"closeReason":"process-exit"},
 {"id":"term_fork","threadId":"thr_fork","title":"make serve","initialCwd":"/work/app","status":"running","exitCode":null,"closeReason":null},
 {"id":"term_root","threadId":"thr_root","title":"pnpm dev","initialCwd":"/work","status":"running","exitCode":null,"closeReason":null},
 {"id":"term_else","threadId":"thr_elsewhere","title":"pnpm dev","initialCwd":"/else","status":"running","exitCode":null,"closeReason":null}]
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
term() { jq -r --arg id "$1" '.[] | select(.id == $id) | .status' "$S/terminals.json"; }

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
expect "saved" "$(jq -rs '[.[] | select(.kind != "terminal") | .id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" \
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

echo "# a stop leaves a descendant's terminals running, so each live one is saved, closed and listed again until none is left; the root's are never touched"
seed
out=$(run) && code=0 || code=$?
expect "terminals exit" "$code" 0
expect "term_dev closed" "$(term term_dev)" exited
expect "term_watch closed" "$(term term_watch)" exited
expect "term_done never closed again" "$(calls "close term_done")" 0
expect "term_root untouched" "$(term term_root)" running
expect "term_root never closed" "$(calls "close term_root")" 0
expect "term_else untouched" "$(term term_else)" running
expect "term_dev saved for the resume" "$(jq -rs '.[] | select(.id == "term_dev") | [.kind, .threadId, .title, .initialCwd] | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" \
	"terminal thr_w1 pnpm dev /work/app"
expect "term_watch saved for the resume" "$(jq -rs '[.[] | select(.kind == "terminal") | .id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" "term_dev term_watch"
expect "term_dev named" "$(grep -c '^closed terminal term_dev of thr_w1 (pnpm dev) in /work/app' <<<"$out" || true)" 1
expect "every close is --if-clean" "$(grep -c '^force ' "$S/calls" || true)" 0
expect "settled" "$(grep -c '^settled ' <<<"$out" || true)" 1

echo "# a terminal that took input stays open: never force-closed, tried once, no recovery row, named with its first input, and the tree is left unsettled for the operator"
seed
jq '. + [{"id":"term_repl","threadId":"thr_w1","title":"psql","initialCwd":"/work/app","status":"running","exitCode":null,"closeReason":null,"lastUserInputAt":1758844800000}]' \
	"$S/terminals.json" > "$S/terminals.new" && mv "$S/terminals.new" "$S/terminals.json"
out=$(run) && code=0 || code=$?
expect "typed-in exit" "$code" 1
expect "typed-in still running" "$(term term_repl)" running
expect "typed-in never force-closed" "$(grep -c '^force ' "$S/calls" || true)" 0
expect "typed-in tried once, not every pass" "$(calls "close term_repl")" 1
expect "typed-in named" "$(grep -c '^  thr_w1 term_repl running psql 2025-09-26T00:00:00Z$' <<<"$out" || true)" 1
expect "typed-in keeps no recovery row" "$(jq -rs '[.[] | select(.id == "term_repl")] | length' "$S/storage/pause-tree-thr_root.jsonl")" 0
expect "typed-in never reports settled" "$(grep -c '^settled ' <<<"$out" || true)" 0
expect "clean terminals still closed" "$(term term_dev) $(term term_watch)" "exited exited"
for id in thr_sub thr_w1 thr_w2 thr_far thr_told thr_woken thr_behind thr_done; do expect "$id" "$(status "$id")" idle/none; done

echo "# input that reaches a terminal between its listing and its close keeps it open too"
seed
out=$(run TYPED=term_dev) && code=0 || code=$?
expect "typed-late exit" "$code" 1
expect "typed-late still running" "$(term term_dev)" running
expect "typed-late named" "$(grep -c '^  thr_w1 term_dev running pnpm dev 2025-09-26T00:00:00Z$' <<<"$out" || true)" 1
expect "typed-late keeps no recovery row" "$(jq -rs '[.[] | select(.id == "term_dev")] | length' "$S/storage/pause-tree-thr_root.jsonl")" 0
expect "typed-late clean terminal still closed" "$(term term_watch)" exited

echo "# a terminal that will not close keeps the tree unsettled, is named, and keeps no recovery row"
seed
out=$(run TERMFAIL=term_dev) && code=0 || code=$?
expect "unclosed exit" "$code" 1
expect "unclosed still running" "$(term term_dev)" running
expect "unclosed named" "$(grep -c '^  thr_w1 term_dev running pnpm dev$' <<<"$out" || true)" 1
expect "unclosed never reports settled" "$(grep -c '^settled ' <<<"$out" || true)" 0
expect "unclosed row dropped" "$(jq -rs '[.[] | select(.id == "term_dev")] | length' "$S/storage/pause-tree-thr_root.jsonl")" 0

echo "# no terminal is closed unless its recovery row is saved first"
if [ "$(id -u)" != 0 ]; then
	seed
	out=$(run LOCK_ON_TERMINALS=1) && code=0 || code=$?
	chmod 755 "$S/storage"
	expect "unsaved exit" "$code" 1
	expect "unsaved closes nothing" "$(grep -c '^close ' "$S/calls" || true)" 0
	expect "unsaved term_dev still running" "$(term term_dev)" running
	expect "unsaved names the save failure" "$(grep -c '^error: cannot save terminal' <<<"$out" || true)" 1
fi

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

echo "# a pause reaches every thread BB's archive of the root reaches: lifecycle dependents in any project, and hidden forks at any depth with their children, but not a visible fork"
seed
cat > "$S/extra.json" <<'EOF'
[{"id":"thr_fork","projectId":"proj","parentThreadId":null,"sourceThreadId":"thr_w1","status":"active","visibility":"hidden"},
 {"id":"thr_forkkid","projectId":"proj","parentThreadId":"thr_fork","status":"active","visibility":"hidden"},
 {"id":"thr_rootfork","projectId":"proj","parentThreadId":null,"sourceThreadId":"thr_root","status":"idle","visibility":"hidden","machineTurn":true},
 {"id":"thr_dep","projectId":"proj_dep","parentThreadId":null,"lifecycleOwnerThreadId":"thr_root","status":"active","visibility":"visible"},
 {"id":"thr_visfork","projectId":"proj","parentThreadId":null,"sourceThreadId":"thr_sub","status":"active","visibility":"visible"}]
EOF
jq -s add "$S/threads.json" "$S/extra.json" > "$S/threads.new" && mv "$S/threads.new" "$S/threads.json"
{
	jq '.[]' "$S/queue.json"
	msg msg_deptell thr_dep agent thr_root cli time "Dependent brief."
	msg msg_rootforktell thr_rootfork agent thr_root cli time "Root fork brief."
	msg msg_forktell thr_forkkid agent thr_fork cli time "Fork kid brief."
} | jq -s . > "$S/queue.new" && mv "$S/queue.new" "$S/queue.json"
cat > "$S/extra.json" <<'EOF'
[{"id":"auto_fork","projectId":"proj","enabled":true,"createdByThreadId":"thr_fork","execution":{"mode":"agent","targetThreadId":"thr_fork"}},
 {"id":"auto_dep","projectId":"proj_dep","enabled":true,"createdByThreadId":"thr_root","execution":{"mode":"agent","targetThreadId":"thr_dep"}},
 {"id":"auto_visfork","projectId":"proj","enabled":true,"createdByThreadId":null,"execution":{"mode":"agent","targetThreadId":"thr_visfork"}}]
EOF
jq -s add "$S/automations.json" "$S/extra.json" > "$S/automations.new" && mv "$S/automations.new" "$S/automations.json"
out=$(run) && code=0 || code=$?
expect "forks exit" "$code" 0
for id in thr_fork thr_forkkid thr_rootfork thr_dep; do
	expect "$id" "$(status "$id")" idle/none
	expect "$id stopped at least once" "$([ "$(calls "stop $id")" -ge 1 ] && echo yes || echo no)" yes
done
expect "no machine turn left running" "$(jq -r '[.[] | select(.machineTurn == true) | .id] | join(" ")' "$S/threads.json")" ""
expect "term_fork closed" "$(term term_fork)" exited
expect "auto_fork" "$(enabled auto_fork)" false
expect "auto_dep paused in the dependent's project" "$(grep -c '^paused automation auto_dep in proj_dep$' <<<"$out" || true)" 1
expect "dependent's tell saved" "$(jq -rs '[.[] | select(.id == "msg_deptell") | .content[0].text] | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" "Dependent brief."
echo "# each saved row and each stop records the route the pause took, so the resume can recover a dependent or a fork no parent link reaches"
route() { jq -rsc --arg id "$1" '.[] | select(.id == $id) | .route | map("\(.threadId):\(.link)") | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null; }
expect "dependent's row routed by its lifecycle link" "$(route msg_deptell)" "thr_dep:dependent"
expect "root fork's row routed by its fork link" "$(route msg_rootforktell)" "thr_rootfork:fork"
expect "fork kid's row routed through its fork" "$(route msg_forktell)" "thr_sub:child thr_w1:child thr_fork:fork thr_forkkid:child"
expect "fork terminal's row routed through its fork" "$(route term_fork)" "thr_sub:child thr_w1:child thr_fork:fork"
expect "every route ends at its row's thread, the root's rows have none" \
	"$(jq -rs 'all(.[]; if .threadId == "thr_root" then .route == [] else .route[-1].threadId == .threadId end)' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" true
expect "a stop names its route" "$([ "$(grep -c '^stopped thr_forkkid via thr_sub (child) > thr_w1 (child) > thr_fork (fork) > thr_forkkid (child)$' <<<"$out" || true)" -ge 1 ] && echo yes || echo no)" yes
expect "thr_visfork untouched" "$(status thr_visfork)" active/none
expect "thr_visfork never stopped" "$(calls "stop thr_visfork")" 0
expect "auto_visfork untouched" "$(enabled auto_visfork)" true
expect "root never stopped" "$(calls "stop thr_root")" 0

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
	"msg_behind msg_due msg_fardue msg_rootdue msg_roottell msg_tell term_dev term_watch"
expect "newest content wins" "$(jq -rs '.[] | select(.id == "msg_tell") | .content[0].text' "$S/storage/pause-tree-thr_root.jsonl")" "Phase 2 brief."

echo "# a delete that fails while the message stays queued leaves it unsaved; one that fails after it left the queue keeps its row"
seed
out=$(run REFUSE=msg_tell) && code=0 || code=$?
expect "refused exit" "$code" 1
expect "refused message still queued" "$(queued thr_told)" "msg_tell"
expect "refused message unsaved" "$(jq -rs '[.[] | select(.kind != "terminal") | .id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl")" \
	"msg_behind msg_due msg_fardue msg_rootdue msg_roottell"
seed
out=$(run LOST=msg_tell) && code=0 || code=$?
expect "lost exit" "$code" 0
expect "lost message kept" "$(jq -rs '[.[] | select(.id == "msg_tell") | .content[0].text] | join(" ")' "$S/storage/pause-tree-thr_root.jsonl")" "Phase 2 brief."

echo
echo "$out"
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
