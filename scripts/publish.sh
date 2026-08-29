#!/usr/bin/env bash
# Rebuild the apt index in a site directory from the .deb files in an incoming
# directory. Does not touch git; the workflow handles the branch and the push.
#
#   publish.sh <incoming-dir> <site-dir>
#
# Requires GPG_KEY_ID to be set to an already-imported secret key.
. "$(dirname "$(readlink -f "$0")")/common.sh"

INCOMING=${1:?usage: publish.sh <incoming-dir> <site-dir>}
SITE=${2:?usage: publish.sh <incoming-dir> <site-dir>}
: "${GPG_KEY_ID:?GPG_KEY_ID is not set}"

# Resolved before the cd below, so both may be given relative to the caller.
mkdir -p "$SITE"
INCOMING=$(cd "$INCOMING" && pwd)
SITE=$(cd "$SITE" && pwd)

pool=pool/$COMPONENT
binary=dists/$DISTRIBUTION/$COMPONENT/binary-$ARCHITECTURE
mkdir -p "$SITE/$pool" "$SITE/$binary"

# GitHub Pages runs Jekyll by default, which drops files and directories whose
# names begin with an underscore or a dot.
touch "$SITE/.nojekyll"

# Written on every publish rather than left to the Pages settings UI, so the
# custom domain survives the branch being recreated from scratch.
printf '%s\n' "$PAGES_DOMAIN" > "$SITE/CNAME"

shopt -s nullglob
debs=("$INCOMING"/*.deb)
if [ ${#debs[@]} -eq 0 ]; then
	echo "no .deb files in $INCOMING" >&2
	exit 1
fi

for deb in "${debs[@]}"; do
	name=$(dpkg-deb -f "$deb" Package)
	arch=$(dpkg-deb -f "$deb" Architecture)
	version=$(dpkg-deb -f "$deb" Version)
	# One version per package. Without this the pool grows without bound and
	# every client downloads a larger index.
	rm -f "$SITE/$pool/${name}_"*"_${arch}.deb"
	cp "$deb" "$SITE/$pool/"
	echo "pooled $name $version ($arch)"
done

cd "$SITE"

apt-ftparchive --arch "$ARCHITECTURE" packages "$pool" > "$binary/Packages"
gzip -9cn "$binary/Packages" > "$binary/Packages.gz"

# apt-ftparchive hashes every file it finds under dists/, so last run's
# signatures have to go before this run's Release is generated.
rm -f "dists/$DISTRIBUTION/Release" \
	"dists/$DISTRIBUTION/Release.gpg" \
	"dists/$DISTRIBUTION/InRelease"

apt-ftparchive \
	-o "APT::FTPArchive::Release::Origin=$ORIGIN" \
	-o "APT::FTPArchive::Release::Label=$LABEL" \
	-o "APT::FTPArchive::Release::Suite=$DISTRIBUTION" \
	-o "APT::FTPArchive::Release::Codename=$DISTRIBUTION" \
	-o "APT::FTPArchive::Release::Architectures=$ARCHITECTURE" \
	-o "APT::FTPArchive::Release::Components=$COMPONENT" \
	release "dists/$DISTRIBUTION" > "dists/$DISTRIBUTION/Release"

gpg --batch --yes --local-user "$GPG_KEY_ID" \
	--clearsign -o "dists/$DISTRIBUTION/InRelease" "dists/$DISTRIBUTION/Release"
gpg --batch --yes --local-user "$GPG_KEY_ID" \
	-abs -o "dists/$DISTRIBUTION/Release.gpg" "dists/$DISTRIBUTION/Release"

# Both armoured and binary: apt reads either, but only the binary form can be
# dropped straight into /etc/apt/keyrings without dearmouring.
gpg --batch --yes --armor --export "$GPG_KEY_ID" > key.asc
gpg --batch --yes --export "$GPG_KEY_ID" > key.gpg

"$ROOT/scripts/make-index-page.sh" "$SITE"

echo
echo "--- dists/$DISTRIBUTION/Release"
cat "dists/$DISTRIBUTION/Release"
