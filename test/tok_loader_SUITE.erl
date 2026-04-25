-module(tok_loader_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0,
         load_wordpiece/1,
         load_missing_file/1,
         load_unsupported_type/1,
         load_bpe_bytelevel/1,
         load_bpe_metaspace/1]).

suite() -> [{timetrap, {seconds, 10}}].

all() -> [load_wordpiece, load_missing_file, load_unsupported_type,
          load_bpe_bytelevel, load_bpe_metaspace].

load_wordpiece(Config) ->
    DataDir = ?config(data_dir, Config),
    Path = filename:join(DataDir, "minimal_tokenizer.json"),
    {ok, Tok} = tok_loader:load(Path),
    wordpiece = maps:get(type,       Tok),
    8          = maps:get(max_length, Tok),
    0          = maps:get(pad_id,     Tok),
    100        = maps:get(unk_id,     Tok),
    101        = maps:get(cls_id,     Tok),
    102        = maps:get(sep_id,     Tok),
    7          = maps:size(maps:get(vocab, Tok)),
    200        = maps:get(<<"hello">>, maps:get(vocab, Tok)).

load_missing_file(_Config) ->
    {error, bad_file} = tok_loader:load("/nonexistent/path.json").

load_unsupported_type(Config) ->
    DataDir = ?config(data_dir, Config),
    Path = filename:join(DataDir, "unigram_tokenizer.json"),
    {error, {unsupported_tokenizer, <<"Unigram">>}} = tok_loader:load(Path).

load_bpe_bytelevel(Config) ->
    DataDir = ?config(data_dir, Config),
    Path = filename:join(DataDir, "bpe_bytelevel.json"),
    {ok, Tok} = tok_loader:load(Path),
    bpe        = maps:get(type,             Tok),
    bytelevel  = maps:get(pre_tokenizer,    Tok),
    false      = maps:get(byte_fallback,    Tok),
    false      = maps:get(add_prefix_space, Tok),
    none       = maps:get(bos_id,           Tok),
    none       = maps:get(eos_id,           Tok),
    16         = maps:get(max_length,       Tok),
    15         = maps:size(maps:get(vocab,  Tok)),
    5          = maps:size(maps:get(merges, Tok)),
    0          = maps:get(<<"H e">>,              maps:get(merges, Tok)),
    4          = maps:get(<<"Ġ world"/utf8>>,    maps:get(merges, Tok)).

load_bpe_metaspace(Config) ->
    DataDir = ?config(data_dir, Config),
    Path = filename:join(DataDir, "bpe_metaspace.json"),
    {ok, Tok} = tok_loader:load(Path),
    bpe        = maps:get(type,             Tok),
    metaspace  = maps:get(pre_tokenizer,    Tok),
    true       = maps:get(byte_fallback,    Tok),
    true       = maps:get(add_prefix_space, Tok),
    1          = maps:get(bos_id,           Tok),
    2          = maps:get(eos_id,           Tok),
    13         = maps:size(maps:get(vocab,  Tok)).
