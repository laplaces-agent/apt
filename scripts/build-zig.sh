#!/usr/bin/env bash
. "$(dirname "$(readlink -f "$0")")/common.sh"
. "$ROOT/packages/zig/package.env"

assert_build_suite

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y -o APT::Immediate-Configure=false --no-install-recommends \
	ca-certificates curl xz-utils dpkg-dev

tarball=zig-x86_64-linux-$UPSTREAM_VERSION
fetch "https://ziglang.org/download/$UPSTREAM_VERSION/$tarball.tar.xz" \
	"$WORK/zig.tar.xz" "$UPSTREAM_SHA256"

# Upstream ships a static toolchain, so this repackages rather than compiles.
# The tree lives under a versioned directory so that several toolchains can be
# installed side by side.
tree=$WORK/pkg
prefix=usr/lib/zig/$UPSTREAM_VERSION
mkdir -p "$tree/$prefix" "$tree/usr/bin" "$tree/DEBIAN" \
	"$tree/usr/share/doc/zig"
tar -xf "$WORK/zig.tar.xz" --strip-components=1 -C "$tree/$prefix"
ln -s "../lib/zig/$UPSTREAM_VERSION/zig" "$tree/usr/bin/zig"

cp "$tree/$prefix/LICENSE" "$tree/usr/share/doc/zig/copyright" 2>/dev/null || true

version=$UPSTREAM_VERSION-$DEBIAN_REVISION~$DISTRIBUTION
installed_size=$(du -sk "$tree/usr" | cut -f1)

# zig-stable and zig-0 come from other third-party repositories and own the
# same /usr/lib/zig paths, so this has to displace them rather than coexist.
cat > "$tree/DEBIAN/control" <<EOF
Package: zig
Version: $version
Section: devel
Priority: optional
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Installed-Size: $installed_size
Provides: zig-stable
Conflicts: zig-stable, zig-0
Replaces: zig-stable, zig-0
Homepage: https://ziglang.org/
Description: General-purpose programming language and toolchain
 Zig is a general-purpose programming language and toolchain for maintaining
 robust, optimal and reusable software. The toolchain also works as a drop-in
 C and C++ compiler.
 .
 This is an unofficial package built from the official upstream release
 tarball; nothing is recompiled.
EOF

dpkg-deb --root-owner-group -Zxz --build "$tree" \
	"$OUT/zig_${version}_${ARCHITECTURE}.deb"
ls -la "$OUT"
