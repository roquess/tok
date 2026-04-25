-module(tok_bpe_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0,
         byte_to_unicode_space/1,
         byte_to_unicode_printable/1,
         byte_to_unicode_control/1,
         byte_to_unicode_high/1,
         unicode_to_byte_roundtrip/1,
         bytelevel_hello_world/1,
         bytelevel_empty/1,
         bytelevel_prefix_space/1,
         bytelevel_decode_basic/1,
         metaspace_hello_world/1,
         metaspace_add_prefix/1,
         metaspace_empty/1,
         encode_word_exact_match/1,
         encode_word_merges_applied/1,
         encode_word_byte_fallback/1,
         encode_word_no_fallback_unk/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [
    byte_to_unicode_space,
    byte_to_unicode_printable,
    byte_to_unicode_control,
    byte_to_unicode_high,
    unicode_to_byte_roundtrip,
    bytelevel_hello_world,
    bytelevel_empty,
    bytelevel_prefix_space,
    bytelevel_decode_basic,
    metaspace_hello_world,
    metaspace_add_prefix,
    metaspace_empty,
    encode_word_exact_match,
    encode_word_merges_applied,
    encode_word_byte_fallback,
    encode_word_no_fallback_unk
].

byte_to_unicode_space(_Config) ->
    288 = tok_bpe:byte_to_unicode(32).

byte_to_unicode_printable(_Config) ->
    72  = tok_bpe:byte_to_unicode(72),
    33  = tok_bpe:byte_to_unicode(33),
    126 = tok_bpe:byte_to_unicode(126).

byte_to_unicode_control(_Config) ->
    256 = tok_bpe:byte_to_unicode(0),
    257 = tok_bpe:byte_to_unicode(1),
    289 = tok_bpe:byte_to_unicode(127).

byte_to_unicode_high(_Config) ->
    290 = tok_bpe:byte_to_unicode(128),
    322 = tok_bpe:byte_to_unicode(160),
    323 = tok_bpe:byte_to_unicode(173).

unicode_to_byte_roundtrip(_Config) ->
    [B = tok_bpe:unicode_to_byte(tok_bpe:byte_to_unicode(B)) || B <- lists:seq(0, 255)],
    ok.

bytelevel_hello_world(_Config) ->
    Words = tok_bpe:pre_tokenize(bytelevel, <<"Hello world">>),
    2 = length(Words),
    <<"Hello">> = hd(Words),
    <<Gclef/utf8, "world">> = lists:nth(2, Words),
    288 = Gclef.

bytelevel_empty(_Config) ->
    [] = tok_bpe:pre_tokenize(bytelevel, <<>>).

bytelevel_prefix_space(_Config) ->
    [<<288/utf8, "Hello">>] = tok_bpe:pre_tokenize(bytelevel, <<" Hello">>).

bytelevel_decode_basic(_Config) ->
    %% Ġworld (Ġ=288=space) decodes back to raw bytes " world"
    <<32, 119, 111, 114, 108, 100>> =
        tok_bpe:bytelevel_decode(<<288/utf8, "world">>).

metaspace_hello_world(_Config) ->
    Words = tok_bpe:pre_tokenize({metaspace, false}, <<"Hello world">>),
    2 = length(Words),
    <<"Hello">> = hd(Words),
    <<"▁world"/utf8>> = lists:nth(2, Words).

metaspace_add_prefix(_Config) ->
    [<<"▁Hello"/utf8>>] = tok_bpe:pre_tokenize({metaspace, true}, <<"Hello">>).

metaspace_empty(_Config) ->
    [] = tok_bpe:pre_tokenize({metaspace, false}, <<>>).

encode_word_exact_match(_Config) ->
    Vocab  = #{<<"Hello">> => 13, <<"Gworld">> => 14},
    Merges = #{},
    [13] = tok_bpe:encode_word(<<"Hello">>, Merges, Vocab, false),
    [14] = tok_bpe:encode_word(<<"Gworld">>, Merges, Vocab, false).

encode_word_merges_applied(_Config) ->
    %% "Hello" chars: H e l l o -> merge H+e -> He, l+l -> ll, He+ll -> Hell, Hell+o -> Hello
    Vocab  = #{<<"H">> => 1, <<"e">> => 2, <<"l">> => 3, <<"o">> => 4,
               <<"He">> => 5, <<"ll">> => 6, <<"Hell">> => 7, <<"Hello">> => 8},
    Merges = #{<<"H e">> => 0, <<"l l">> => 1, <<"He ll">> => 2, <<"Hell o">> => 3},
    [8] = tok_bpe:encode_word(<<"Hello">>, Merges, Vocab, false).

encode_word_byte_fallback(_Config) ->
    %% "€" is U+20AC, UTF-8 bytes: 0xE2 0x82 0xAC
    %% With byte_fallback=true, unknown chars split into <0xNN> byte tokens
    Vocab  = #{<<"<0xe2>">> => 1, <<"<0x82>">> => 2, <<"<0xac>">> => 3},
    Merges = #{},
    [1, 2, 3] = tok_bpe:encode_word(<<226, 130, 172>>, Merges, Vocab, true).

encode_word_no_fallback_unk(_Config) ->
    %% Unknown char with byte_fallback=false: use unk_id lookup (returns -1 sentinel)
    Vocab  = #{<<"a">> => 1},
    Merges = #{},
    [-1] = tok_bpe:encode_word(<<"b">>, Merges, Vocab, false).
