<p align="center"><img src="docs/icon.png" width="128" alt="swisswitch icon"></p>

<h1 align="center">swisswitch</h1>

<p align="center">
  Switch apps on macOS with <b>Right ⌘ + a letter</b>.
  <br>
  <a href="https://github.com/inhzus/swisswitch/actions/workflows/ci.yml"><img src="https://github.com/inhzus/swisswitch/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/inhzus/swisswitch/releases/latest"><img src="https://img.shields.io/github/v/release/inhzus/swisswitch" alt="Release"></a>
</p>

Hold the right Command key and press a letter to jump straight to that app: `S` for Safari,
`T` for Terminal. No ⌘-Tab cycling, and the left ⌘ keeps working as usual.

## Features

- **Learns your habits.** When several running apps share a letter, the first press goes to
  the one you use most; press again to cycle through the rest.
- **Hold to preview.** Hold Right ⌘ for about a second to see every app and its letter.
- **Your own keys.** Reassign any app to a letter or digit in Settings → Keys. Digits are only
  taken when an app uses them, so ⌘1…⌘9 keep working elsewhere.
- **Pick your trigger.** Use Right ⌘, Right ⌥, Right ⌃ or Right ⇧ (Settings → General). Only
  the right-hand key triggers; its left twin keeps its usual job.
- **Native names.** Localized apps match by their English name too, e.g. 访达 → `F` for Finder.

## Install

Requires macOS 27 or later on Apple silicon.

```sh
brew install --cask inhzus/tap/swisswitch
```

Or download the zip from [Releases](https://github.com/inhzus/swisswitch/releases/latest)
and move `Swisswitch.app` to `/Applications`.

> [!NOTE]
> Releases are not notarized yet. If you install manually, clear the quarantine flag once:
> `xattr -dr com.apple.quarantine /Applications/Swisswitch.app`. The Homebrew cask does
> this for you.

On first launch, grant **Accessibility** in System Settings → Privacy & Security. swisswitch
needs it to see the trigger key and bring apps to the front.

## Prior art

Inspired by [rcmd](https://lowtechguys.com/rcmd/) and
[Dory](https://apps.apple.com/us/app/dory-app-switcher/id6746273626?mt=12). swisswitch is a
small, free, open-source take on the core idea.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for building, debugging and releasing.

## License

Licensed under the [Apache License 2.0](LICENSE).
