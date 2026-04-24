-module(tok_wordpiece_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0,
         pre_tokenize_whitespace/1,
         pre_tokenize_punctuation/1,
         pre_tokenize_multi_space/1,
         pre_tokenize_empty/1,
         encode_exact_match/1,
         encode_subword/1,
         encode_unknown/1,
         encode_too_long_word/1]).

all() -> [
    pre_tokenize_whitespace,
    pre_tokenize_punctuation,
    pre_tokenize_multi_space,
    pre_tokenize_empty,
    encode_exact_match,
    encode_subword,
    encode_unknown,
    encode_too_long_word
].

pre_tokenize_whitespace(_Config) ->
    [<<"hello">>, <<"world">>] = tok_wordpiece:pre_tokenize(<<"hello world">>).

pre_tokenize_punctuation(_Config) ->
    [<<"hello">>, <<",">>, <<"world">>] = tok_wordpiece:pre_tokenize(<<"hello,world">>).

pre_tokenize_multi_space(_Config) ->
    [<<"hello">>, <<"world">>] = tok_wordpiece:pre_tokenize(<<"hello  world">>).

pre_tokenize_empty(_Config) ->
    [] = tok_wordpiece:pre_tokenize(<<>>).

encode_exact_match(_Config) ->
    Vocab = #{<<"hello">> => 1, <<"world">> => 2},
    [1, 2] = tok_wordpiece:encode_words([<<"hello">>, <<"world">>], Vocab, 100, 100).

encode_subword(_Config) ->
    %% "hello" splits into "hel" + "##lo"
    Vocab = #{<<"hel">> => 1, <<"##lo">> => 2, <<"world">> => 3},
    [1, 2, 3] = tok_wordpiece:encode_words([<<"hello">>, <<"world">>], Vocab, 100, 100).

encode_unknown(_Config) ->
    Vocab = #{<<"hello">> => 1},
    [100] = tok_wordpiece:encode_words([<<"xyz">>], Vocab, 100, 100).

encode_too_long_word(_Config) ->
    %% max_chars_per_word=1, "ab" has 2 chars -> UNK
    Vocab = #{<<"ab">> => 1},
    [100] = tok_wordpiece:encode_words([<<"ab">>], Vocab, 100, 1).
