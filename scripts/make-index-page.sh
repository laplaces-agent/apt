#!/usr/bin/env bash
# Writes the landing page for the Pages site, listing whatever is in the pool.
. "$(dirname "$(readlink -f "$0")")/common.sh"

SITE=${1:?usage: make-index-page.sh <site-dir>}

rows=""
while read -r name version; do
	[ -n "$name" ] || continue
	rows+="<tr><td><code>${name}</code></td><td>${version}</td></tr>"
done < <(awk '/^Package: /{p=$2} /^Version: /{print p, $2}' \
	"$SITE/dists/$DISTRIBUTION/$COMPONENT/binary-$ARCHITECTURE/Packages")

cat > "$SITE/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$LABEL</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 15px/1.6 system-ui, -apple-system, sans-serif; max-width: 46rem;
         margin: 3rem auto; padding: 0 1.2rem; }
  pre  { background: rgba(127,127,127,.12); padding: .9rem 1rem;
         border-radius: 6px; overflow-x: auto; }
  code { font-size: .92em; }
  table { border-collapse: collapse; margin: 1rem 0; }
  td, th { text-align: left; padding: .3rem 1.4rem .3rem 0; }
  th { border-bottom: 1px solid rgba(127,127,127,.4); }
  footer { margin-top: 2.5rem; font-size: .9em; opacity: .75; }
</style>
</head>
<body>
<h1>$LABEL</h1>
<p>Unofficial Debian packages, rebuilt automatically on each upstream release.
Suite <code>$DISTRIBUTION</code>, component <code>$COMPONENT</code>,
architecture <code>$ARCHITECTURE</code>.</p>

<h2>Install</h2>
<pre><code>sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL $PAGES_URL/key.gpg \\
  | sudo tee /etc/apt/keyrings/$KEYRING_NAME.gpg &gt; /dev/null
echo "deb [arch=$ARCHITECTURE signed-by=/etc/apt/keyrings/$KEYRING_NAME.gpg] $PAGES_URL $DISTRIBUTION $COMPONENT" \\
  | sudo tee /etc/apt/sources.list.d/$KEYRING_NAME.list
sudo apt update</code></pre>

<h2>Packages</h2>
<table><tr><th>Package</th><th>Version</th></tr>$rows</table>

<footer>Built and published by
<a href="https://github.com/laplaces-agent/apt">laplaces-agent/apt</a>.</footer>
</body>
</html>
EOF
echo "wrote index.html"
