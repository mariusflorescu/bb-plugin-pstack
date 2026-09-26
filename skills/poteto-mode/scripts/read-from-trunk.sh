#!/usr/bin/env bash
# Print a file from the trunk of the pstack plugin's source repo. A thread holds
# the skill copy BB loaded when it started, and path or pinned installs never
# follow trunk, so a long program re-reads its policy here. The trunk revision
# goes to stderr for the decision trail. Exits non-zero with the reason when
# the source has no readable trunk.
#
# BB installs plugins on its server, and a thread may run on another machine. A
# source at a local path that this machine does not have falls back to the
# plugin's published repository, named in trunk-url next to this script.
#
# Usage: read-from-trunk.sh <path in the pstack repo>
#   read-from-trunk.sh skills/poteto-mode/playbooks/autopilot-full.md
set -eu
file="${1:?usage: read-from-trunk.sh <path in the pstack repo>}"
die() { echo "read-from-trunk: $*" >&2; exit 1; }
# The published repository holds the plugin at its root, so no prefix applies.
published() {
	url=$(head -n 1 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/trunk-url") && [ -n "$url" ] \
		|| die "$1 is not on this machine and trunk-url names no published repository"
	sub=
	echo "read-from-trunk: $1 is not on this machine; reading the published repository" >&2
}

source_json=$(bb plugin source pstack --json) || die "bb plugin source pstack failed"
# `requested` is the install source; `resolved` is display text (`<url>@<ref> (<commit>)` for git).
requested=$(jq -r '.requested // empty' <<<"$source_json")

# The source forms of BB's parsePluginSource: builtin:, npm:, git:<url>[@<spec>],
# http(s)://<url>[@<spec>], and path:<dir> or a bare path.
case "$requested" in
"" | builtin:* | npm:*) die "source '$requested' has no git trunk" ;;
git:* | http://* | https://*)
	spec="${requested#git:}"
	# BB splits the ref at the last @, so a ref may hold / (feature/x, ref:release/v2).
	url="${spec%@*}"
	[ -n "$url" ] || url="$spec"
	case "$url" in http://* | https://* | /*) ;; [A-Za-z0-9]*) url="https://$url" ;; *) die "source '$requested' has no git url" ;; esac
	sub=$(jq -r '.subdirectory // empty' <<<"$source_json")
	case "$url" in /*) [ -e "$url" ] || published "git source $url" ;; esac
	;;
*)
	# A path install stores the plugin's own directory, which may sit below the repository root.
	dir="${requested#path:}"
	if [ ! -d "$dir" ]; then
		published "path source $dir"
	else
		url=$(git -C "$dir" remote get-url origin 2>/dev/null) || die "path source $dir has no origin remote, so it has no trunk"
		top=$(git -C "$dir" rev-parse --show-toplevel)
		sub=$(git -C "$dir" rev-parse --show-prefix)
		# git resolves a relative local origin from the repository root, and the fetch below runs in the cache.
		case "$url" in /*) ;; *) case "${url%%:*}" in "$url" | */*) url="$top/$url" ;; esac ;; esac
	fi
	;;
esac

cache="${BB_THREAD_STORAGE:-${TMPDIR:-/tmp}}/pstack-trunk.git"
[ -d "$cache" ] || git init -q --bare "$cache"
git -C "$cache" fetch -q --depth 1 "$url" HEAD || die "cannot fetch trunk from $url"
rev=$(git -C "$cache" rev-parse FETCH_HEAD)
echo "pstack trunk $url@$rev" >&2
git -C "$cache" show "FETCH_HEAD:${sub:+${sub%/}/}$file" || die "$file is not on trunk at $url@$rev"
