# Making a release

## 1. Build the files

```sh
scripts/make_release.sh 1.0
```

This builds an **arm64 Release** (signed locally, ad-hoc), checks the signature, and writes to `dist/`:

- `NorthernCrater-1.0-arm64.dmg` (the download most people want)
- `NorthernCrater-1.0-arm64.zip`
- `NorthernCrater-1.0-arm64.sha256`

The version defaults to `MARKETING_VERSION` in the Xcode project (change it there to bump the app's own version).

## 2. Check them

- Open the DMG and drag the app to Applications.
- Run it. macOS will warn the first time because the app is not notarized; follow the README's "Opening it the first time".
- Confirm `shasum -a 256 -c dist/NorthernCrater-1.0-arm64.sha256` prints OK for both files.

## 3. Publish

On GitHub, create a release (Releases, Draft a new release) with a tag such as `v1.0`, attach the three files, and paste notes like the ones below. Or with the GitHub CLI:

```sh
gh release create v1.0 dist/NorthernCrater-1.0-arm64.* \
  --title "NorthernCrater 1.0" --notes-file release-notes.md
```

(`release-notes.md` is a file you write from the template below; do not commit it unless you want to.)

### Release notes template

> **NorthernCrater 1.0** for Apple Silicon Macs.
>
> Download `NorthernCrater-1.0-arm64.dmg`, drag the app to Applications, and follow the README to open it the first time and build the game engine from your own copy of FINAL FANTASY VII (Steam, the new release). This download contains **no game files** and no built engine.
>
> macOS will warn when you first open it, because the app is not notarized by Apple. See "Opening it the first time" in the README.
>
> Not affiliated with or endorsed by Square Enix. FINAL FANTASY is a trademark of Square Enix.

## Things to keep in mind

- **Never attach a built engine** (`NorthernCrater Engine.app`, anything from `~/Library/Caches/NorthernCrater`) or any game file. They contain code derived from the game.
- **Signing.** Ad-hoc signing leaves no developer identity in the app. A Developer ID signature plus Apple notarization would remove the first-open warning, but needs a paid Apple Developer account in your name, which shows your name to users.
- Check `dist/` is not committed (it is in `.gitignore`).
