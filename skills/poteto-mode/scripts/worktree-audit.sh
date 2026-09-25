#!/usr/bin/env bash
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, uncommitted work, remote/PR state, and the BB environment and threads
# on it (newest activity, pinned, running). Emits a table sorted by size with a
# suggested bucket. Never deletes anything; deletion stays a human-gated step
# in the playbook.
#
# Usage: worktree-audit.sh [repo-path]   (defaults to the current repo)
set -u

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a git repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1

# Main worktree is the first entry; everything else is a candidate.
main_wt=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

# origin/main drives the merge check. Best-effort; stale is fine for a first pass.
git fetch origin main --quiet 2>/dev/null || echo "warn: could not fetch origin/main; merged column may be stale" >&2

# PR state by branch, fetched once. Empty if gh is unavailable. Kept in
# variables because bare macOS mktemp writes outside $TMPDIR, which an agent
# sandbox denies.
prs=$(gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName 2>/dev/null) || prs="[]"

# One row per BB environment, fetched once: path, env id, newest activity of its
# unarchived threads, and how many are pinned or running. A thread counts as
# pinned or running when any ancestor is, since a pinned coordinator's children
# work in sibling worktrees the user never pinned.
bbenvs=$(
	envs=$(bb environment list --json 2>/dev/null) \
		&& threads=$(bb thread list --include-hidden --json 2>/dev/null) \
		&& printf '%s\n%s\n' "$envs" "$threads" | jq -rs '
			def lineage($by): ., ($by[.parentThreadId // ""] // empty | lineage($by));
			def running: .status | IN("pending", "starting", "active", "stopping");
			.[1] as $threads | INDEX($threads[]; .id) as $by
			| .[0][] | .id as $id
			| [$threads[] | select(.environmentId == $id)] as $t
			| [.path, $id, ((($t | map(.updatedAt) | max) // 0) / 1000 | floor),
			   ($t | map(select(any(lineage($by); .pinnedAt != null))) | length),
			   ($t | map(select(any(lineage($by); running))) | length)]
			| @tsv'
) || echo "warn: bb unavailable; ENV and LAST_THREAD are blank and nothing is held as in use" >&2
# git lists canonical paths (/private/tmp, not /tmp), so match BB's in that form.
bbenvs=$(printf '%s\n' "$bbenvs" | while IFS=$'\t' read -r path rest; do
	[ -n "$path" ] && printf '%s\t%s\n' "$(cd "$path" 2>/dev/null && pwd -P || echo "$path")" "$rest"
done)
now=$(date +%s)

printf "SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tENV\tLAST_THREAD\tBUCKET\tWORKTREE\n"

git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
	[ "$wt" = "$main_wt" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of main, so PR state is the
	# real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" origin/main 2>/dev/null && merged=YES || merged=no

	# Distinguish real WIP (tracked edits) from disposable untracked scratch.
	porcelain=$(git -C "$wt" status --porcelain 2>/dev/null)
	if [ -z "$porcelain" ]; then dirty=clean
	elif printf '%s\n' "$porcelain" | grep -qv '^??'; then
		dirty="wip:$(printf '%s\n' "$porcelain" | grep -cv '^??')"
	else dirty="scratch:$(printf '%s\n' "$porcelain" | grep -c '^??')"; fi

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		[ "$(git -C "$wt" rev-parse "origin/$branch" 2>/dev/null)" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
	else remote=no-remote; fi

	pr=$([ -n "$branch" ] && jq -r --arg b "$branch" \
		'.[] | select(.headRefName==$b) | "#\(.number)/\(.state)"' <<<"$prs" 2>/dev/null | head -1)
	[ -z "$pr" ] && pr="-"

	IFS=$'\t' read -r _ env last_ts pinned running \
		< <(awk -F'\t' -v p="$wt" '$1 == p' <<<"$bbenvs")
	env="${env:--}"
	last="-"
	[ "${last_ts:-0}" -gt 0 ] && last=$(date -r "$last_ts" '+%Y-%m-%d' 2>/dev/null)
	[ "${pinned:-0}" -gt 0 ] && last="$last,pinned"
	[ "${running:-0}" -gt 0 ] && last="$last,running"
	recent=$([ "${last_ts:-0}" -gt 0 ] && [ $(( (now - last_ts) / 86400 )) -le 4 ] && echo yes || echo no)

	case "$dirty" in wip:*) bucket=hold-wip ;; *)
		if [ "${pinned:-0}" -gt 0 ] || [ "${running:-0}" -gt 0 ]; then bucket=hold-in-use; else
		case "$pr" in *OPEN*) bucket=hold-open-pr ;; *)
			if [ "$recent" = yes ]; then bucket=verify-recent-chat
			elif [ "$merged" = YES ] || [ "$pr" != "-" ]; then bucket=safe
			else bucket=review; fi ;;
		esac; fi ;;
	esac

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$remote" "$pr" "$env" "$last" "$bucket" "$wt"
done | sort -t$'\t' -k1,1 -rh
