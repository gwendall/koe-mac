# Polish evals

How Koe's optional polishing (app/Sources/Polish.swift) was chosen and tuned:
the same dictations through each candidate, scored against what they should
read, timed warm on an M5 MacBook Pro.

- `cases.py`: 69 dictations in six kinds (kept as is, fillers and repeats,
  dictionary words, traps that must not be answered, other languages, long
  ones), four of them real Parakeet output.
- `fillers.py`: the rule pass, the same as `Fillers` in Polish.swift.
- `bench.py`: runs a model through llama-server (or Apple's on-device model
  through `apple/run.swift`), keeps its answer only when it stays close to
  what was said (as Koe does), and writes `results/`.

```sh
brew install llama.cpp
python3 bench.py rules                                   # the rule pass alone
PREPASS=1 python3 bench.py llama Qwen3.5-2B-Q4_K_M.gguf  # rules, then a model
swiftc -O -o apple/run apple/run.swift && python3 bench.py apple
python3 bench.py report
```

Quality is the mean similarity to the expected text (1 = exact); the raw
transcript scores 0.896. "Trap answered" is how often a model replied to a
question or an instruction instead of cleaning it (Koe then keeps the
transcript). See `report.md` for the run behind the choice: the rules alone
(0.931, no latency) always, and Qwen3.5 2B Q4_K_M after them when switched on
(0.957, every right text kept intact, about 90 ms, the fewest traps
answered). A second round of smaller models: Llama 3.2 1B matches it (0.954)
at 0.8 GB and 37 ms but answers three times as many traps; Phi-4-mini (0.972,
2.5 GB), Gemma 3n and 4 E2B (0.971 and 0.968, 3 GB and more), SmolLM3 3B
(0.966, 1.9 GB) score higher for their weight; below a billion parameters
(Granite 350M, SmolLM2 360M, Apple's OpenELM 270M) models spoil right text
or answer it. Apple's on-device model: 0.956 at 470 ms. `report-first-prompt.md`
is the first prompt's run, before the dictionary and the transcript were
framed as data.
