-module(tok_bpe_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0,
         byte_to_unicode_space/1,
         byte_to_unicode_printable/1,
         byte_to_unicode_control/1,
         unicode_to_byte_roundtrip/1,
         bytelevel_hello_world/1,
         bytelevel_empty/1,
         bytelevel_prefix_space/1,
         metaspace_hello_world/1,
         metaspace_add_prefix/1,
         metaspace_empty/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [
    byte_to_unicode_space,
    byte_to_unicode_printable,
    byte_to_unicode_control,
    unicode_to_byte_roundtrip,
    bytelevel_hello_world,
    bytelevel_empty,
    bytelevel_prefix_space,
    metaspace_hello_world,
    metaspace_add_prefix,
    metaspace_empty
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

metaspace_hello_world(_Config) ->
    Words = tok_bpe:pre_tokenize({metaspace, false}, <<"Hello world">>),
    2 = length(Words),
    <<"Hello">> = hd(Words),
    <<"▁world"/utf8>> = lists:nth(2, Words).

metaspace_add_prefix(_Config) ->
    [<<"▁Hello"/utf8>>] = tok_bpe:pre_tokenize({metaspace, true}, <<"Hello">>).

metaspace_empty(_Config) ->
    [] = tok_bpe:pre_tokenize({metaspace, false}, <<>>).
