#!/usr/bin/env bash
# Print the event sequence this BB thread's current run starts after: the seq
# of the thread's latest context clear, or 0 when it was never cleared. A clear
# (`bb thread clear`, or the provider resetting its conversation) keeps the
# thread and its event history but starts a fresh conversation, so it starts a
# new run in the same thread. A compaction summarizes the run and does not.
# `bb thread log <id> --format json --all --after-seq <seq>` reads the run.
# Usage: run-start.sh
set -euo pipefail
: "${BB_THREAD_ID:?BB_THREAD_ID is not set}"

bb thread log --self --format json --all | jq '
	[.[] | select(.type == "thread/context/cleared"
		or (.type == "system/operation" and .data.operation == "context_clear" and .data.status == "completed"))
	| .seq] | max // 0'
