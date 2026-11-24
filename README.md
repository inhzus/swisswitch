<p align="center"><img src="docs/icon.png" width="128" alt="swisswitch icon"></p>

# swisswitch

<p align="center"><a href="https://github.com/inhzus/swisswitch/actions/workflows/ci.yml"><img src="https://github.com/inhzus/swisswitch/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <a href="https://github.com/inhzus/swisswitch/releases/latest"><img src="https://img.shields.io/github/v/release/inhzus/swisswitch" alt="Release"></a></p>

Switch apps on macOS with **Right ⌘ + a letter**.

Hold the right Command key and press a letter, and swisswitch jumps straight to the app whose name starts with it. You don't cycle through ⌘-Tab, and the left Command key works normally for your usual shortcuts.

## Install

Requires **macOS 27** or later on Apple silicon.

**Homebrew**

```sh
brew install --cask inhzus/tap/swisswitch
```

**Manually**: download `Swisswitch-<version>.zip` from
[Releases](https://github.com/inhzus/swisswitch/releases/latest), unzip it, and move
`Swisswitch.app` to `/Applications`.

> Releases are not notarized yet, so on first launch macOS says it can't check the app for
> malicious software. Clear the quarantine flag once:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/Swisswitch.app
> ```
>
> The Homebrew cask does this for you.

Then grant **Accessibility** when asked (see [Permissions](#permissions)).

## How it works

- **Right ⌘ + letter**: focus the running app whose name starts with that letter, e.g. `S` for Safari or `T` for Terminal.
- **Not running?** The same keys launch the matching installed app.
- **Several matches?** The first press goes to the one you use most; press again to cycle through the rest.
- **Hold Right ⌘** for about a second to preview every app and its letter.
- **Settings** (menu bar → **Settings…**, ⌘,): **General** has launch at login, the switch HUD and hold-preview toggles, the preview delay, resetting learned preferences, and Accessibility status.
- **Your own keys**: Settings → **Keys** lists your apps. Click an app's key and press any letter or digit to reassign it, or ⌫ to give it none. Right ⌘ + digit is only intercepted when some app has that digit, so apps keep their own ⌘1…⌘9 shortcuts. Assignments live in the app's defaults (`defaults read io.zunish.Swisswitch keyAssignments`).
- **Learns your habits**: activations that stick (≥ 1.5 s in front) raise an app's score, which halves every 7 days without use. Stats live in `~/Library/Application Support/swisswitch/usage.json`.
- **Already in front?** Pressing its letter again hides it.
- **Left ⌘ is unaffected**, so ⌘C, ⌘V and the rest behave as usual.

## Roadmap

**MVP**
- [x] Global Right ⌘ key tap
- [x] Letter → running app matching (also on non-localized names, e.g. 访达 → `F` for Finder)
- [ ] Launching apps that aren't running
- [x] Cycling through apps that share a letter
- [x] Liquid Glass switch HUD and Accessibility onboarding
- [ ] Hide on re-press
- [x] Menu-bar app (no Dock icon) with Quit
- [x] Usage-learned preference among apps sharing a letter

**Later**
- [x] Custom key assignments per app (letters and digits), in a Settings window
- [ ] Configurable trigger key (Caps Lock, fn, Right ⌥, …)
- [x] On-screen hint overlay showing which letter maps to which app (hold Right ⌘)
- [ ] Cycling through windows of the same app
- [x] Launch at login

## Prior art

swisswitch is inspired by these apps:

- [rcmd](https://lowtechguys.com/rcmd/): the original Right ⌘ + letter switcher, now with window management, Spaces, and more.
- [Dory](https://apps.apple.com/us/app/dory-app-switcher/id6746273626?mt=12): a typing-based switcher that learns your usage.

swisswitch aims to be a small, free, open-source take on the core idea, Right ⌘ + letter, done well.

## Building

Requires **macOS 27** or later. Only the Xcode Command Line Tools are needed; full Xcode isn't.

```sh
swift run swisswitch          # run from the terminal (quit from the menu bar or Ctrl-C)
./scripts/test.sh             # run the tests
./scripts/bundle.sh           # build build/Swisswitch.app (LSUIElement, no Dock icon)
./scripts/package.sh          # bundle and zip as build/Swisswitch-<version>.zip
swift scripts/make-icon.swift # regenerate Resources/AppIcon.icns and docs/icon.png
```

`scripts/test.sh` exists because the Command Line Tools keep the Swift Testing macro plugin in a folder SwiftPM doesn't search by default.

### Debugging

UI automation tools usually post synthetic keys straight to a process, so those keys never reach the global event tap. For scripted checks, set `SWISSWITCH_DEBUG_LETTER_FILE=<path>`, write a letter or digit (or `preview` / `release` for the hold overlay) to that file, and send `kill -USR1 <pid>`. `SWISSWITCH_HUD_HOLD_MS` keeps the HUD on screen longer, `SWISSWITCH_HOLD_MS` overrides the Right ⌘ hold delay set in Settings, `SWISSWITCH_USAGE_FILE` points usage stats at another file, and `SWISSWITCH_DEFAULTS_SUITE` stores key assignments in another defaults domain.

## Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, merge, then push a version tag:

```sh
git tag v1.2.3 && git push origin v1.2.3
```

The [release workflow](.github/workflows/release.yml) tests, builds the app, zips it, and
publishes a GitHub release. [CI](.github/workflows/ci.yml) runs the tests and a bundle on
every push and pull request. Both use GitHub's `xcode-27` runner (macOS 27, arm64). These
repository secrets are optional, and each one turns on a step:

| Secret | Turns on |
| --- | --- |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | Signing with that identity (base64 of the `.p12` export) |
| `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Notarization with an App Store Connect API key (contents of the `.p8`); needs a Developer ID identity |
| `TAP_DEPLOY_KEY` | Pushing the updated cask to [`inhzus/homebrew-tap`](https://github.com/inhzus/homebrew-tap) (the private half of a deploy key with write access there) |

macOS ties the Accessibility grant to the code signature. Without a signing secret, releases
are signed ad-hoc and users have to grant access again after every upgrade. A Developer ID
certificate fixes that, and so does the self-signed identity from `scripts/make-cert.sh`.
To use the self-signed one, export it:

```sh
security export -k login.keychain-db -t identities -f pkcs12 -P <password> -o swisswitch.p12
base64 -i swisswitch.p12 | pbcopy   # → MACOS_CERT_P12; <password> → MACOS_CERT_PASSWORD
```

(If the login keychain holds other identities, export it from Keychain Access instead:
select the "swisswitch Dev" certificate and choose File → Export Items.)

The cask template is [`packaging/homebrew/swisswitch.rb`](packaging/homebrew/swisswitch.rb).
Once releases are notarized, drop its `postflight_steps` block and the quarantine note above.

## Permissions

swisswitch will need **Accessibility** access, granted in System Settings → Privacy & Security → Accessibility. It uses this to listen for the global Right ⌘ key and to bring apps to the front.

## Status

Early days. Right ⌘ + letter switches between running apps, preferring the ones you use most; holding Right ⌘ previews them all; quit from the ⌘ menu-bar item.

## License

TBD.
