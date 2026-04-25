# tok

Pure Erlang tokenizer for [HuggingFace](https://huggingface.co) `tokenizer.json` files.
No NIFs, no Python, no native dependencies — drop a `tokenizer.json` next to your application and encode text directly from Erlang.

## Supported formats

| Type | Models |
|------|--------|
| WordPiece | BERT, DistilBERT, RoBERTa-base, multilingual BERT, ... |
| BPE — ByteLevel | GPT-2, Falcon, Llama 3, Mistral-Nemo, ... |
| BPE — Metaspace | Llama 2, Mistral 7B, Phi-3, ... |

## Installation

```erlang
%% rebar.config
{deps, [{tok, "0.2.0"}]}.
```

## Quick start

```erlang
{ok, Tok} = tok:load("path/to/tokenizer.json"),

%% Encode — returns {InputIds, AttentionMask, TokenTypeIds} as flat binaries
%% of int32 little-endian values, padded to max_length from the tokenizer config.
{IdsBin, MaskBin, _TypeBin} = tok:encode(Tok, <<"Hello world">>),

%% Decode ids from the binary
Ids = [Id || <<Id:32/signed-little>> <= IdsBin],

%% Decode back to text (strips special tokens)
Text = tok:decode(Tok, Ids),

%% Count tokens without building the output binary
N = tok:count_tokens(Tok, <<"Hello world">>).
```

## Getting a tokenizer.json

Download directly from HuggingFace:

```bash
# Any model page → Files → tokenizer.json
curl -L https://huggingface.co/<org>/<model>/resolve/main/tokenizer.json \
     -o tokenizer.json
```

Or save from the Python `transformers` library:

```python
from transformers import AutoTokenizer
AutoTokenizer.from_pretrained("bert-base-uncased").save_pretrained(".")
# tokenizer.json is now in the current directory
```

## API

```erlang
%% Load a tokenizer from a tokenizer.json file.
-spec load(file:filename()) -> {ok, tokenizer()} | {error, term()}.

%% Encode text. Returns three binaries of int32 little-endian values,
%% each padded to max_length as configured in the tokenizer file.
-spec encode(tokenizer(), binary()) ->
    {InputIds, AttentionMask, TokenTypeIds}.

%% Encode with options.
%%   add_special_tokens => false  skips CLS/SEP (WordPiece) or BOS/EOS (BPE).
-spec encode(tokenizer(), binary(), #{add_special_tokens => boolean()}) ->
    {InputIds, AttentionMask, TokenTypeIds}.

%% Encode a list of texts.
-spec encode_batch(tokenizer(), [binary()]) ->
    [{InputIds, AttentionMask, TokenTypeIds}].
-spec encode_batch(tokenizer(), [binary()], #{add_special_tokens => boolean()}) ->
    [{InputIds, AttentionMask, TokenTypeIds}].

%% Decode a list of token IDs back to text. Special tokens are stripped.
-spec decode(tokenizer(), [integer()]) -> binary().

%% Count real tokens (after truncation, including special tokens).
%% Cheaper than encode/2 — does not allocate output binaries.
-spec count_tokens(tokenizer(), binary()) -> non_neg_integer().

%% Return vocabulary size.
-spec vocab_size(tokenizer()) -> integer().
```

### Reading the output binary

```erlang
{IdsBin, MaskBin, TypeBin} = tok:encode(Tok, Text),

InputIds     = [Id || <<Id:32/signed-little>> <= IdsBin],
AttentionMask = [M  || <<M:32/signed-little>>  <= MaskBin],
TokenTypeIds  = [T  || <<T:32/signed-little>>  <= TypeBin].
```

The binary format matches what most ONNX runtimes and NIF-based inference libraries expect directly, so you can often pass `IdsBin` through without decoding.

## Notes

- **max_length** is read from the `truncation` section of `tokenizer.json`. If absent, defaults to 512.
- **pad_id** is read from the `padding` section. If absent, defaults to the `[PAD]` token id or 0.
- BOS/EOS tokens are injected automatically when a `TemplateProcessing` post-processor is present in the tokenizer file.
- `byte_fallback` (Llama 2 / Mistral style) is supported: characters not in the vocabulary are split into `<0xNN>` byte tokens.

## License

Apache 2.0 — see [LICENSE](LICENSE).
