# Koe

**Talk. It types.** Hold fn, say it, and your words land where your cursor
is. On your Mac, offline, in about a tenth of a second.

Koe lives in the menu bar as a little chat bubble. It runs Parakeet Ultra on
the Apple Neural Engine (through [FluidAudio](https://github.com/FluidInference/FluidAudio)):
no account, no cloud, nothing to choose.

- **Hold fn** and talk; let go and the words are typed. Or, from the menu,
  **press fn** to start and again to stop.
- **The menu** keeps your last five dictations: click one to copy it.
- Sound, Open at Login. That is all.

Koe needs an Apple silicon Mac with macOS 14 or later, the microphone, and
Accessibility (to hear fn and to paste).

## Build

```sh
SIGN=- scripts/build.sh     # build/Koe.app, signed ad hoc
```

`Koe --transcribe <file.wav>…` prints what Koe hears in each file;
`Koe --render-toasts <dir>` and `Koe --render-sounds <dir>` write its pills and
sounds out to look at and listen to.

Brand: [docs/brand.md](docs/brand.md). Koe belongs to the family of
[Wham](https://github.com/gwendall/wham), from The Atelier.

## Credits

Speech model: [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra)
by moondream, a post-training of NVIDIA
[parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
converted to Core ML by [FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml),
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Runtime:
FluidAudio (Apache-2.0). Pixel font: Silkscreen by Jason Kottke (SIL OFL 1.1).
