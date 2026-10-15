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
(0.957, every right text kept intact, about 90 ms; Gemma 4 E2B scored 0.968
but weighs 3.3 GB, Apple's model 0.956 at 470 ms). `report-first-prompt.md`
is the first prompt's run, before the dictionary and the transcript were
framed as data.
