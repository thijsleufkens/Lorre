# Automatic updates

Lorre updates itself with [Sparkle](https://sparkle-project.org). This page explains how that works without
an Apple Developer account, what you do once, and the commands for each release.

**Status:** the code, the packaging and the release script are built and checked as far as one machine goes
(see "What has not been verified"). No real update from one version to the next has been run yet.

## How it works, and why

Normally an app is notarized by Apple, and that is what makes updates trustworthy. Lorre is not notarized
(no developer account), so the trust comes from two other things:

- **Sparkle's own signature (EdDSA).** Every release zip is signed with a private key that only you hold.
  The public half is baked into the app (`SUPublicEDKey`). The app refuses any update whose signature does
  not match, so a hijacked download location cannot push a bad build.
- **The self-signed certificate** ("Lorre Local Signing", see [signing.md](signing.md)). This keeps the app's
  identity the same from release to release, which is what lets macOS keep the privacy permissions.

The app finds updates through an *appcast*: one XML file listing the releases, each with its zip address,
version and signature. The app only has update features when its Info.plist carries both `SUFeedURL` and
`SUPublicEDKey`. A build made without them (for example a plain `swift run`, or the packaging script without
the update variables) has no menu item, no row in Settings and never contacts anything. The command line
never starts the updater.

## One-time step: the signing key (you do this yourself)

Sparkle ships a tool for it. After a `swift build` it sits in the SwiftPM artifacts:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

It stores the private key in your login keychain and prints the public key (a short base64 string). Copy
that string; it is what `LORRE_UPDATE_PUBLIC_KEY` needs.

Back the private key up right away, to a file you keep somewhere safe (not in the repository):

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/some/safe/place/lorre-update-key
```

If you lose the private key, installed copies can no longer be updated automatically: they only accept
updates signed with it, and users would have to install a new build by hand once. The same goes for the
signing certificate in [signing.md](signing.md).

## Where to host the files

Two files per release go online:

1. **`Lorre-<version>.zip`**: an asset of a GitHub release on your fork. Its download address is stable.
2. **`appcast.xml`**: needs one address that never changes, because it is baked into the app. Either the raw
   file on a dedicated branch (for example a `updates` branch holding only `appcast.xml`, served as
   `https://raw.githubusercontent.com/<you>/Lorre/updates/appcast.xml`) or GitHub Pages. The feed address must be
   `https://`.

For the zip address inside the appcast, pass the folder the release assets live under, for example
`https://github.com/<you>/Lorre/releases/download/v1.0/` (see below). Each release has its own tag, so set the
prefix per release.

## Making a release

Set these once per shell (use your own fork and the public key from the step above):

```bash
export LORRE_SIGN_IDENTITY="Lorre Local Signing"
export LORRE_UPDATE_FEED_URL="https://raw.githubusercontent.com/<you>/Lorre/updates/appcast.xml"
export LORRE_UPDATE_PUBLIC_KEY="<the key generate_keys printed>"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH
```

Then, per release (version is what people see, build must always go up):

```bash
export LORRE_UPDATE_DOWNLOAD_PREFIX="https://github.com/<you>/Lorre/releases/download/v1.0/"
./scripts/make_release.sh 1.0 7
```

The script:

1. packages and signs the app with that version and build number;
2. zips it to `dist/release/Lorre-1.0.zip`;
3. runs Sparkle's `generate_appcast` over `dist/release/`, which signs the zip with the private key from
   your keychain (macOS may ask for permission to use it) and creates or extends
   `dist/release/appcast.xml`.

It uploads nothing. At the end it prints the two files to publish: attach the zip to the GitHub release (tag
`v1.0`), and commit the new `appcast.xml` to the `updates` branch (or Pages).

Keep earlier zips in `dist/release/` so the appcast keeps their entries (`dist/` is git-ignored). The script
stops with a message when a variable or Sparkle's tool is missing.

**Cloud-synced folders.** If the repository lives in Dropbox or iCloud, the sync client adds file
attributes that make `codesign` reject the bundle ("resource fork, Finder information, or similar
detritus"). The package script therefore puts the bundle together and signs it in a temporary folder and
copies the result to `dist/` without attributes; the release zip is made without them too. Install a build
with `ditto --noextattr --norsrc dist/Lorre.app /Applications/Lorre.app`, not with `cp -R`.

## What a user sees

**First install.** The app is not notarized, so macOS refuses to open it the first time. The user opens
**System Settings → Privacy & Security** and chooses **Open Anyway**, once. After that it opens normally.

**Updates.** Lorre checks in the background (and on request via **Lorre → Check for Updates…**, or the button in
Settings → About). When a newer release is in the appcast, Sparkle shows its standard window with the version,
downloads the zip, checks the EdDSA signature, replaces the app and restarts it. No "Open Anyway" step again:
Sparkle installs the update itself, it is not a fresh download from a browser.

**Privacy permissions.** Microphone and system-audio permission carry over to the new version only when the
new build has the same designated requirement, which means it must be signed with the same certificate as the
old one (see [signing.md](signing.md)). Ad-hoc builds change identity every time and lose the permissions. A
silent system-audio track after an update is the sign that the permission did not carry over.

## What has not been verified

- An actual update from one version to the next (download, signature check, install, relaunch).
- That permissions carry over through such an update when signed with the self-signed certificate.
- `generate_appcast` against a real release folder and the real private key; the hosting steps above.
- Behaviour of the "Open Anyway" first run on a Mac other than yours.

What was checked: the app builds with Sparkle, the packaged app verifies with `codesign --verify --deep --strict`,
the packaged binary loads the framework, and the update keys appear in the Info.plist only when both
variables are set.

To test an update end to end: build version 1 and install it, build version 2 with a higher build number, make
the release, publish to a test location, and choose Check for Updates in version 1.
