#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/pause-tree.sh.
# A stub `bb` holds a coordinator, sub-coordinator and worker tree with a hidden
# worker, stops threads the way BB does (a stopped child's report wakes its idle
# parent), and records automation pauses. Asserts the end state of every thread
# and automation.
# Usage: pause-tree.test.sh <path to pause-tree.sh>
set -eu
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/pause-tree-test.$$"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/stub"

cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
state="$S/threads.json" autos="$S/automations.json"
update() { jq "\$@" "\$state" > "\$state.new" && mv "\$state.new" "\$state"; }
case "\$1 \$2" in
	"thread list")
		parent=""; hidden=""; prev=""
		for a in "\$@"; do [ "\$prev" = --parent-thread ] && parent="\$a"; [ "\$a" = --include-hidden ] && hidden=1; prev="\$a"; done
		jq --arg p "\$parent" --arg h "\$hidden" '[.[] | select(.parentThreadId == \$p) | select(\$h != "" or .visibility == "visible")]' "\$state" ;;
	"thread stop")
		id="\$3"
		[ "\$id" = "\${STUCK:-}" ] && { update --arg id "\$id" 'map(if .id == \$id then .status = "stopping" else . end)'; exit 0; }
		busy=\$(jq -r --arg id "\$id" '.[] | select(.id == \$id) | .status | IN("pending", "starting", "active", "stopping")' "\$state")
		update --arg id "\$id" 'map(if .id == \$id then .status = "idle" | .queuedWork = "none" else . end)'
		parent=\$(jq -r --arg id "\$id" '.[] | select(.id == \$id) | .parentThreadId // ""' "\$state")
		[ "\$busy" = true ] && [ -n "\$parent" ] && update --arg p "\$parent" 'map(if .id == \$p and .status == "idle" then .status = "active" else . end)'
		exit 0 ;;
	"automation list") cat "\$autos" ;;
	"automation pause") jq --arg id "\$3" 'map(if .id == \$id then .enabled = false else . end)' "\$autos" > "\$autos.new" && mv "\$autos.new" "\$autos" ;;
	*) exit 2 ;;
esac
EOF
chmod +x "$S/stub/bb"

seed() {
	cat > "$S/threads.json" <<'EOF'
[{"id":"thr_root","parentThreadId":null,"status":"active","queuedWork":"none","visibility":"visible"},
 {"id":"thr_sub","parentThreadId":"thr_root","status":"active","queuedWork":"none","visibility":"visible"},
 {"id":"thr_w1","parentThreadId":"thr_sub","status":"active","queuedWork":"none","visibility":"visible"},
 {"id":"thr_w2","parentThreadId":"thr_sub","status":"active","queuedWork":"none","visibility":"hidden"},
 {"id":"thr_queued","parentThreadId":"thr_root","status":"idle","queuedWork":"waiting","visibility":"visible"},
 {"id":"thr_done","parentThreadId":"thr_root","status":"idle","queuedWork":"none","visibility":"visible"},
 {"id":"thr_elsewhere","parentThreadId":null,"status":"active","queuedWork":"none","visibility":"visible"}]
EOF
	cat > "$S/automations.json" <<'EOF'
[{"id":"auto_tick","enabled":true,"execution":{"mode":"agent","targetThreadId":"thr_root"}},
 {"id":"auto_worker","enabled":true,"targetThreadId":"thr_w2"},
 {"id":"auto_spawner","enabled":true,"execution":{"mode":"agent"}},
 {"id":"auto_other","enabled":true,"execution":{"mode":"agent","targetThreadId":"thr_elsewhere"}}]
EOF
}
run() { env PATH="$S/stub:$PATH" BB_PROJECT_ID=proj PAUSE_TREE_SETTLE=0 "$@" bash "$script" thr_root 2>&1; }
status() { jq -r --arg id "$1" '.[] | select(.id == $id) | "\(.status)/\(.queuedWork)"' "$S/threads.json"; }
enabled() { jq -r --arg id "$1" '.[] | select(.id == $id) | .enabled' "$S/automations.json"; }

fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1 = $2"; else echo "FAIL $1 got '$2' want '$3'"; fail=1; fi; }

seed
out=$(run) && code=0 || code=$?
expect "exit" "$code" 0
for id in thr_sub thr_w1 thr_w2 thr_queued thr_done; do expect "$id" "$(status "$id")" idle/none; done
expect "thr_root keeps running" "$(status thr_root)" active/none
expect "thr_elsewhere untouched" "$(status thr_elsewhere)" active/none
expect "auto_tick" "$(enabled auto_tick)" false
expect "auto_worker" "$(enabled auto_worker)" false
expect "auto_spawner untouched" "$(enabled auto_spawner)" true
expect "auto_other untouched" "$(enabled auto_other)" true

seed
out=$(run STUCK=thr_w1) && code=0 || code=$?
expect "stuck exit" "$code" 1
expect "stuck thread named" "$(grep -c 'thr_w1 stopping' <<<"$out")" 1

echo
echo "$out"
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
