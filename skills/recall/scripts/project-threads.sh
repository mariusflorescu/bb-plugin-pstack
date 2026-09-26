#!/usr/bin/env bash
# List this project's threads updated in the last <days> days, hidden and
# archived ones included, newest first, skipping the current thread. With a
# topic, keep only threads whose raw log mentions it (case-insensitive) and
# count the matching events.
# Usage: project-threads.sh <days> [topic]
# Output (TSV): updated	thread	parent	hits	title
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
	printf 'usage: project-threads.sh <days> [topic]\n' >&2
	exit 1
fi

days="$1"
topic="${2:-}"
: "${BB_PROJECT_ID:?BB_PROJECT_ID is not set}"

since_ms=$(( ($(date +%s) - days * 86400) * 1000 ))

printf 'updated\tthread\tparent\thits\ttitle\n'
bb thread list --project "$BB_PROJECT_ID" --include-hidden --json |
	jq -r --argjson since "$since_ms" --arg self "${BB_THREAD_ID:-}" '
		map(select(.updatedAt >= $since and .id != $self))
		| sort_by(-.updatedAt)[]
		| [(.updatedAt / 1000 | floor | todate), .id, (.parentThreadId // "-"), ((.title // "-") | gsub("[\t\r\n]"; " "))]
		| @tsv' |
	while IFS=$'\t' read -r updated id parent title; do
		hits="-"
		if [ -n "$topic" ]; then
			if ! log="$(bb thread log "$id" --format json --all </dev/null)"; then
				printf 'project-threads: log of %s did not load, skipped\n' "$id" >&2
				continue
			fi
			# Streamed deltas repeat text that the completed item already holds.
			hits="$(jq --arg t "$topic" '
				($t | ascii_downcase) as $needle
				| [.[] | select(.type | test("[Dd]elta$") | not) | select(tostring | ascii_downcase | contains($needle))]
				| length' <<<"$log")"
			[ "$hits" -eq 0 ] && continue
		fi
		printf '%s\t%s\t%s\t%s\t%s\n' "$updated" "$id" "$parent" "$hits" "$title"
	done
