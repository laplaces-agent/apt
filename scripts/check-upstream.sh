#!/usr/bin/env bash
# Compares each recipe's pinned version against upstream and rewrites
# package.env in place where a newer release exists. Makes no git commits;
# .github/workflows/check-upstream.yml turns the result into a pull request.
. "$(dirname "$(readlink -f "$0")")/common.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ZIG_INDEX=$WORK/zig-index.json
curl -fsSL --retry 3 -o "$ZIG_INDEX" https://ziglang.org/download/index.json

getval() { sed -n "s/^$2=//p" "$1" | tail -1; }

setval() {
	grep -q "^$2=" "$1" || { echo "$1 has no key $2" >&2; exit 1; }
	sed -i "s|^$2=.*|$2=$3|" "$1"
}

zig_shasum() {
	jq -er --arg v "$1" '.[$v]["x86_64-linux"].shasum' "$ZIG_INDEX"
}

changed=()
body=$ROOT/bump-body.md
: > "$body"

# --- ghostty -----------------------------------------------------------------
# Ghostty does not publish GitHub releases for stable versions, so the tags are
# the only machine-readable list.
gh_env=$ROOT/packages/ghostty/package.env
gh_cur=$(getval "$gh_env" UPSTREAM_VERSION)
gh_new=$(git ls-remote --tags --refs https://github.com/ghostty-org/ghostty 'v*' \
	| sed 's#.*refs/tags/v##' \
	| grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

if [ -z "$gh_new" ]; then
	echo "could not determine the latest ghostty tag" >&2
	exit 1
fi

if dpkg --compare-versions "$gh_new" gt "$gh_cur"; then
	echo "ghostty: $gh_cur -> $gh_new"
	tgz=$WORK/ghostty-$gh_new.tar.gz
	curl -fsSL --retry 3 -o "$tgz" \
		"https://release.files.ghostty.org/$gh_new/ghostty-$gh_new.tar.gz"
	gh_sha=$(sha256sum "$tgz" | cut -d' ' -f1)

	# The Zig ghostty needs is a property of the release, not of the calendar,
	# so read it out of the tarball rather than tracking Zig's latest.
	zig_new=$(tar -xzOf "$tgz" "ghostty-$gh_new/build.zig.zon" \
		| sed -n 's/.*minimum_zig_version = "\([^"]*\)".*/\1/p')
	if [ -z "$zig_new" ]; then
		echo "no minimum_zig_version in ghostty $gh_new build.zig.zon" >&2
		exit 1
	fi
	# A development Zig has no release tarball to pin, and guessing one would
	# produce a recipe that only fails once the build runs.
	if ! zig_sha=$(zig_shasum "$zig_new"); then
		echo "ghostty $gh_new wants zig $zig_new, which ziglang.org does not publish" >&2
		exit 1
	fi

	setval "$gh_env" UPSTREAM_VERSION "$gh_new"
	setval "$gh_env" UPSTREAM_SHA256 "$gh_sha"
	setval "$gh_env" ZIG_VERSION "$zig_new"
	setval "$gh_env" ZIG_SHA256 "$zig_sha"
	setval "$gh_env" DEBIAN_REVISION 1
	changed+=("ghostty $gh_new")
	{
		echo "### ghostty $gh_cur → $gh_new"
		echo
		echo "- builds with zig \`$zig_new\`"
		echo "- <https://ghostty.org/docs/install/release-notes/${gh_new//./-}>"
		echo
	} >> "$body"
fi

# --- zig ---------------------------------------------------------------------
# Independent of the Zig that ghostty builds with.
zig_env=$ROOT/packages/zig/package.env
zig_cur=$(getval "$zig_env" UPSTREAM_VERSION)
zig_latest=$(jq -r 'keys_unsorted[]' "$ZIG_INDEX" \
	| grep -Ex '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)

if [ -n "$zig_latest" ] && dpkg --compare-versions "$zig_latest" gt "$zig_cur"; then
	echo "zig: $zig_cur -> $zig_latest"
	sha=$(zig_shasum "$zig_latest")
	setval "$zig_env" UPSTREAM_VERSION "$zig_latest"
	setval "$zig_env" UPSTREAM_SHA256 "$sha"
	setval "$zig_env" DEBIAN_REVISION 1
	changed+=("zig $zig_latest")
	{
		echo "### zig $zig_cur → $zig_latest"
		echo
		echo "- <https://ziglang.org/download/$zig_latest/release-notes.html>"
		echo
	} >> "$body"
fi

# -----------------------------------------------------------------------------
if [ ${#changed[@]} -eq 0 ]; then
	echo "everything is current"
	rm -f "$body"
else
	printf 'bumped: %s\n' "${changed[*]}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		printf 'changed=%s\n' "${changed[*]-}"
		printf 'title=Bump %s\n' "${changed[*]-}"
	} >> "$GITHUB_OUTPUT"
fi
