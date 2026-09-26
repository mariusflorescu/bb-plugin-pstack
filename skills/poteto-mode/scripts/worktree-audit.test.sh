#!/usr/bin/env bash
# Rerunnable check for skills/poteto-mode/scripts/worktree-audit.sh.
# Builds a scratch repo with a dozen worktrees and a stub `bb` and `gh`, runs
# the audit, and asserts each row's columns by header name. Stub paths use the
# non-canonical $TMPDIR form while git lists canonical paths, so a pass also
# proves the path canonicalization.
# Usage: worktree-audit.test.sh <path to worktree-audit.sh>
set -eu
audit="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
S="${TMPDIR:-/tmp}/wt-audit-test.$$"
trap 'rm -rf "$S" "$S.link"' EXIT
mkdir -p "$S/stub/logs"
cd "$S"

git init -q --bare origin.git
git init -q -b main repo
cd repo
git config user.email t@t
git config user.name t
echo a > a.txt && git add a.txt && git commit -qm init
git remote add origin "$S/origin.git" && git push -q origin main
wt() { git worktree add -q -b "$1" "$S/wt-$1" && (cd "$S/wt-$1" && echo "$1" > "$1.txt" && git add . && git commit -qm "$1"); }
wt_at_main() { git worktree add -q -b "$1" "$S/wt-$1"; }
wt merged && git merge -q --ff-only merged && git push -q origin main
for name in wip inuse running child recent; do wt "$name"; done
for name in hidden parent leaf new renamed staged byname byslash bytilde kid nested nestpin gonesub sib byproj bymain; do wt_at_main "$name"; done
mkdir -p "$S/wt-nested/scripts" "$S/wt-nestpin/packages/app" "$S/wt-sib-x" "$S/repo/tools"
git worktree add -q -b spaced "$S/wt-sp ace"
ln -s "$S" "$S.link"
git worktree add -q --detach "$S/wt-detached" && (cd "$S/wt-detached" && echo d > d.txt && git add . && git commit -qm detached)
echo edited >> "$S/wt-wip/a.txt"
echo edited >> "$S/wt-leaf/a.txt"
echo 'export const x = 1' > "$S/wt-new/new.ts"
mkdir "$S/wt-renamed/notes" && echo draft > "$S/wt-renamed/notes/a.md" && echo todo > "$S/wt-renamed/notes/todo.md"
echo scratch > "$S/wt-inuse/scratch.md"
(cd "$S/wt-staged" && echo staged1 > a.txt && git add a.txt && echo final > a.txt)
echo scratch > "$S/wt-running/scratch.md"

# Submodules: outer nests inner, and each sub* worktree checks outer out recursively.
gitc() { git -c user.email=t@t -c user.name=t -c protocol.file.allow=always "$@"; }
for r in inner outer; do git init -q -b main "$S/$r" && echo "$r" > "$S/$r/$r.txt" && git -C "$S/$r" add . && gitc -C "$S/$r" commit -qm "$r"; done
gitc -C "$S/outer" submodule add -q "$S/inner" inner && gitc -C "$S/outer" commit -qm inner
sm() { git worktree add -q -b "$1" "$S/wt-$1" && (cd "$S/wt-$1" && gitc submodule add -q "$S/outer" outer && gitc submodule update -q --init --recursive && git commit -qm "$1"); }
for name in subclean subdirty subnew subignored subcommit subgone subbare; do sm "$name"; done
echo edited >> "$S/wt-subdirty/outer/inner/inner.txt"
echo draft > "$S/wt-subnew/outer/notes.md"
(cd "$S/wt-subignored" && git config -f .gitmodules submodule.outer.ignore all && git commit -qam ignore && echo edited >> outer/outer.txt)
(cd "$S/wt-subcommit" && echo more >> outer/outer.txt && gitc -C outer commit -qam local && git commit -qam bump)
rm -rf "$S/repo/.git/worktrees/wt-subgone/modules/outer"
rm "$S/wt-subbare/outer/.git"

now=$(( $(date +%s) * 1000 )); old=$(( now - 10 * 86400 * 1000 ))
envrow() { printf '{"id":"env_%s","projectId":"%s","hostId":"%s","path":"%s"}' "$1" "${3:-proj_here}" "${4:-host_here}" "$2"; }
{
	printf '[%s' "$(envrow far "$S/wt-merged" proj_far host_far)"
	printf ',%s' "$(envrow main "$S/repo")" "$(envrow far2 "$S/elsewhere" proj_far)"
	for name in merged inuse running child recent hidden parent leaf kid; do printf ',%s' "$(envrow "$name" "$S/wt-$name")"; done
	# Attached below a worktree's root, one of them at a directory since deleted.
	printf ',%s' "$(envrow nested "$S/wt-nested/scripts")" "$(envrow nestpin "$S/wt-nestpin/packages/app" proj_nest)" \
		"$(envrow gonesub "$S/wt-gonesub/dist/")" "$(envrow sibx "$S/wt-sib-x")" "$(envrow tools "$S/repo/tools" proj_tools)"
	printf ']\n'
} > "$S/stub/envs.json"
thread() { # id env status pinnedAt parent updatedAt [visibility] [source] [project]
	printf '{"id":"%s","projectId":"%s","environmentId":"%s","status":"%s","pinnedAt":%s,"parentThreadId":%s,"lifecycleOwnerThreadId":null,"sourceThreadId":%s,"visibility":"%s","archivedAt":null,"queuedWork":"none","updatedAt":%s}' \
		"$1" "${9:-proj_here}" "$2" "$3" "$4" "$5" "${8:-null}" "${7:-visible}" "$6"
}
{
	printf '[%s' "$(thread thr_self env_main active null null "$now")"
	printf ',%s' \
		"$(thread thr_a env_merged idle null null "$old")" \
		"$(thread thr_a2 env_merged idle null null "$old" hidden '"thr_a"')" \
		"$(thread thr_far env_far idle "$old" null "$old" visible null proj_far)" \
		"$(thread thr_b env_inuse idle "$old" null "$old")" \
		"$(thread thr_c env_running stopping null null "$old")" \
		"$(thread thr_d env_child idle null '"thr_b"' "$old")" \
		"$(thread thr_e env_recent idle null null "$now")" \
		"$(thread thr_h env_hidden active null null "$old" hidden)" \
		"$(thread thr_p env_parent idle null null "$old")" \
		"$(thread thr_leaf env_leaf idle null '"thr_mid"' "$old")" \
		"$(thread thr_kid env_kid idle null '"thr_self"' "$old")" \
		"$(thread thr_m env_main idle "$old" null "$old")" \
		"$(thread thr_x env_main active null null "$old")" \
		"$(thread thr_q env_far2 active null null "$old" visible null proj_far)" \
		"$(thread thr_n env_nested active null null "$old")" \
		"$(thread thr_np env_nestpin idle "$old" null "$old" visible null proj_nest)" \
		"$(thread thr_g env_gonesub active null null "$old")" \
		"$(thread thr_s env_sibx active null null "$old")" \
		"$(thread thr_t env_tools idle null null "$old" visible null proj_tools)"
	printf ']\n'
} > "$S/stub/threads.json"
jq -c --argjson t "$old" '.[] | select(.id == "thr_p") | .id = "thr_mid" | .environmentId = "env_gone" | .parentThreadId = "thr_p" | .archivedAt = $t' \
	"$S/stub/threads.json" | jq -s . > "$S/stub/archived.json"
jq -n --arg link "cat $S.link/wt-byname/src/x.ts" --arg slash "ls $S//wt-byslash/lib" --arg tilde "cd ~/wt-bytilde && make" \
	--arg space "open $(cd "$S" && pwd -P)/wt-sp ace/notes.md" \
	'[$link, $slash, $tilde, $space | {data: {command: .}}]' > "$S/stub/logs/thr_m.json"
echo "[{\"data\":{\"command\":\"ls $S/wt-merged-copy/\"}}]" > "$S/stub/logs/thr_x.json"
echo "[{\"data\":{\"command\":\"ls $S/wt-merged/\"}}]" > "$S/stub/logs/thr_q.json"
echo "[{\"data\":{\"command\":\"cat $S/wt-byproj/src/y.ts\"}}]" > "$S/stub/logs/thr_np.json"
echo "[{\"data\":{\"command\":\"cat $S/wt-bymain/src/z.ts\"}}]" > "$S/stub/logs/thr_t.json"
echo "[{\"data\":{\"text\":\"$(ls -d "$S"/wt-* | grep -v /wt-merged | tr '\n' ' ')\"}}]" > "$S/stub/logs/thr_self.json"

cat > "$S/stub/gh" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
cat > "$S/stub/bb" <<EOF
#!/usr/bin/env bash
[ -n "\${BB_STUB_FAIL:-}" ] && { echo '{"ok":false,"error":{"code":"down","message":"down"}}'; exit 1; }
cmd="\$1 \$2"; shift 2
host=""; archived=""; hidden=""; prev=""
for a in "\$@"; do
	case "\$prev" in --host) host="\$a" ;; esac
	case "\$a" in --archived) archived=1 ;; --include-hidden) hidden=1 ;; esac
	prev="\$a"
done
case "\$cmd" in
	"environment show") jq -e --arg id "\$1" '.[] | select(.id == \$id)' "$S/stub/envs.json" ;;
	"environment list") jq --arg h "\$host" '[.[] | select(\$h == "" or .hostId == \$h)]' "$S/stub/envs.json" ;;
	"thread list") file=threads; [ -n "\$archived" ] && file=archived
		jq --arg h "\$hidden" '[.[] | select(\$h != "" or .visibility == "visible")]' "$S/stub/\$file.json" ;;
	"thread log") echo "\$1" >> "$S/stub/logs-read"
		[ -n "\${BB_STUB_FAIL_LOG:-}" ] && exit 1
		cat "$S/stub/logs/\$1.json" 2>/dev/null || echo '[]' ;;
	*) exit 2 ;;
esac
EOF
chmod +x "$S/stub/bb" "$S/stub/gh"

fail=0
field() {
	awk -F'\t' -v n="/wt-$2" -v c="$3" '$1 == "SIZE" { for (i = 1; i <= NF; i++) if ($i == c) k = i; next }
		n == "/wt-*" ? index($NF, "/wt-") : substr($NF, length($NF) - length(n) + 1) == n { print (k ? $k : "<no " c " column>") }' <<<"$1"
}
check() {
	local out="$1" name="$2" kv col want got
	shift 2
	for kv in "$@"; do
		col="${kv%%=*}" want="${kv#*=}"
		got=$(field "$out" "$name" "$col")
		# shellcheck disable=SC2053
		if [[ "$got" == $want ]]; then echo "ok   $name $col=$got"; else echo "FAIL $name $col got '$got' want '$want'"; fail=1; fi
	done
}
assert() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
run() { env PATH="$S/stub:$PATH" HOME="$S" BB_ENVIRONMENT_ID=env_main BB_PROJECT_ID=proj_here BB_THREAD_ID=thr_self "$@" bash "$audit" "$S/repo" 2>&1; }

out=$(run)
check "$out" wip BUCKET=hold-wip DIRTY=wip:1
check "$out" merged ENV=env_merged CASCADE=- MENTIONS=- BUCKET=safe
echo "# a thread in use outranks uncommitted work, since a user can release work but not a live thread"
check "$out" inuse ENV=env_inuse DIRTY=untracked:1 BUCKET=hold-in-use
check "$out" running DIRTY=untracked:1 BUCKET=hold-in-use
check "$out" child "LAST_THREAD=*,pinned" BUCKET=hold-in-use
check "$out" recent BUCKET=verify-recent-chat
check "$out" hidden BUCKET=hold-in-use

echo "# archiving a clean worktree's threads must not retire another worktree"
check "$out" parent CASCADE=env_leaf BUCKET=hold-cascade
check "$out" leaf BUCKET=hold-wip

echo "# untracked files, counted one by one, and commits no ref contains are work removal loses"
check "$out" new DIRTY=untracked:1 BUCKET=hold-wip
check "$out" renamed DIRTY=untracked:2 BUCKET=hold-wip
check "$out" detached DIRTY=unreachable BUCKET=hold-wip

echo "# environments come from this machine; logs come from this repo's projects, however a path is spelled"
check "$out" byname ENV=- MENTIONS=thr_m BUCKET=hold-in-use
check "$out" byslash MENTIONS=thr_m BUCKET=hold-in-use
check "$out" bytilde MENTIONS=thr_m BUCKET=hold-in-use
check "$out" "sp ace" MENTIONS=thr_m BUCKET=hold-in-use
assert "never reads another project's log" '! grep -qx thr_q "$S/stub/logs-read" 2>/dev/null'
assert "never reads its own log" '! grep -qx thr_self "$S/stub/logs-read" 2>/dev/null'

echo "# a thread attached below a worktree's root holds it, and its project's logs are scanned"
check "$out" nested ENV=env_nested "LAST_THREAD=*,running" BUCKET=hold-in-use
check "$out" nestpin ENV=env_nestpin "LAST_THREAD=*,pinned" BUCKET=hold-in-use
check "$out" gonesub ENV=env_gonesub "LAST_THREAD=*,running" BUCKET=hold-in-use
check "$out" sib ENV=- LAST_THREAD=- BUCKET=safe
check "$out" byproj MENTIONS=thr_np BUCKET=hold-in-use
check "$out" bymain MENTIONS=thr_t
assert "reads the logs of a project attached below the main worktree" 'grep -qx thr_t "$S/stub/logs-read" 2>/dev/null'

echo "# the auditing thread holds the worktree it works in, not its children's"
check "$out" kid "LAST_THREAD=????-??-??T??:??:??.???Z" BUCKET=safe
check "$(run BB_THREAD_ID=thr_a)" merged "LAST_THREAD=*,running" BUCKET=hold-in-use

echo "# unknown BB state holds every row: bb down, one log unreadable, no BB environment"
down=$(run BB_STUB_FAIL=1)
nolog=$(run BB_STUB_FAIL_LOG=1)
nohost=$(run BB_ENVIRONMENT_ID=)
assert "bb down warns" 'grep -q "^warn: .*hold-unknown" <<<"$down"'
for o in "$down" "$nolog" "$nohost"; do
	check "$o" merged BUCKET=hold-unknown
	assert "no row is safe" '! field "$o" "*" BUCKET | grep -qx safe'
done

echo "# an approval binds to the snapshot: HEAD, the index, the tracked diff, and each untracked path and content"
check "$out" merged SNAPSHOT=-
for name in wip new renamed detached leaf staged; do
	check "$out" "$name" "SNAPSHOT=[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]"
done
echo other >> "$S/wt-wip/a.txt"
echo 'rm -rf ~' > "$S/wt-new/new.ts"
mv "$S/wt-renamed/notes/a.md" "$S/wt-renamed/notes/b.md"
(cd "$S/wt-detached" && git commit -q --amend -m amended)
# Restaging changes only the index: HEAD and the working tree read the same.
(cd "$S/wt-staged" && echo staged2 > a.txt && git add a.txt && echo final > a.txt)
snap=$(env PATH="$S/stub:$PATH" BB_ENVIRONMENT_ID=env_main BB_PROJECT_ID=proj_here BB_THREAD_ID=thr_self \
	bash "$audit" "$S/repo" "$S/wt-wip" "$S/wt-new" "$S/wt-renamed" "$S/wt-detached" "$S/wt-leaf" "$S/wt-staged" 2>&1)
for kv in wip=wip:1 new=untracked:1 renamed=untracked:2 detached=unreachable leaf=wip:1 staged=wip:1; do check "$snap" "${kv%%=*}" "DIRTY=${kv#*=}"; done
for name in wip new renamed detached staged; do
	assert "$name snapshot changes with its content" '[ "$(field "$snap" "$name" SNAPSHOT)" != "$(field "$out" "$name" SNAPSHOT)" ]'
done
assert "leaf snapshot is stable" '[ "$(field "$snap" leaf SNAPSHOT)" = "$(field "$out" leaf SNAPSHOT)" ]'

echo "# a submodule's work counts at any depth, whatever ignore it has, and so do commits only its repository holds"
check "$out" subclean DIRTY=clean SNAPSHOT=- BUCKET=review
hex=$(printf '[0-9a-f]%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)
check "$out" subdirty DIRTY=wip:1 "SNAPSHOT=$hex" BUCKET=hold-wip
check "$out" subnew DIRTY=untracked:1 "SNAPSHOT=$hex" BUCKET=hold-wip
check "$out" subignored DIRTY=wip:1 "SNAPSHOT=$hex" BUCKET=hold-wip
check "$out" subcommit DIRTY=unreachable "SNAPSHOT=$hex" BUCKET=hold-wip
echo "# a submodule it cannot read holds the row"
check "$out" subgone BUCKET=hold-unknown
check "$out" subbare BUCKET=hold-unknown
echo "# the snapshot binds each submodule's content and local commits while the gitlink reads the same"
gitlink() { git -C "$S/wt-$1" diff HEAD --submodule=short --ignore-submodules=none; }
before=$(for name in subdirty subnew subcommit; do gitlink "$name"; done)
echo other >> "$S/wt-subdirty/outer/inner/inner.txt"
echo 'rm -rf ~' > "$S/wt-subnew/outer/notes.md"
(cd "$S/wt-subcommit/outer" && git checkout -q -b side && echo side >> outer.txt && gitc commit -qam side && git checkout -q main)
subsnap=$(env PATH="$S/stub:$PATH" BB_ENVIRONMENT_ID=env_main BB_PROJECT_ID=proj_here BB_THREAD_ID=thr_self \
	bash "$audit" "$S/repo" "$S/wt-subdirty" "$S/wt-subnew" "$S/wt-subcommit" 2>&1)
assert "every gitlink and its diff read the same" '[ "$(for name in subdirty subnew subcommit; do gitlink "$name"; done)" = "$before" ]'
for kv in subdirty=wip:1 subnew=untracked:1 subcommit=unreachable; do check "$subsnap" "${kv%%=*}" "DIRTY=${kv#*=}"; done
for name in subdirty subnew subcommit; do
	assert "$name snapshot changes with its submodule" '[ "$(field "$subsnap" "$name" SNAPSHOT)" != "$(field "$out" "$name" SNAPSHOT)" ]'
done

echo "# an approval binds to LAST_THREAD: activity later the same day, even a millisecond later, changes it"
jq '(.[] | select(.id == "thr_e") | .updatedAt) += 1' "$S/stub/threads.json" > "$S/stub/threads.new" && mv "$S/stub/threads.new" "$S/stub/threads.json"
later=$(env PATH="$S/stub:$PATH" BB_ENVIRONMENT_ID=env_main BB_PROJECT_ID=proj_here BB_THREAD_ID=thr_self \
	bash "$audit" "$S/repo" "$S/wt-recent" 2>&1)
check "$later" recent BUCKET=verify-recent-chat
assert "recent LAST_THREAD moves with new activity" '[ "$(field "$later" recent LAST_THREAD)" != "$(field "$out" recent LAST_THREAD)" ]'

echo "# a recheck names only the worktrees about to be pruned"
recheck=$(env PATH="$S/stub:$PATH" BB_ENVIRONMENT_ID=env_main BB_PROJECT_ID=proj_here BB_THREAD_ID=thr_self \
	bash "$audit" "$S/repo" "$S/wt-merged" "$S/wt-parent" 2>&1)
assert "recheck prints exactly the two named rows" '[ "$(grep -c "/wt-" <<<"$recheck")" = 2 ]'
check "$recheck" merged BUCKET=safe
check "$recheck" parent BUCKET=hold-cascade

echo "# no setting that narrows git status hides work: untracked files hidden in the repo and in a submodule, a submodule's ignore for its own submodule"
git -C "$S/repo" config status.showUntrackedFiles no
git -C "$S/wt-subnew/outer" config status.showUntrackedFiles no
git -C "$S/wt-subdirty/outer" config submodule.inner.ignore all
narrowed=$(env PATH="$S/stub:$PATH" BB_ENVIRONMENT_ID=env_main BB_PROJECT_ID=proj_here BB_THREAD_ID=thr_self \
	bash "$audit" "$S/repo" "$S/wt-new" "$S/wt-renamed" "$S/wt-subnew" "$S/wt-subdirty" 2>&1)
for kv in new=untracked:1 renamed=untracked:2 subnew=untracked:1 subdirty=wip:1; do
	check "$narrowed" "${kv%%=*}" "DIRTY=${kv#*=}" "SNAPSHOT=$hex" BUCKET=hold-wip
done

echo
echo "$out"
[ "$fail" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
