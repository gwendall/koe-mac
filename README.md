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
Accessibility (to hear fn and to paste).

## Build

```sh
SIGN=- scripts/build.sh     # build/Koe.app, signed ad hoc
```

- `Koe --self-test`: the guards (shortcuts, delivery rules, silence, journal).
- `Koe --render-journey <dir>`: every screen a newcomer meets, light and dark.
- `Koe --transcribe <file.wav>…`: what Koe hears in each file.
- `Koe --render-toasts <dir>`, `Koe --render-sounds <dir>`: pills and sounds.

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
