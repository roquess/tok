# motif + nli + nuance Design Spec

**Goal:** Replace the Python `nuance` topic-extraction tool with a pure Erlang stack —
`motif` (keyword extraction) + `nli` (Natural Language Inference) — and expose the same
CLI interface as the original.

**Architecture:** Three independent units. `motif` extracts keyword candidates from raw
text using the RAKE algorithm with multilingual stop-word lists. `nli` scores
(premise, hypothesis) pairs using a multilingual ONNX NLI model. `nuance` is an escript
that chains the two: extract candidates → score each against the full text → return top-K.

**Tech Stack:** Erlang/OTP, rebar3, Common Test, onyx 0.1+, tok 0.2+, Apache-2.0.

---

## Dependency Graph

```
nuance (escript)
├── motif   — pure Erlang, no external deps
└── nli
    ├── tok  0.2.0
    └── onyx 0.1.0
```

---

## motif

### Purpose

Extract ranked keyword/phrase candidates from a text using RAKE
(Rapid Automatic Keyword Extraction). Pure Erlang, no ML required.

### Files

```
motif/
  src/
    motif.erl           — public API
    motif_rake.erl      — RAKE scoring algorithm
    motif_stopwords.erl — bundled stop-word lists (fr, en, de)
    motif_lang.erl      — language auto-detection
    motif.app.src
  test/
    motif_SUITE.erl
  rebar.config
  README.md
  LICENSE
```

### Public API

```erlang
%% Extract keyword candidates with RAKE scores.
%% Options:
%%   max  => pos_integer()   max candidates to return (default: all)
%%   lang => fr | en | de | auto   stop-word language (default: auto)
-spec extract(binary()) -> [{binary(), float()}].
-spec extract(binary(), #{max  => pos_integer(),
                           lang => fr | en | de | auto}) -> [{binary(), float()}].

%% Return the built-in stop-word list for a language.
-spec stop_words(fr | en | de) -> [binary()].
```

### RAKE Algorithm

1. Normalise text: lowercase, strip punctuation except hyphens inside words.
2. Split into sentences on `. ! ?`.
3. Within each sentence, split on stop words and single characters → candidate phrases.
4. Build a word co-occurrence matrix across all candidates.
5. Score each word: `degree(word) / frequency(word)`.
6. Score each candidate phrase: sum of its word scores.
7. Return candidates sorted by score descending.

### Language Auto-Detection

`auto` samples the first 200 words, counts stop-word hits per language list,
picks the language with the most hits. Falls back to `en` on a tie.

### Stop Words

| Language | Count |
|----------|-------|
| fr       | ~450  |
| en       | ~175  |
| de       | ~200  |

Lists are embedded as Erlang terms in `motif_stopwords.erl` — no external files.

### Publishing Requirements

- All code and comments in English.
- Inline comments on non-obvious logic only.
- README: purpose, installation, quick start, full API, algorithm note.
- License: Apache-2.0 (`LICENSE` file + `{licenses, ["Apache-2.0"]}` in `app.src` and `rebar.config`).

---

## nli

### Purpose

Natural Language Inference: given a premise and a hypothesis, return the probability
that the premise *entails* the hypothesis. Wraps an ONNX NLI model via `onyx` and
`tok` for tokenization.

### Files

```
nli/
  src/
    nli.erl       — public API
    nli.app.src
  test/
    nli_SUITE.erl
    nli_SUITE_data/tokenizer.json   (multilingual tokenizer fixture)
  rebar.config
  README.md
  LICENSE
```

### Public API

```erlang
%% Load a tokenizer + NLI ONNX model.
-spec load(file:filename(), file:filename()) -> {ok, nli()} | {error, term()}.

%% Return the entailment probability for (Premise, Hypothesis). Range [0.0, 1.0].
-spec score(nli(), binary(), binary()) -> {ok, float()} | {error, term()}.

%% Release the ONNX session.
-spec unload(nli()) -> ok.
```

### Inference Pipeline

1. Encode the pair: `[CLS] premise [SEP] hypothesis [SEP]` — tok handles this
   via `tok:encode/3` with `add_special_tokens => true`.
2. Run through onyx session.
3. Model outputs logits for 3 classes: `[contradiction, neutral, entailment]`.
4. Apply softmax to logits.
5. Return `softmax[2]` (entailment index).

### Recommended Model

`MoritzLaurer/mDeBERTa-v3-base-mnli-xnli` — multilingual DeBERTa, native fr/en/de,
XNLI-trained. Export with:

```bash
pip install optimum
optimum-cli export onnx --model MoritzLaurer/mDeBERTa-v3-base-mnli-xnli ./model/
```

Place `tokenizer.json` and `model.onnx` (or `model_optimized.onnx`) in `priv/` or
pass paths explicitly to `nli:load/2`.

### Label Index

The entailment label is at index 2 for XNLI-family models. `nli` reads the
`id2label` map from the ONNX session metadata if available; falls back to index 2.

### Publishing Requirements

Same as motif: English code and comments, README, Apache-2.0.

---

## nuance (application)

### Purpose

Escript that replicates the Python `nuance/topics.py` CLI exactly, using
`motif` + `nli` under the hood.

### Files

```
nuance_erl/
  src/nuance.erl      — escript entry point + pipeline
  priv/               — tokenizer.json + model.onnx (gitignored)
  rebar.config        — deps: motif + nli
  README.md
  LICENSE
```

### CLI Interface

```bash
./nuance <file> [--max N] [--lang fr|en|de|auto] [--format simple|json|verbose] [--quiet]
```

| Flag       | Default  | Description                              |
|------------|----------|------------------------------------------|
| `--max`    | 6        | Number of topics to return               |
| `--lang`   | auto     | Stop-word language for motif             |
| `--format` | verbose  | Output format                            |
| `--quiet`  | false    | Suppress stderr progress messages        |

### Output Formats

```
simple   one topic per line           (pipe-friendly)
json     ["topic1","topic2",…]
verbose  1. topic1\n2. topic2\n…
```

### Pipeline

```
read file
    │
    ▼
motif:extract(Text, #{max => 30, lang => Lang})
    │  up to 30 candidates
    ▼
nli:score(NLI, Text, Candidate) for each candidate
    │  entailment probability per candidate
    ▼
sort desc, take top --max
    │
    ▼
format and print to stdout
```

`motif` generates more candidates (30) than the final output (default 6) so that
`nli` reranking has enough material to work with.

### Model Location

`priv/tokenizer.json` and `priv/model.onnx` by default. Override via environment
variables `NLI_TOKENIZER` and `NLI_MODEL`.

---

## Self-Review

### Spec Coverage

| Requirement                        | Where          |
|------------------------------------|----------------|
| RAKE keyword extraction            | motif          |
| fr/en/de stop words                | motif          |
| Language auto-detection            | motif          |
| NLI scoring (entailment prob)      | nli            |
| Multilingual model (fr/en/de)      | nli            |
| Pair encoding [CLS] P [SEP] H [SEP]| nli            |
| CLI identical to Python nuance     | nuance         |
| --max, --lang, --format, --quiet   | nuance         |
| 30 candidates → nli rerank → top-K | nuance         |
| English code + comments            | all three      |
| README + Apache-2.0                | all three      |

### Placeholder Scan

None found.

### Scope

Three focused units, each independently testable and publishable. Appropriate
for three separate implementation plans (motif → nli → nuance).
