# apt

Debian packages for software Debian does not carry, built on GitHub Actions and
served as a signed apt repository from GitHub Pages.

```
packages/<name>/package.env      pinned version + sha256
        |
        v
.github/workflows/<name>.yml     build in a debian:sid container
        |
        v
.github/workflows/publish.yml    apt-ftparchive + gpg --clearsign
        |
        v
gh-pages branch
```

## Install

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.xeyes.org/key.gpg \
  | sudo tee /etc/apt/keyrings/apt.xeyes.org.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/apt.xeyes.org.gpg] https://apt.xeyes.org sid main" \
  | sudo tee /etc/apt/sources.list.d/apt.xeyes.org.list
sudo apt update
```

## Packages

| Package | Source | Built how |
|---------|--------|-----------|
| `ghostty` | `release.files.ghostty.org` source tarball | compiled with a pinned Zig, `dpkg-buildpackage` |
| `zig` | `ziglang.org` official static tarball | repackaged, nothing compiled |

## Recipes

`packages/<name>/package.env` is the whole recipe: an upstream version, a
sha256 for every tarball fetched, and a Debian revision. Nothing floats — a
build is reproducible from the recipe alone, and every download is checked
against its recorded hash before use.

The two Zig versions in the tree are unrelated:

- `packages/zig/package.env` — the Zig that gets **published**, tracking latest stable.
- `packages/ghostty/package.env` `ZIG_VERSION` — the Zig ghostty is **built with**.

Ghostty compiles against exactly one Zig release. `build-ghostty.sh` reads
`minimum_zig_version` from the release tarball and refuses to build if it
disagrees with the recipe, so a silent compiler mismatch is not possible.

Versions are `<upstream>-<revision>~<suite>`. Bump `DEBIAN_REVISION` when the
packaging changes but upstream has not; an upstream bump resets it to 1.

## Automation

`check-upstream.yml` runs daily. It compares each recipe against upstream,
rewrites `package.env` where something is newer — recomputing the sha256, and
for ghostty also the required Zig — and opens a pull request. Merging it
triggers the build.

It is a pull request rather than a direct commit because an upstream bump can
need packaging changes too, and a failed build should not be the first sign.

## Building locally

Everything runs in the same container the workflow uses:

```bash
docker run --rm -v "$PWD:/w" -w /w debian:sid ./scripts/build-zig.sh
docker run --rm -v "$PWD:/w" -w /w debian:sid ./scripts/build-ghostty.sh
```

Artifacts land in `build/`. `publish.sh` takes an incoming directory and a site
directory, and needs `GPG_KEY_ID` set to an imported secret key.

## Adding a package

1. `packages/<name>/package.env` with `UPSTREAM_VERSION`, `UPSTREAM_SHA256`,
   `DEBIAN_REVISION`.
2. A `debian/` directory if it needs `dpkg-buildpackage`; nothing if the
   upstream artifact can be repackaged like `zig`.
3. `scripts/build-<name>.sh`, modelled on the closer of the two.
4. `.github/workflows/<name>.yml`, copied from `zig.yml`. Trigger on
   `packages/<name>/**` and its own build script — not on the workflow file
   itself, so editing how a job runs does not rebuild the artifact.
5. Teach `scripts/check-upstream.sh` how to find its latest version.

## Notes

- **The build container must match `DISTRIBUTION` in `config.env`.**
  `shlibs:Depends` is generated against whatever the build ran in.
  `assert_build_suite` fails the build rather than trusting the two to agree.
- **Do not build on a newer suite than you install on**, or the generated
  dependency floors will be unsatisfiable.
- **`apt-ftparchive release` hashes everything under `dists/`**, including a
  previous run's `Release`. `publish.sh` removes the old signatures first;
  otherwise the file signs a digest of itself.
- **GitHub Pages runs Jekyll**, which drops paths beginning with `_` or `.`.
  The `.nojekyll` marker keeps the pool intact.
- **`publish.sh` writes the `CNAME` file on every publish**, so the custom
  domain survives the branch being recreated.
- **The pool keeps one version per package.** A new build deletes the old
  `.deb`; there is no rollback target in the repository.
