# Koe

**Talk. It types.** Hold fn, say it, and your words land where your cursor
is. On your Mac, offline, in about a tenth of a second.

Koe lives in the menu bar as a little chat bubble. It runs Parakeet Ultra on
the Apple Neural Engine (through [FluidAudio](https://github.com/FluidInference/FluidAudio)):
no account, no cloud, nothing to choose.

- **Hold fn** and talk; let go and the words are typed where your cursor is
  (even if you clicked another field meanwhile). Escape cancels. A small pill
  low on the screen shows Koe listening, then a check when the words land.
- **25 European languages**, found on their own, even when you switch in the
  middle of a dictation. A **dictionary** spells names and jargon your way.
- **Your shortcut:** fn, a modifier on its own (right ⌥…), or a combination;
  hold to talk, or press to start and stop.
- **The menu** keeps your last five dictations: click one to copy it.
- **Settings:** microphone, Return after typing, a dictionary of your words,
  sounds, open at login, automatic updates, a diagnostic report.
- **Polish the words** (off by default): a small language model on the Mac
  takes out repeats and corrections, spells your dictionary words and fixes
  punctuation, in about 0.1 s; filler sounds (um, uh, euh…) always go. How it
  was chosen: [evals/polish](evals/polish).
- **Never loses a word:** every dictation is on disk until it is typed; after
  a crash Koe puts it on the clipboard at the next launch.

Koe needs an Apple silicon Mac with macOS 14 or later, the microphone, and
Accessibility (to hear fn and to paste). It speaks the Mac's language: ten of
them, as [Wham](https://github.com/gwendall/wham) does. On an Intel Mac, Koe
0.1 (the earlier app, at [v0.koe.fm](https://v0.koe.fm)) still works.

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

It refuses to replace a Koe that is running from there: quit it first, or
build elsewhere with `APP=<path>.app`.

- `Koe --self-test`: the guards (shortcuts, typing, silence, journal, the ten
  languages, deadlines) and thousands of random keys, transcripts and pastes.
- `Koe --render-journey <dir>`: every screen a newcomer meets, light and dark.
- `Koe --transcribe <file.wav>…`: what Koe hears in each file.
- `Koe --render-toasts <dir>`, `Koe --render-sounds <dir>`: pills and sounds.

- `scripts/test.sh`: what CI runs on every push (build, self-test, strings, scripts).
- `KOE_EVAL=1 scripts/build.sh`: a build that takes the shortcut, Escape and a
  sound file from outside (distributed notifications `fm.koe.mac.eval.*`),
  for end-to-end runs that make no sound. Never in a release.

## Release

Write the version's notes on koe.fm's changelog first, in every language (the
site's repo); its `pnpm changelog` writes `CHANGELOG.md` here. Then
`scripts/release.sh 2.0.1`: the tag makes GitHub Actions build, sign with
Developer ID, notarize, make `Koe.zip` and `Koe.dmg`, publish the release and
update the Homebrew cask. Secrets it needs: `DEVELOPER_ID_P12`,
`DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`,
`TAP_DEPLOY_KEY`, and `SITE_DEPLOY_HOOK` for the site to pick up a new
`install.sh`.

To meet Koe as a newcomer again: `defaults delete fm.koe.mac` and
`tccutil reset All fm.koe.mac`, then open it.

Brand: [docs/brand.md](docs/brand.md). Made by Gwendall,
[gwendall.com](https://gwendall.com).

## Credits

Speech model: [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra)
by moondream, a post-training of NVIDIA
[parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
converted to Core ML by [FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml),
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Runtime:
FluidAudio (Apache-2.0). Polishing, when switched on: [Qwen3.5 2B](https://huggingface.co/Qwen/Qwen3.5-2B)
(Apache-2.0, the Q4_K_M quantization by [Unsloth](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF),
downloaded on the Mac that asks for it) through [llama.cpp](https://github.com/ggml-org/llama.cpp)
(MIT, shipped in the app with its license). Pixel font: Silkscreen by Jason Kottke (SIL OFL 1.1).
