#!/usr/bin/env bash
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, work that removal would lose (in submodules too) and a hash of it,
# remote/PR state, and BB usage: the BB environments at or inside its path on
# this machine, the threads in them or in this repo's projects whose logs name
# the path, whether any of those or an ancestor is pinned or running, and which
# other environments archiving its threads would cascade into. Emits a table
# sorted by size with a suggested bucket.
# Never deletes anything; deletion stays a human-gated step in the playbook.
# BB state it cannot read makes every row hold-unknown, never safe. Work it
# cannot read, in a submodule too, makes that row hold-unknown.
#
# Usage: worktree-audit.sh [repo-path [worktree-path...]]
#   Defaults to the current repo and all of its worktrees. Name worktrees to
#   recheck only those right before pruning.
set -u

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a git repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1
[ $# -gt 0 ] && shift

list_worktrees() { git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /, ""); print}'; }
# A path in the form git lists worktrees in: absolute, symlinks resolved at its
# longest existing prefix (so /tmp and /private/tmp compare equal even below a
# deleted directory), and no doubled or trailing slash.
canonical() {
	local p="$1" rest="" dir
	[ "${p#/}" = "$p" ] && p="$PWD/$p"
	p=$(printf '%s\n' "$p" | sed -e 's#//*#/#g' -e 's#\(.\)/$#\1#')
	while [ -n "$p" ] && [ ! -d "$p" ]; do rest="/${p##*/}$rest"; p="${p%/*}"; done
	dir=$(cd -P "${p:-/}" 2>/dev/null && pwd -P) || { printf '%s\n' "$1"; return; }
	dir="${dir%/}$rest"
	printf '%s\n' "${dir:-/}"
}

# Every absolute path on stdin, resolved through symlinks at its longest
# existing prefix, so /var and /private/var or a symlinked parent compare equal.
resolved_paths() {
	grep -oE '/[A-Za-z0-9._~@%+=/-]+' | sort -u | while read -r tok; do
		p="$tok"
		while [ -n "$p" ] && [ ! -d "$p" ]; do p="${p%/*}"; done
		[ -n "$p" ] && cd -P "$p" 2>/dev/null && printf '%s%s\n' "${PWD%/}" "${tok#"$p"}"
	done
}

# The worktrees ($wts) a thread log on stdin names, however the path is spelled.
# Resolved paths cover symlinks, doubled slashes and ~/, and each worktree's
# literal forms ($patterns) cover paths with spaces. Fails when a match errors.
mentioned_worktrees() {
	local log found="" wt pattern
	log=$(sed -e "s#~/#${HOME%/}/#g" -e 's#//*#/#g')
	while IFS=$'\t' read -r wt pattern; do
		[ -z "$pattern" ] && continue
		grep -qE "${pattern}([^A-Za-z0-9._-]|\$)" <<<"$log"
		case $? in 0) found+="$wt"$'\n' ;; 1) ;; *) return 1 ;; esac
	done <<<"$patterns"
	found+=$(resolved_paths <<<"$log" | WTS="$wts" awk 'BEGIN { n = split(ENVIRON["WTS"], w, "\n") }
		{ for (i = 1; i <= n; i++) if (w[i] != "" && ($0 == w[i] || index($0, w[i] "/") == 1)) print w[i] }') || return 1
	printf '%s\n' "$found" | sed '/^$/d' | sort -u
}

# Every checked-out submodule under $1, at any depth: a gitlink in the index
# whose directory is not empty. A linked worktree keeps its submodules'
# repositories in its own git dir, so removal deletes them with their
# commits. Fails on one that is not a repository of its own or whose path git
# has to quote, so the row holds.
submodules() {
	local index sub entries prefix
	index=$(git -C "$1" -c core.quotePath=false ls-files --stage) || return 1
	while IFS= read -r sub; do
		[ -z "$sub" ] && continue
		case "$sub" in \"*) return 1 ;; esac
		[ -e "$1/$sub" ] || continue
		entries=$(ls -A "$1/$sub") || return 1
		[ -z "$entries" ] && continue
		prefix=$(git -C "$1/$sub" rev-parse --show-prefix) && [ -z "$prefix" ] || return 1
		printf '%s\n' "$1/$sub"
		submodules "$1/$sub" || return 1
	done < <(awk -F'\t' '$1 ~ /^160000 / { print $2 }' <<<"$index" | sort -u)
}

# A commit in a submodule under $1 that no remote-tracking ref of that
# submodule contains, if any.
submodule_unpushed() {
	local subs sub ahead
	subs=$(submodules "$1") || return 1
	while IFS= read -r sub; do
		[ -z "$sub" ] && continue
		ahead=$(git -C "$sub" rev-list -n1 --all --not --remotes) || return 1
		[ -z "$ahead" ] || { printf '%s\n' "$ahead"; return 0; }
	done <<<"$subs"
}

# The work removing a worktree loses, as one hash: HEAD, every index entry
# (mode, blob and stage, since `diff HEAD` skips staged content the working
# tree has moved past), the tracked diff against HEAD, and each untracked
# file's path and content. Counts stay the same when one file is swapped for
# another, so an approval to lose work binds to this. A path git has to quote
# fails the hash, and the row holds. Git's diff names a submodule by one
# commit, so each submodule adds the same four, plus its local refs, which
# removal deletes too. A submodule it cannot read fails the hash.
work() {
	local head index diff paths blobs=""
	head=$(git -C "$1" rev-parse HEAD) || return 1
	index=$(git -C "$1" ls-files --stage) || return 1
	diff=$(git -C "$1" diff HEAD --binary --no-ext-diff --no-textconv --no-color --submodule=short --ignore-submodules=none) || return 1
	paths=$(git -C "$1" -c core.quotePath=false ls-files --others --exclude-standard) || return 1
	[ -n "$paths" ] && { blobs=$(git -C "$1" hash-object --stdin-paths <<<"$paths") || return 1; }
	printf '%s\n%s\n%s\n%s\n%s\n' "$head" "$index" "$diff" "$paths" "$blobs"
}
snapshot() {
	local all subs sub state refs
	all=$(work "$1") || return 1
	subs=$(submodules "$1") || return 1
	while IFS= read -r sub; do
		[ -z "$sub" ] && continue
		state=$(work "$sub") || return 1
		refs=$(git -C "$sub" for-each-ref --format='%(objectname) %(refname)') || return 1
		all+=$(printf '\nsubmodule %s\n%s\n%s' "${sub#"$1"/}" "$state" "$(grep -v ' refs/remotes/' <<<"$refs")")
	done <<<"$subs"
	printf '%s\n' "$all" | git hash-object --stdin | cut -c1-12
}

# Main worktree is the first entry; everything else is a candidate.
main_wt=$(list_worktrees | head -1)
all_wts=$(list_worktrees | tail -n +2)
wts="$all_wts"
if [ $# -gt 0 ]; then
	wts=$(for p in "$@"; do
		c=$(canonical "$p")
		grep -qxF "$c" <<<"$all_wts" && echo "$c" || echo "warn: $p is not a worktree of $repo" >&2
	done)
fi

# origin/main drives the merge check. Best-effort; stale is fine for a first pass.
git fetch origin main --quiet 2>/dev/null || echo "warn: could not fetch origin/main; merged column may be stale" >&2

# PR state by branch, fetched once. Empty if gh is unavailable. Kept in
# variables because bare macOS mktemp writes outside $TMPDIR, which an agent
# sandbox denies.
prs=$(gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName 2>/dev/null) || prs="[]"

# BB usage, fetched once. Environments come from this machine only, since the
# same path on another machine is a different directory. Thread metadata comes
# from every project because archiving cascades across projects; no message
# content is read from it.
bb_known=yes
bb_fail() { [ "$bb_known" = yes ] && echo "warn: $1; BB usage is unknown, so every row is hold-unknown" >&2; bb_known=no; }
bb_array() { local out; out=$(bb "$@" 2>/dev/null) && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$out" && printf '%s\n' "$out"; }

host=$(bb environment show "${BB_ENVIRONMENT_ID:-}" --json 2>/dev/null | jq -er '.hostId' 2>/dev/null) \
	|| bb_fail "cannot resolve this machine's BB host from BB_ENVIRONMENT_ID"
[ "$bb_known" = yes ] && { envs=$(bb_array environment list --host "$host" --json) || bb_fail "bb environment list failed"; }
[ "$bb_known" = yes ] && { live=$(bb_array thread list --include-hidden --json) || bb_fail "bb thread list failed"; }
[ "$bb_known" = yes ] && { archived=$(bb_array thread list --archived --include-hidden --json) || bb_fail "bb thread list --archived failed"; }

usage=""
if [ "$bb_known" = yes ]; then
	# git lists canonical paths (/private/tmp, not /tmp), so match BB's in that form.
	env_paths=$(jq -r '.[] | [.id, .path // ""] | @tsv' <<<"$envs" | while IFS=$'\t' read -r id path; do
		[ -n "$path" ] && printf '%s\t%s\t%s\n' "$id" "$(canonical "$path")" "$path"
	done)
	canon=$(jq -Rn '[inputs | select(. != "") | split("\t") | {(.[0]): .[1]}] | add // {}' <<<"$env_paths")
	# A thread can attach to any directory, so an environment inside a worktree
	# works in that worktree as much as one at its root.
	within='def within($p): . == $p or startswith($p + "/");'

	# A thread can work in a worktree by path from another environment, so scan
	# the logs of the projects that own this repo's environments, those attached
	# to a directory inside a worktree too. Never this thread, whose own output
	# names every path.
	projects=$(jq -r --arg main "$main_wt" --arg wts "$all_wts" --arg project "${BB_PROJECT_ID:-}" \
		--argjson canon "$canon" "$within"'
		(($wts | split("\n")) + [$main] | map(select(. != ""))) as $repo
		| [.[] | select(($canon[.id] // "") as $c | any($repo[]; . as $r | $c | within($r))) | .projectId]
		+ [$project] | map(select(. != "")) | unique | join(" ")' <<<"$envs")
	patterns=$(while read -r wt; do
		[ -z "$wt" ] && continue
		{ echo "$wt"; echo "${wt#/private}"; awk -F'\t' -v p="$wt" '$2 == p { print $3 }' <<<"$env_paths"; } | sed 's#//*#/#g' | sort -u |
			while read -r form; do printf '%s\t%s\n' "$wt" "$(printf '%s' "$form" | sed 's/[][\.*^$+?(){}|]/\\&/g')"; done
	done <<<"$wts")
	mentions=""
	for id in $(jq -r --arg ps "$projects" --arg self "${BB_THREAD_ID:-}" \
		'.[] | select(.projectId | IN($ps | split(" ")[])) | select(.id != $self) | .id' <<<"$live"); do
		log=$(bb thread log "$id" --format json --all 2>/dev/null) || { bb_fail "cannot read the log of $id"; break; }
		found=$(mentioned_worktrees <<<"$log") || { bb_fail "cannot scan the log of $id"; break; }
		mentions+=$(sed '/^$/d' <<<"$found" | while read -r wt; do printf '%s\t%s\n' "$wt" "$id"; done)$'\n'
	done
fi

if [ "$bb_known" = yes ]; then
	# One row per worktree path: its environments, at the path or inside it (so
	# a worktree nested in another counts for both), the newest activity of the
	# threads using it (BB's millisecond updatedAt, kept whole so a recheck
	# sees activity later the same day), how many of those have a pinned or
	# running thread in their ancestry, the environments outside this path
	# that archiving its threads would reach, and the threads whose logs name
	# it. BB's archive
	# walks children, lifecycle dependents and hidden forks, through archived
	# threads too, so the walk uses both lists. This thread is running only
	# because it runs the audit, so it holds the worktree it works in but not
	# the worktrees of its descendants.
	usage=$(jq -rn --arg wts "$wts" --arg mentions "$mentions" --arg self "${BB_THREAD_ID:-}" --argjson canon "$canon" \
		--argjson live "$live" --argjson archived "$archived" "$within"'
		def running: (.status | IN("pending", "starting", "active", "stopping"))
			or ((.queuedWork // "none") != "none")
			or (([(.activity // {})[]] | add // 0) > 0);
		($live + $archived) as $all
		| ($all | INDEX(.id)) as $by
		| (reduce $all[] as $t ({};
			reduce ([$t.parentThreadId, $t.lifecycleOwnerThreadId,
				(if $t.visibility == "hidden" then $t.sourceThreadId else null end)]
				| map(select(. != null)) | unique)[] as $p (.; .[$p] += [$t.id]))) as $kids
		| def lineage: limit(1000; recurse(($by[.parentThreadId // ""], $by[.lifecycleOwnerThreadId // ""]) // empty));
		def cascade: limit(100000; recurse($kids[.id][]? | $by[.] // empty));
		(reduce ($mentions | split("\n")[] | select(. != "") | split("\t")) as $m ({}; .[$m[0]] += [$m[1]])) as $named
		| $wts | split("\n")[] | select(. != "") as $wt
		| [$canon | to_entries[] | select(.value | within($wt)) | .key] as $envs
		| [$live[] | select(.environmentId | IN($envs[]))] as $roots
		| [$roots[] | cascade | select(.archivedAt == null and (.environmentId | IN($envs[]) | not))] as $outside
		| ($roots + [($named[$wt] // [])[] | $by[.] // empty] | unique_by(.id)) as $users
		| [$wt,
			(if $envs == [] then "-" else $envs | join(",") end),
			(($users | map(.updatedAt) | max) // 0),
			($users | map(select(any(lineage; .pinnedAt != null))) | length),
			($users | map(select(.id == $self or any(lineage; .id != $self and running))) | length),
			(if $outside == [] then "-" else [$outside[] | .environmentId // .id] | unique | join(",") end),
			(($named[$wt] // []) | if . == [] then "-" else join(",") end)]
		| @tsv') || bb_fail "could not join BB state to worktrees"
fi
now=$(date +%s)

printf "SIZE\tAGE\tMERGED\tDIRTY\tSNAPSHOT\tREMOTE\tPR\tENV\tLAST_THREAD\tCASCADE\tMENTIONS\tBUCKET\tWORKTREE\n"

while read -r wt; do
	[ -z "$wt" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of main, so PR state is the
	# real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" origin/main 2>/dev/null && merged=YES || merged=no

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")

	# Everything removal would lose: tracked edits, untracked files that git
	# does not ignore (new source until someone says otherwise), a detached
	# HEAD that no branch, tag or remote ref contains, and a submodule commit
	# that no remote-tracking ref of that submodule contains. A submodule's
	# edits count as its gitlink's, whatever `ignore` the repo sets for it.
	if porcelain=$(git -C "$wt" status --porcelain --ignore-submodules=none 2>/dev/null) \
		&& sub_ahead=$(submodule_unpushed "$wt" 2>/dev/null); then
		tracked=$(printf '%s' "$porcelain" | grep -cv '^??')
		untracked=$(printf '%s' "$porcelain" | grep -c '^??')
		dirty=""
		[ "$tracked" -gt 0 ] && dirty="wip:$tracked"
		[ "$untracked" -gt 0 ] && dirty="${dirty:+$dirty+}untracked:$untracked"
		{ [ -z "$branch" ] && [ -z "$(git -C "$wt" for-each-ref --contains "$head" --count=1 refs/heads refs/tags refs/remotes 2>/dev/null)" ]; } \
			|| [ -n "$sub_ahead" ] && dirty="${dirty:+$dirty+}unreachable"
		dirty="${dirty:-clean}"
	else dirty="?"; fi
	snap=-
	[ "$dirty" = "?" ] && snap="?"
	[ "$dirty" != clean ] && [ "$dirty" != "?" ] && { snap=$(snapshot "$wt" 2>/dev/null) || snap="?"; }

	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		[ "$(git -C "$wt" rev-parse "origin/$branch" 2>/dev/null)" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
	else remote=no-remote; fi

	pr=$([ -n "$branch" ] && jq -r --arg b "$branch" \
		'.[] | select(.headRefName==$b) | "#\(.number)/\(.state)"' <<<"$prs" 2>/dev/null | head -1)
	[ -z "$pr" ] && pr="-"

	env="?"; last="?"; cascade="?"; named="?"; last_ms=0; pinned=0; running=0
	if [ "$bb_known" = yes ]; then
		IFS=$'\t' read -r _ env last_ms pinned running cascade named \
			< <(awk -F'\t' -v p="$wt" '$1 == p' <<<"$usage")
		last="-"
		[ "${last_ms:-0}" -gt 0 ] && last=$(jq -rn --argjson ms "$last_ms" \
			'($ms / 1000 | floor | todate | sub("Z$"; "")) + "." + ("00" + ($ms % 1000 | tostring))[-3:] + "Z"')
		[ "${pinned:-0}" -gt 0 ] && last="$last,pinned"
		[ "${running:-0}" -gt 0 ] && last="$last,running"
	fi
	recent=$([ "${last_ms:-0}" -gt 0 ] && [ $(( (now - last_ms / 1000) / 86400 )) -le 4 ] && echo yes || echo no)

	# First match wins, so every hold outranks every go, and the holds a user
	# cannot release outrank the ones they can.
	if [ "$bb_known" != yes ] || [ "$dirty" = "?" ] || [ "$snap" = "?" ]; then bucket=hold-unknown
	elif [ "${pinned:-0}" -gt 0 ] || [ "${running:-0}" -gt 0 ]; then bucket=hold-in-use
	elif [ "$cascade" != "-" ]; then bucket=hold-cascade
	elif [ "$dirty" != clean ]; then bucket=hold-wip
	elif [[ "$pr" == *OPEN* ]]; then bucket=hold-open-pr
	elif [ "$recent" = yes ]; then bucket=verify-recent-chat
	elif [ "$merged" = YES ] || [ "$pr" != "-" ]; then bucket=safe
	else bucket=review; fi

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$snap" "$remote" "$pr" "$env" "$last" "$cascade" "$named" "$bucket" "$wt"
done <<<"$wts" | sort -t$'\t' -k1,1 -rh
