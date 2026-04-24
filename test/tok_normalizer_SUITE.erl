-module(tok_normalizer_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0,
         clean_text_removes_nul/1,
         clean_text_removes_control_char/1,
         clean_text_normalises_tab_to_space/1,
         clean_text_keeps_normal_text/1,
         chinese_chars_get_spaces/1,
         non_chinese_unchanged/1,
         nfd_strip_removes_combining_acute/1,
         nfd_strip_leaves_ascii/1,
         lowercase_ascii/1,
         lowercase_unicode/1,
         normalize_applies_pipeline/1]).

all() -> [
    clean_text_removes_nul,
    clean_text_removes_control_char,
    clean_text_normalises_tab_to_space,
    clean_text_keeps_normal_text,
    chinese_chars_get_spaces,
    non_chinese_unchanged,
    nfd_strip_removes_combining_acute,
    nfd_strip_leaves_ascii,
    lowercase_ascii,
    lowercase_unicode,
    normalize_applies_pipeline
].

clean_text_removes_nul(_Config) ->
    <<"hello">> = tok_normalizer:clean_text(<<0, "hello">>).

clean_text_removes_control_char(_Config) ->
    <<"hello">> = tok_normalizer:clean_text(<<"hello", 1>>).

clean_text_normalises_tab_to_space(_Config) ->
    <<"hello world">> = tok_normalizer:clean_text(<<"hello\tworld">>).

clean_text_keeps_normal_text(_Config) ->
    <<"Bonjour le monde">> = tok_normalizer:clean_text(<<"Bonjour le monde">>).

chinese_chars_get_spaces(_Config) ->
    Input    = unicode:characters_to_binary([16#4E2D]),
    Expected = unicode:characters_to_binary([32, 16#4E2D, 32]),
    Expected = tok_normalizer:handle_chinese_chars(Input).

non_chinese_unchanged(_Config) ->
    <<"hello">> = tok_normalizer:handle_chinese_chars(<<"hello">>).

nfd_strip_removes_combining_acute(_Config) ->
    %% U+00E9 (é) → NFD: e + U+0301 → strip U+0301 → "e"
    Input = unicode:characters_to_binary([16#00E9]),
    <<"e">> = tok_normalizer:nfd_strip_accents(Input).

nfd_strip_leaves_ascii(_Config) ->
    <<"hello">> = tok_normalizer:nfd_strip_accents(<<"hello">>).

lowercase_ascii(_Config) ->
    <<"hello world">> = tok_normalizer:lowercase(<<"Hello World">>).

lowercase_unicode(_Config) ->
    %% U+00C9 (É) → U+00E9 (é)
    Input    = unicode:characters_to_binary([16#00C9]),
    Expected = unicode:characters_to_binary([16#00E9]),
    Expected = tok_normalizer:lowercase(Input).

normalize_applies_pipeline(_Config) ->
    Config = #{clean_text => true, handle_chinese_chars => false,
               strip_accents => false, lowercase => true},
    <<"hello world">> = tok_normalizer:normalize(Config, <<"Hello\tWorld">>).
