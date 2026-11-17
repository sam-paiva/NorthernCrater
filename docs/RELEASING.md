# Making a release

There are three ways, from least to most work. All of them run the same script, `scripts/make_release.sh`, so the
files are always built the same way: an **arm64 Release**, signed locally (ad-hoc), packed as a `.dmg`, a `.zip`
and a `.sha256` file.

## 1. Automatic: push a tag (recommended)

A GitHub Action (`.github/workflows/release.yml`) builds and publishes the release for you, on a GitHub-hosted
Apple Silicon Mac. You do not need to build anything yourself.

```sh
git tag v1.0
git push origin v1.0
```

Open the repository's **Actions** tab to watch it. A few minutes later the release **v1.0** appears under
**Releases** with the three files, the release notes and the checksums. The release is published by
`github-actions[bot]`.

- The tag decides the version: `v1.0.1` gives `NorthernCrater-1.0.1-arm64.dmg`, and the app reports version 1.0.1.
- To **test the pipeline without publishing**, open Actions, choose **Release**, then **Run workflow**. It builds and
  checks everything but creates no release.
- The release notes come from `.github/release-notes.md` (`{{VERSION}}` is filled in). Edit that file to change them.
- Public repositories can use GitHub's hosted runners for free as far as I know; check GitHub's current pricing if
  the repository is private, because macOS minutes cost more.

## 2. One command from your Mac

Install the GitHub CLI once (`brew install gh`, then `gh auth login`), push your commits, and run:

```sh
scripts/make_release.sh 1.0 --publish
```

It builds, packs and creates the release `v1.0` with the files and notes. Add `DRY_RUN=1` in front to see what it
would do without publishing.

## 3. By hand

```sh
scripts/make_release.sh 1.0
```

The files are written to `dist/`. On GitHub, open **Releases**, **Draft a new release**, create the tag (`v1.0`),
drag the three files from `dist/` into the box that says "Attach binaries by dropping them here", paste the notes
from `.github/release-notes.md` and press **Publish release**.

## Before any release

- Make sure your commits are pushed and the README is correct.
- Never attach a built engine (`NorthernCrater Engine.app`, anything from `~/Library/Caches/NorthernCrater`) or any
  game file. They contain code derived from the game. The release files above never include them.
- To bump the app's own version, the tag is enough: the script builds with the version you give it.

## After a release

- Download the DMG from the release page, check it with `shasum -a 256 -c <file>.sha256`, and open it the way a user
  would: macOS warns the first time because the app is not notarized (see the README, "Opening it the first time").
- Do not replace files on an existing release. Publish a new version instead, so the checksums stay trustworthy.

## About signing

Ad-hoc signing leaves no developer identity in the app (the script refuses to continue if there is one). A Developer
ID signature plus Apple notarization would remove the first-open warning, but it needs a paid Apple Developer
account in your name, which macOS then shows to users.
