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
         encode_word_no_fallback_unk/1,
         encode_bpe_bytelevel_integration/1,
         encode_bpe_metaspace_with_bos_eos/1,
         decode_bpe_bytelevel/1,
         decode_bpe_metaspace/1,
         fixture_replay_gpt2/1]).

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
    encode_word_no_fallback_unk,
    encode_bpe_bytelevel_integration,
    encode_bpe_metaspace_with_bos_eos,
    decode_bpe_bytelevel,
    decode_bpe_metaspace,
    fixture_replay_gpt2
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

encode_bpe_bytelevel_integration(_Config) ->
    Vocab  = #{<<"H">> => 1, <<"e">> => 2, <<"l">> => 3, <<"o">> => 4,
               <<"He">> => 5, <<"ll">> => 6, <<"Hell">> => 7, <<"Hello">> => 8,
               <<"Ġ"/utf8>> => 9, <<"w">> => 10, <<"r">> => 11, <<"d">> => 12,
               <<"Ġworld"/utf8>> => 13},
    Merges = #{<<"H e">> => 0, <<"l l">> => 1, <<"He ll">> => 2,
               <<"Hell o">> => 3, <<"Ġ world"/utf8>> => 4},
    Tok = #{type => bpe, vocab => Vocab,
            ids_to_tokens => maps:fold(fun(K,V,A) -> A#{V=>K} end, #{}, Vocab),
            merges => Merges, special_tokens => #{},
            normalizer => #{clean_text => false, handle_chinese_chars => false,
                            strip_accents => false, lowercase => false},
            pre_tokenizer => bytelevel, add_prefix_space => false,
            byte_fallback => false, max_length => 8, pad_id => 0,
            unk_id => -1, bos_id => none, eos_id => none},
    {IdsBin, MaskBin, TypeBin} = tok:encode(Tok, <<"Hello world">>),
    %% Expected: [8, 13, 0, 0, 0, 0, 0, 0] padded to max_length=8
    <<8:32/signed-little,  13:32/signed-little, 0:32/signed-little,
      0:32/signed-little,  0:32/signed-little,  0:32/signed-little,
      0:32/signed-little,  0:32/signed-little>>  = IdsBin,
    <<1:32/signed-little, 1:32/signed-little, 0:32/signed-little,
      0:32/signed-little, 0:32/signed-little, 0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>>   = MaskBin,
    <<0:32/signed-little, 0:32/signed-little, 0:32/signed-little,
      0:32/signed-little, 0:32/signed-little, 0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>>   = TypeBin.

encode_bpe_metaspace_with_bos_eos(_Config) ->
    Vocab  = #{<<"<unk>">> => 0, <<"<s>">> => 1, <<"</s>">> => 2,
               <<"▁"/utf8>> => 3, <<"H">> => 4, <<"e">> => 5, <<"l">> => 6,
               <<"o">> => 7, <<"▁H"/utf8>> => 8, <<"▁He"/utf8>> => 9,
               <<"▁Hell"/utf8>> => 10, <<"▁Hello"/utf8>> => 11},
    Merges = #{<<"▁ H"/utf8>> => 0, <<"▁H e"/utf8>> => 1,
               <<"▁He ll"/utf8>> => 2, <<"▁Hell o"/utf8>> => 3},
    Tok = #{type => bpe, vocab => Vocab,
            ids_to_tokens => maps:fold(fun(K,V,A) -> A#{V=>K} end, #{}, Vocab),
            merges => Merges, special_tokens => #{<<"<s>">> => 1, <<"</s>">> => 2},
            normalizer => #{clean_text => false, handle_chinese_chars => false,
                            strip_accents => false, lowercase => false},
            pre_tokenizer => metaspace, add_prefix_space => true,
            byte_fallback => true, max_length => 8, pad_id => 0,
            unk_id => 0, bos_id => 1, eos_id => 2},
    {IdsBin, MaskBin, TypeBin} = tok:encode(Tok, <<"Hello">>),
    %% Expected: [1(BOS), 11(▁Hello), 2(EOS), 0, 0, 0, 0, 0]
    <<1:32/signed-little, 11:32/signed-little, 2:32/signed-little,
      0:32/signed-little, 0:32/signed-little,  0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>>  = IdsBin,
    <<1:32/signed-little, 1:32/signed-little,  1:32/signed-little,
      0:32/signed-little, 0:32/signed-little,  0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>>  = MaskBin,
    <<0:32/signed-little, 0:32/signed-little,  0:32/signed-little,
      0:32/signed-little, 0:32/signed-little,  0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>>  = TypeBin.

decode_bpe_bytelevel(_Config) ->
    IdsToTokens = #{8 => <<"Hello">>, 13 => <<"Ġworld"/utf8>>},
    Tok = #{type => bpe, pre_tokenizer => bytelevel,
            ids_to_tokens => IdsToTokens, special_tokens => #{}},
    <<"Hello world">> = tok:decode(Tok, [8, 13]).

decode_bpe_metaspace(_Config) ->
    IdsToTokens = #{11 => <<"▁Hello"/utf8>>, 20 => <<"▁world"/utf8>>},
    Tok = #{type => bpe, pre_tokenizer => metaspace,
            ids_to_tokens => IdsToTokens, special_tokens => #{}},
    <<"Hello world">> = tok:decode(Tok, [11, 20]).

fixture_replay_gpt2(Config) ->
    ct:timetrap({seconds, 120}),
    DataDir  = ?config(data_dir, Config),
    TokPath  = filename:join([DataDir, "gpt2", "tokenizer.json"]),
    CasePath = filename:join([DataDir, "gpt2", "wordpiece_cases.json"]),
    {ok, Tok}   = tok:load(TokPath),
    {ok, Bin}   = file:read_file(CasePath),
    {ok, Cases} = thoas:decode(Bin),
    lists:foreach(fun(Case) ->
        Text     = maps:get(<<"text">>, Case),
        Expected = maps:get(<<"input_ids">>, Case),
        {IdsBin, _Mask, _Type} = tok:encode(Tok, Text),
        Got = [Id || <<Id:32/signed-little>> <= IdsBin],
        Got =:= Expected orelse
            ct:fail("GPT-2 mismatch for ~p~nExpected first 10: ~p~nGot first 10:      ~p",
                    [Text, lists:sublist(Expected, 10), lists:sublist(Got, 10)])
    end, Cases).
