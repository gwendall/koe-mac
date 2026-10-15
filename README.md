# Koe

**Talk. It types.** Hold fn, say it, and your words land where your cursor
is. On your Mac, offline, in about a tenth of a second.

Koe lives in the menu bar as a little chat bubble. It runs Parakeet Ultra on
the Apple Neural Engine (through [FluidAudio](https://github.com/FluidInference/FluidAudio)):
no account, no cloud, nothing to choose.

- **Hold fn** and talk; let go and the words are typed where your cursor is
  (even if you clicked another field meanwhile). Escape cancels.
- **Your shortcut:** fn, a modifier on its own (right ⌥…), or a combination;
  hold to talk, or press to start and stop.
- **The menu** keeps your last five dictations: click one to copy it.
- **Settings:** microphone, Return after typing, a dictionary of your words,
  sounds, open at login, automatic updates, a diagnostic report.
- **Never loses a word:** every dictation is on disk until it is typed; after
  a crash Koe puts it on the clipboard at the next launch.

Koe needs an Apple silicon Mac with macOS 14 or later, the microphone, and
Accessibility (to hear fn and to paste). It speaks the Mac's language: ten of
them, as [Wham](https://github.com/gwendall/wham) does.

## Install

```sh
curl -fsSL koe.fm | sh                       # or
brew install --cask gwendall/tap/koe
```

or the disk image from [Releases](https://github.com/gwendall/koe-mac/releases/latest).
Uninstall: `curl -fsSL koe.fm/uninstall | sh`.

## Build

```sh
SIGN=- scripts/build.sh     # build/Koe.app, signed ad hoc
```

- `Koe --self-test`: the guards (shortcuts, delivery rules, silence, journal).
- `Koe --render-journey <dir>`: every screen a newcomer meets, light and dark.
- `Koe --transcribe <file.wav>…`: what Koe hears in each file.
- `Koe --render-toasts <dir>`, `Koe --render-sounds <dir>`: pills and sounds.

- `scripts/test.sh`: what CI runs on every push (build, self-test, strings, scripts).
- `KOE_EVAL=1 scripts/build.sh`: a build that takes the shortcut, Escape and a
  sound file from outside (distributed notifications `fm.koe.mac.eval.*`),
  for end-to-end runs that make no sound. Never in a release.

## Release

Write the version's notes on koe.fm's changelog first (the koe-site repo), in
every language, and `pnpm changelog` there writes `CHANGELOG.md` here. Then
`scripts/release.sh 2.0.1`: the tag makes GitHub Actions build, sign with
Developer ID, notarize, make `Koe.zip` and `Koe.dmg`, publish the release and
update the Homebrew cask. Secrets it needs: `DEVELOPER_ID_P12`,
`DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`,
`TAP_DEPLOY_KEY`, and `SITE_DEPLOY_HOOK` for the site to pick up a new
`install.sh`.

To meet Koe as a newcomer again: `defaults delete fm.koe.mac` and
`tccutil reset All fm.koe.mac`, then open it.

Brand: [docs/brand.md](docs/brand.md). Koe belongs to the family of
[Wham](https://github.com/gwendall/wham), from The Atelier.

## Credits

Speech model: [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra)
by moondream, a post-training of NVIDIA
[parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
converted to Core ML by [FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml),
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Runtime:
FluidAudio (Apache-2.0). Pixel font: Silkscreen by Jason Kottke (SIL OFL 1.1).
