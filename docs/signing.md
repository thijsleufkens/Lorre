# Signing Lorre without a paid developer account

Lorre is distributed without an Apple Developer Program membership. This page explains how builds are
signed and what that means for permissions and for other users.

## Why the signing identity matters

macOS remembers privacy permissions (microphone, system-audio capture) per app, and recognises the app by
its *designated requirement*.

| Signing | Designated requirement | Effect |
|---|---|---|
| Ad-hoc (`codesign --sign -`), the default | The hash of the binary | Every build is a new app to macOS; permissions must be granted again |
| A fixed certificate | The bundle identifier plus that certificate | Permissions carry over between builds |

## One-time setup: create the certificate

Do this yourself in Keychain Access; it takes a minute.

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `Lorre Local Signing`. Identity Type: **Self-Signed Root**. Certificate Type: **Code Signing**.
3. Create. The certificate and its private key land in the login keychain.

Check that it is usable:

```bash
security find-identity -p codesigning
```

It is listed under "Matching identities". It does not need to be trusted for Gatekeeper; it only has to be
the same certificate every time.

## Building with it

```bash
LORRE_SIGN_IDENTITY="Lorre Local Signing" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH \
./scripts/package_macos_app.sh release
```

The first time, macOS asks whether `codesign` may use the key; choose **Always Allow**. The script prints
the designated requirement after signing; it should name the certificate instead of a `cdhash`.

Without `LORRE_SIGN_IDENTITY` the script signs ad-hoc as before, so builds on other machines keep working.

## Verifying that permissions survive a rebuild

This has to be checked by hand once; it is the reason for the whole exercise.

1. Build and install with the identity set. Grant microphone and system-audio permission. Make a
   10-second microphone + system audio recording while something is playing, and confirm that both
   tracks contain sound.
2. Change any line of code, build and install again with the same identity.
3. Record again. There should be no permission prompt, and both tracks should contain sound. A silent
   system-audio track means the permission did not carry over, even when no prompt appeared.

If step 3 fails, note the result here and in the product spec's open questions: it affects how updates
reach other users.

**Result:** not yet verified.

## Other identities in the keychain

An "Apple Development" certificate (created by Xcode for an Apple ID) also gives a stable requirement on
the Mac it lives on. It expires and is tied to one Apple ID, so the self-signed certificate is the one to
standardise on.

## What other users see

The app is not notarized. The first time, macOS refuses to open it; the user allows it once under
**System Settings → Privacy & Security → Open Anyway**. After that it opens normally.

For permissions to survive *updates* on other people's Macs, every release must be signed with the same
certificate, so the certificate and its private key need a backup (export as `.p12` from Keychain Access
and store it somewhere safe). Losing it means every user grants permissions once more.

Update delivery (Sparkle, with its own EdDSA signing key) is separate from code signing and is set up in a
later milestone.
