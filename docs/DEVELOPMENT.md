# Developing swisswitch

## Building

Needs macOS 27 and the Xcode Command Line Tools; full Xcode isn't required.

```sh
swift run swisswitch          # run from the terminal (quit from the menu bar or Ctrl-C)
scripts/test.sh               # run the tests
scripts/bundle.sh             # build build/Swisswitch.app (menu bar only, no Dock icon)
scripts/package.sh            # bundle and zip as build/Swisswitch-<version>.zip
swift scripts/make-icon.swift # regenerate Resources/AppIcon.icns and docs/icon.png
```

`scripts/test.sh` exists because the Command Line Tools keep the Swift Testing macro plugin
in a folder SwiftPM doesn't search by default.

macOS ties the Accessibility grant to the code signature, so an ad-hoc build loses it on
every rebuild. Run `scripts/make-cert.sh` once to create a self-signed "swisswitch Dev"
identity; `bundle.sh` signs with it automatically, and the grant then survives rebuilds.

## Data

- Key assignments and preferences: the `io.zunish.Swisswitch` defaults domain
  (`defaults read io.zunish.Swisswitch keyAssignments`).
- Usage stats: `~/Library/Application Support/swisswitch/usage.json`. An activation that
  stays in front for at least 1.5 s raises an app's score, and the score halves every 7 days
  without use.

## Debugging

UI automation tools usually post synthetic keys straight to a process, so those keys never
reach the global event tap. For scripted checks, set `SWISSWITCH_DEBUG_LETTER_FILE=<path>`,
write a letter or digit (or `preview` / `release` for the hold overlay) to that file, and
send `kill -USR1 <pid>`.

| Variable | Effect |
| --- | --- |
| `SWISSWITCH_HUD_HOLD_MS` | Keeps the switch HUD on screen longer |
| `SWISSWITCH_HOLD_MS` | Overrides the Right ⌘ hold delay set in Settings |
| `SWISSWITCH_USAGE_FILE` | Points usage stats at another file |
| `SWISSWITCH_DEFAULTS_SUITE` | Stores key assignments in another defaults domain |

## Roadmap

- [ ] Launching apps that aren't running
- [ ] Hiding the front app when its letter is pressed again
- [ ] Configurable trigger key (Caps Lock, fn, Right ⌥, …)
- [ ] Cycling through windows of the same app

## Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, merge, then push a version tag:

```sh
git tag v1.2.3 && git push origin v1.2.3
```

The [release workflow](../.github/workflows/release.yml) tests, builds the app, zips it, and
publishes a GitHub release. [CI](../.github/workflows/ci.yml) runs the tests and a bundle on
every push and pull request. Both use GitHub's `xcode-27` runner (macOS 27, arm64). These
repository secrets are optional, and each one turns on a step:

| Secret | Turns on |
| --- | --- |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | Signing with that identity (base64 of the `.p12` export) |
| `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Notarization with an App Store Connect API key (contents of the `.p8`); needs a Developer ID identity |
| `TAP_DEPLOY_KEY` | Pushing the updated cask to [`inhzus/homebrew-tap`](https://github.com/inhzus/homebrew-tap) (the private half of a deploy key with write access there) |

Releases are signed with a self-signed **"Swisswitch Release"** certificate (valid until
2046), stored in the `MACOS_CERT_*` secrets, with a backup in the maintainer's login keychain.
macOS ties the Accessibility grant to the bundle ID plus this certificate, so the grant
survives upgrades. **Don't replace the certificate:** a new one, or a release without
the secrets (signed ad-hoc), makes every user grant Accessibility again.

To sign a local build the way releases are signed, run
`SWISSWITCH_SIGN_IDENTITY="Swisswitch Release" scripts/bundle.sh`. To restore the secrets
from the backup, export the certificate from Keychain Access (File → Export Items as
`.p12`), then:

```sh
base64 -i swisswitch-release.p12 | gh secret set MACOS_CERT_P12
gh secret set MACOS_CERT_PASSWORD   # the export password
```

The cask template is [`packaging/homebrew/swisswitch.rb`](../packaging/homebrew/swisswitch.rb).
Once releases are notarized, drop its `postflight_steps` block and the quarantine note in
the README.
