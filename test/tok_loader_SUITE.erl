-module(tok_loader_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0,
         load_wordpiece/1,
         load_missing_file/1,
         load_unsupported_type/1]).

suite() -> [{timetrap, {seconds, 10}}].

all() -> [load_wordpiece, load_missing_file, load_unsupported_type].

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
