# swisswitch

Switch apps on macOS with **Right ⌘ + a letter**.

Hold the right Command key and press a letter, and swisswitch jumps straight to the app whose name starts with it. You don't cycle through ⌘-Tab, and the left Command key works normally for your usual shortcuts.

## How it works

- **Right ⌘ + letter**: focus the running app whose name starts with that letter, e.g. `S` for Safari or `T` for Terminal.
- **Not running?** The same keys launch the matching installed app.
- **Several matches?** Press the letter again to cycle through them.
- **Already in front?** Pressing its letter again hides it.
- **Left ⌘ is unaffected**, so ⌘C, ⌘V and the rest behave as usual.

## Roadmap

**MVP**
- [ ] Global Right ⌘ key tap
- [ ] Letter → running app matching, plus launching apps that aren't running
- [ ] Cycling through apps that share a letter
- [ ] Hide on re-press
- [ ] Menu-bar app (no Dock icon)

**Later**
- [ ] Custom letter assignments per app
- [ ] Configurable trigger key (Caps Lock, fn, Right ⌥, …)
- [ ] On-screen hint overlay showing which letter maps to which app
- [ ] Cycling through windows of the same app
- [ ] Launch at login

## Prior art

swisswitch is inspired by these apps:

- [rcmd](https://lowtechguys.com/rcmd/): the original Right ⌘ + letter switcher, now with window management, Spaces, and more.
- [Dory](https://apps.apple.com/us/app/dory-app-switcher/id6746273626?mt=12): a typing-based switcher that learns your usage.

swisswitch aims to be a small, free, open-source take on the core idea, Right ⌘ + letter, done well.

## Building (planned)

- A Swift Package Manager executable target.
- `scripts/bundle.sh` wraps the binary into `Swisswitch.app`, with an `Info.plist` that sets `LSUIElement` so the app runs from the menu bar.
- Only the Xcode Command Line Tools are required; full Xcode isn't needed.

## Permissions

swisswitch will need **Accessibility** access, granted in System Settings → Privacy & Security → Accessibility. It uses this to listen for the global Right ⌘ key and to bring apps to the front.

## Status

Early days. Nothing runnable yet.

## License

TBD.
