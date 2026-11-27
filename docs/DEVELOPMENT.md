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

macOS ties the Accessibility grant to the bundle ID plus the signing certificate, so an
ad-hoc build loses it on every rebuild. `bundle.sh` signs with the first identity it finds:
"Swisswitch Release" (if it's in your keychain, local builds share the installed release's
grant), then "swisswitch Dev", then ad-hoc. Without the release certificate, run
`scripts/make-cert.sh` once to create the self-signed "swisswitch Dev" identity, and the
grant then survives rebuilds. `SWISSWITCH_SIGN_IDENTITY` picks another identity.

## Data

- Key assignments and preferences: the `io.zunish.Swisswitch` defaults domain
  (`defaults read io.zunish.Swisswitch keyAssignments`).
- Usage stats: `~/Library/Application Support/swisswitch/usage.json`. An activation that
  stays in front for at least 1.5 s raises an app's score, and the score halves every 7 days
  without use.
- Log: `~/Library/Application Support/swisswitch/logs/swisswitch.log` (menu bar → Show Log
  in Finder). It rolls over at 1 MB into `swisswitch.1.log` … `swisswitch.3.log`, so it never
  takes more than about 4 MB. The same lines go to the unified log
  (`log stream --predicate 'subsystem == "io.zunish.Swisswitch"'`) and to stderr when run
  from a terminal.

## Debugging

UI automation tools usually post synthetic keys straight to a process, so those keys never
reach the global event tap. For scripted checks, set `SWISSWITCH_DEBUG_LETTER_FILE=<path>`,
write a letter or digit (or `preview` / `release` for the hold overlay) to that file, and
send `kill -USR1 <pid>`.

| Variable | Effect |
| --- | --- |
| `SWISSWITCH_HUD_HOLD_MS` | Keeps the switch HUD on screen longer |
| `SWISSWITCH_HOLD_MS` | Overrides the trigger key hold delay set in Settings |
| `SWISSWITCH_USAGE_FILE` | Points usage stats at another file |
| `SWISSWITCH_DEFAULTS_SUITE` | Stores key assignments in another defaults domain |
| `SWISSWITCH_LOG_FILE` | Writes the log to another file (archives go next to it) |

## Roadmap

- [ ] Launching apps that aren't running
- [ ] Hiding the front app when its letter is pressed again
- [x] Configurable trigger key (Right ⌘, ⌥, ⌃ or ⇧)
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

Releases are signed with a self-signed **"Swisswitch Release"** certificate, stored in the
`MACOS_CERT_*` secrets. macOS ties the Accessibility grant to the bundle ID plus this
certificate, so the grant survives upgrades. **Don't replace the certificate:** a new one, or
a release without the secrets (signed ad-hoc), makes every user grant Accessibility again.

| | |
| --- | --- |
| Subject | `CN=Swisswitch Release` (self-signed, Code Signing only), serial `9DC4D9F36E28CEFD` |
| Valid | 2026-11-24 to 2046-11-19 |
| SHA-1 | `75EE883388389C11F65B70CAB4BC1B7CCD7B46BC` |
| SHA-256 | `60FCCB91E22C83B1291F01315CE0C74809A64846DFDB8289715C9CDAA41D6B91` |
| Backup | 1Password, Personal vault, item **"Swisswitch Release signing cert"**: the `.p12` file, and its export password in `password` |

A correctly signed build shows this SHA-1 in its designated requirement:

```sh
codesign -dr - /Applications/Swisswitch.app   # … certificate leaf = H"75ee8833…7b46bc"
```

With the [1Password CLI](https://developer.1password.com/docs/cli/) signed in (`op signin`),
these commands restore the certificate from the backup:

```sh
ITEM="Swisswitch Release signing cert"

# GitHub secrets
op document get "$ITEM" --vault Personal | base64 | gh secret set MACOS_CERT_P12
op read "op://Personal/$ITEM/password" | gh secret set MACOS_CERT_PASSWORD

# Login keychain on a new Mac (local builds then use it automatically, see Building)
P12="$(mktemp -d)/release.p12"
op document get "$ITEM" --vault Personal --out-file "$P12"
security import "$P12" -k ~/Library/Keychains/login.keychain-db \
    -P "$(op read "op://Personal/$ITEM/password")" -T /usr/bin/codesign
rm -f "$P12"

# Check the backup: should print the SHA-1 above
op document get "$ITEM" --vault Personal |
    openssl pkcs12 -nokeys -legacy -passin "pass:$(op read "op://Personal/$ITEM/password")" |
    openssl x509 -noout -fingerprint -sha1
```

The `.p12` uses the legacy encryption that Keychain Access exports. OpenSSL 3 and later
need `-legacy` to read it, and the macOS LibreSSL at `/usr/bin/openssl` reads it without the flag.

The cask template is [`packaging/homebrew/swisswitch.rb`](../packaging/homebrew/swisswitch.rb).
Once releases are notarized, drop its `postflight_steps` block and the quarantine note in
the README.
