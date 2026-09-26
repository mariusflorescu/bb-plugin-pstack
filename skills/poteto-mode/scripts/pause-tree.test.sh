#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/pause-tree.sh.
# A stub `bb` holds a coordinator, sub-coordinator and worker tree with a hidden
# worker and behaves the way BB does: a stop leaves the queue alone, a message
# queued behind a turn dispatches when that turn ends, a stopped child's report
# wakes its idle parent, and a thread list derives queuedWork from the queue.
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
				echo "delete \$5" >> "\$calls"
				update "\$queue" --arg m "\$5" 'map(select(.id != \$m))' ;;
			*) exit 2 ;;
		esac ;;
	"thread stop")
		id="\$3"
		echo "stop \$id" >> "\$calls"
		[ "\$id" = "\${STUCK:-}" ] && { update "\$state" --arg id "\$id" 'map(if .id == \$id then .status = "stopping" else . end)'; exit 0; }
		busy=\$(jq -r --arg id "\$id" '.[] | select(.id == \$id) | .status | IN("pending", "starting", "active", "stopping")' "\$state")
		[ "\$busy" = true ] || exit 0
		update "\$state" --arg id "\$id" 'map(if .id == \$id then .status = "idle" else . end)'
		parent=\$(jq -r --arg id "\$id" '.[] | select(.id == \$id) | .parentThreadId // ""' "\$state")
		[ -n "\$parent" ] && update "\$state" --arg p "\$parent" 'map(if .id == \$p and .status == "idle" then .status = "active" else . end)'
		next=\$(jq -r --arg id "\$id" '[.[] | select(.threadId == \$id and (.waitingOn == null or .waitingOn.kind == "thread-busy"))][0].id // ""' "\$queue")
		if [ -n "\$next" ]; then
			echo "dispatch \$next" >> "\$calls"
			update "\$queue" --arg m "\$next" 'map(select(.id != \$m))'
			update "\$state" --arg id "\$id" 'map(if .id == \$id then .status = "active" else . end)'
		fi
		exit 0 ;;
	"automation list") cat "\$autos" ;;
	"automation pause") update "\$autos" --arg id "\$3" 'map(if .id == \$id then .enabled = false else . end)' ;;
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
[{"id":"thr_root","parentThreadId":null,"status":"active","visibility":"visible"},
 {"id":"thr_sub","parentThreadId":"thr_root","status":"active","visibility":"visible"},
 {"id":"thr_w1","parentThreadId":"thr_sub","status":"active","visibility":"visible"},
 {"id":"thr_w2","parentThreadId":"thr_sub","status":"active","visibility":"hidden"},
 {"id":"thr_told","parentThreadId":"thr_root","status":"idle","visibility":"visible"},
 {"id":"thr_woken","parentThreadId":"thr_sub","status":"idle","visibility":"visible"},
 {"id":"thr_behind","parentThreadId":"thr_root","status":"active","visibility":"visible"},
 {"id":"thr_done","parentThreadId":"thr_root","status":"idle","visibility":"visible"},
 {"id":"thr_elsewhere","parentThreadId":null,"status":"active","visibility":"visible"}]
EOF
	{
		msg msg_tell thr_told agent thr_sub cli time "Phase 2 brief."
		msg msg_due thr_woken user "" plugin interaction $'[bb automation due:auto_worker]\n\nAudit tick.'
		msg msg_behind thr_behind agent thr_root cli "" "Next slice."
		msg msg_else thr_elsewhere user "" app time "Not this tree."
	} | jq -s . > "$S/queue.json"
	cat > "$S/automations.json" <<'EOF'
[{"id":"auto_tick","enabled":true,"createdByThreadId":"thr_root","execution":{"mode":"agent","targetThreadId":"thr_root"}},
 {"id":"auto_worker","enabled":true,"createdByThreadId":"thr_sub","targetThreadId":"thr_w2"},
 {"id":"auto_user","enabled":true,"createdByThreadId":null,"execution":{"mode":"agent","targetThreadId":"thr_held"}},
 {"id":"auto_spawner","enabled":true,"createdByThreadId":"thr_root","execution":{"mode":"agent"}},
 {"id":"auto_other","enabled":true,"createdByThreadId":"thr_elsewhere","execution":{"mode":"agent","targetThreadId":"thr_elsewhere"}}]
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

echo "# the program's own queued tells and automation wake-ups are discarded, saved, and never dispatched"
seed
out=$(run) && code=0 || code=$?
expect "exit" "$code" 0
for id in thr_sub thr_w1 thr_w2 thr_told thr_woken thr_behind thr_done; do expect "$id" "$(status "$id")" idle/none; done
expect "thr_root keeps running" "$(status thr_root)" active/none
expect "thr_elsewhere untouched" "$(status thr_elsewhere)" active/waiting
expect "saved" "$(jq -rs '[.[].id] | sort | join(" ")' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" "msg_behind msg_due msg_tell"
expect "saved text" "$(jq -rs '.[] | select(.id == "msg_tell") | .content[0].text' "$S/storage/pause-tree-thr_root.jsonl" 2>/dev/null)" "Phase 2 brief."
expect "dispatched" "$(grep -c '^dispatch ' "$S/calls" || true)" 0
expect "auto_tick" "$(enabled auto_tick)" false
expect "auto_worker" "$(enabled auto_worker)" false
expect "auto_spawner untouched" "$(enabled auto_spawner)" true
expect "auto_other untouched" "$(enabled auto_other)" true
expect "idempotent rerun exit" "$(run >/dev/null && echo 0 || echo $?)" 0

echo "# queued work the program did not create is left in place, its thread is not stopped, and the script stops"
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
} | jq -s . > "$S/queue.new" && mv "$S/queue.new" "$S/queue.json"
out=$(run) && code=0 || code=$?
expect "held exit" "$code" 1
expect "held left queued" "$(queued thr_held)" "msg_outside msg_retry msg_user msg_userauto"
expect "held never stopped" "$(calls "stop thr_held")" 0
expect "held named" "$(grep -c '^  thr_held idle msg_user user' <<<"$out" || true)" 1
expect "auto_user paused" "$(enabled auto_user)" false
for id in thr_sub thr_w1 thr_w2 thr_told thr_woken thr_behind thr_done; do expect "$id" "$(status "$id")" idle/none; done

echo "# a thread that will not stop is named"
seed
out=$(run STUCK=thr_w1) && code=0 || code=$?
expect "stuck exit" "$code" 1
expect "stuck thread named" "$(grep -c 'thr_w1 stopping' <<<"$out")" 1

echo
echo "$out"
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
