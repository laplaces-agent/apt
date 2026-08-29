# Sourced by the build scripts. Not executable on its own.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/config.env"

OUT=${OUT:-$ROOT/build}
mkdir -p "$OUT"

DEBFULLNAME=${MAINTAINER%% <*}
DEBEMAIL=${MAINTAINER##*<}
DEBEMAIL=${DEBEMAIL%>}
export DEBFULLNAME DEBEMAIL

# The version suffix and the shlibs:Depends both come from the running
# container, so a mismatch with DISTRIBUTION would silently produce packages
# labelled for a suite they were not built against.
assert_build_suite() {
	if ! grep -qi "$DISTRIBUTION" /etc/os-release; then
		echo "config.env says DISTRIBUTION=$DISTRIBUTION but this container is:" >&2
		grep PRETTY_NAME /etc/os-release >&2
		exit 1
	fi
}

fetch() {
	local url=$1 dest=$2 sha=$3
	curl -fsSL --retry 3 -o "$dest" "$url"
	echo "$sha  $dest" | sha256sum -c - >/dev/null
	echo "verified $(basename "$dest")"
}
