#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/common.sh"
. "$ROOT/packages/ghostty/package.env"

assert_build_suite

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update
# APT::Immediate-Configure=false works around a dependency-ordering bug in
# sid's tpm2-tss/systemd stack that otherwise fails to configure.
apt-get install -y -o APT::Immediate-Configure=false --no-install-recommends \
	ca-certificates curl xz-utils \
	build-essential debhelper devscripts fakeroot pandoc \
	libadwaita-1-dev libbz2-dev libfontconfig-dev libgtk-4-dev \
	libgtk4-layer-shell-dev libonig-dev libxml2-utils pkgconf

# Ghostty builds against exactly one Zig release, so take it from ziglang.org
# rather than from whatever Debian happens to carry.
zig_dir=zig-x86_64-linux-$ZIG_VERSION
fetch "https://ziglang.org/download/$ZIG_VERSION/$zig_dir.tar.xz" \
	"$WORK/zig.tar.xz" "$ZIG_SHA256"
tar -xf "$WORK/zig.tar.xz" -C "$WORK"
export PATH="$WORK/$zig_dir:$PATH"
zig version

src=ghostty-$UPSTREAM_VERSION
fetch "https://release.files.ghostty.org/$UPSTREAM_VERSION/$src.tar.gz" \
	"$WORK/$src.tar.gz" "$UPSTREAM_SHA256"
tar -xf "$WORK/$src.tar.gz" -C "$WORK"

# The release tarball pins the Zig it wants; if it disagrees with the recipe the
# build would either fail obscurely or silently use the wrong compiler.
want=$(sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' "$WORK/$src/build.zig.zon")
if [ -n "$want" ] && [ "$want" != "$ZIG_VERSION" ]; then
	echo "ghostty $UPSTREAM_VERSION wants zig $want, recipe pins $ZIG_VERSION" >&2
	exit 1
fi

cp -r "$ROOT/packages/ghostty/debian" "$WORK/$src/debian"
chmod +x "$WORK/$src/debian/rules"

version=$UPSTREAM_VERSION-$DEBIAN_REVISION~$DISTRIBUTION
cd "$WORK/$src"
dch --create --package ghostty --newversion "$version" \
	--distribution "$DISTRIBUTION" \
	"Unofficial build of ghostty $UPSTREAM_VERSION."
dpkg-buildpackage --build=binary --no-sign

cp "$WORK"/*.deb "$OUT/"
ls -la "$OUT"
