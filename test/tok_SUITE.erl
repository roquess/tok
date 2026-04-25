-module(tok_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0,
         encode_hello_world/1,
         encode_truncates/1,
         encode_batch/1,
         decode_removes_specials/1,
         vocab_size/1,
         fixture_replay/1,
         encode_no_special_tokens_wordpiece/1,
         encode_no_special_tokens_bpe/1,
         count_tokens_wordpiece/1,
         count_tokens_truncation/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [encode_hello_world, encode_truncates, encode_batch,
          decode_removes_specials, vocab_size, fixture_replay,
          encode_no_special_tokens_wordpiece, encode_no_special_tokens_bpe,
          count_tokens_wordpiece, count_tokens_truncation].

encode_hello_world(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    %% max_length=8, [CLS]=101, hello=200, world=201, [SEP]=102, [PAD]=0
    {IdsBin, MaskBin, TypeBin} = tok:encode(Tok, <<"hello world">>),
    <<101:32/signed-little, 200:32/signed-little, 201:32/signed-little,
      102:32/signed-little, 0:32/signed-little,   0:32/signed-little,
      0:32/signed-little,   0:32/signed-little>>   = IdsBin,
    <<1:32/signed-little, 1:32/signed-little, 1:32/signed-little,
      1:32/signed-little, 0:32/signed-little, 0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>>      = MaskBin,
    TypeBin = binary:copy(<<0:32/signed-little>>, 8).

encode_truncates(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    {IdsBin, _MaskBin, _TypeBin} = tok:encode(Tok, <<"hello world hello world hello world">>),
    %% max_length=8 → 8*4 = 32 bytes total, always
    <<101:32/signed-little, _Rest/binary>> = IdsBin,
    32 = byte_size(IdsBin).

encode_batch(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    Results = tok:encode_batch(Tok, [<<"hello">>, <<"world">>]),
    2 = length(Results),
    [{Ids1, _, _}, {Ids2, _, _}] = Results,
    32 = byte_size(Ids1),
    32 = byte_size(Ids2).

decode_removes_specials(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    %% [CLS]=101, hello=200, world=201, ##s=202, [SEP]=102
    <<"hello worlds">> = tok:decode(Tok, [101, 200, 201, 202, 102]).

vocab_size(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    7 = tok:vocab_size(Tok).

fixture_replay(Config) ->
    DataDir = ?config(data_dir, Config),
    %% Directory name must match MODEL constant in test/generate.py
    TokPath  = filename:join([DataDir, "bert-base-multilingual-cased", "tokenizer.json"]),
    {ok, Tok} = tok:load(TokPath),
    CasesPath = filename:join(DataDir, "wordpiece_cases.json"),
    {ok, Bin}  = file:read_file(CasesPath),
    {ok, Cases} = thoas:decode(Bin),
    lists:foreach(fun(Case) ->
        Text     = maps:get(<<"text">>, Case),
        Expected = maps:get(<<"input_ids">>, Case),
        {IdsBin, _Mask, _Type} = tok:encode(Tok, Text),
        Got = [Id || <<Id:32/signed-little>> <= IdsBin],
        case Got =:= Expected of
            true  -> ok;
            false ->
                ct:fail("Mismatch for ~p~nExpected: ~p~nGot:      ~p",
                        [Text, lists:sublist(Expected, 10), lists:sublist(Got, 10)])
        end
    end, Cases).

encode_no_special_tokens_wordpiece(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    {IdsBin, MaskBin, _} = tok:encode(Tok, <<"hello world">>, #{add_special_tokens => false}),
    Ids  = [Id  || <<Id:32/signed-little>>  <= IdsBin],
    Mask = [M   || <<M:32/signed-little>>   <= MaskBin],
    %% Without CLS/SEP: first real token is "hello" not [CLS]
    %% Mask should have 1s for real tokens only
    false = (hd(Ids) =:= 101),         %% 101 is [CLS] — must NOT be first
    true  = (hd(Ids) =/= 0),           %% first token must be real
    1     = hd(Mask).                  %% attention mask starts with 1

encode_no_special_tokens_bpe(_Config) ->
    %% Build a minimal BPE tokenizer map directly (no file needed)
    Vocab  = #{<<"H">> => 1, <<"e">> => 2, <<"l">> => 3, <<"o">> => 4,
               <<"He">> => 5, <<"ll">> => 6, <<"Hell">> => 7, <<"Hello">> => 8,
               <<"Ġ"/utf8>> => 9, <<"w">> => 10, <<"r">> => 11, <<"d">> => 12,
               <<"Ġworld"/utf8>> => 13, <<"<s>">> => 100, <<"</s>">> => 101},
    Merges = #{<<"H e">> => 0, <<"l l">> => 1, <<"He ll">> => 2,
               <<"Hell o">> => 3, <<"Ġ world"/utf8>> => 4},
    Tok = #{type => bpe, vocab => Vocab,
            ids_to_tokens => maps:fold(fun(K,V,A) -> A#{V=>K} end, #{}, Vocab),
            merges => Merges, special_tokens => #{<<"<s>">> => 100, <<"</s>">> => 101},
            normalizer => #{clean_text => false, handle_chinese_chars => false,
                            strip_accents => false, lowercase => false},
            pre_tokenizer => bytelevel, add_prefix_space => false,
            byte_fallback => false, max_length => 8, pad_id => 0,
            unk_id => -1, bos_id => 100, eos_id => 101},
    %% With add_special_tokens=false: no BOS/EOS, just [8, 13] padded to 8
    {IdsBin, _, _} = tok:encode(Tok, <<"Hello world">>, #{add_special_tokens => false}),
    <<8:32/signed-little, 13:32/signed-little, 0:32/signed-little,
      0:32/signed-little, 0:32/signed-little,  0:32/signed-little,
      0:32/signed-little, 0:32/signed-little>> = IdsBin.

count_tokens_wordpiece(Config) ->
    DataDir = ?config(data_dir, Config),
    {ok, Tok} = tok:load(filename:join(DataDir, "minimal_tokenizer.json")),
    N = tok:count_tokens(Tok, <<"hello world">>),
    %% "hello world" -> [CLS] hello world [SEP] = 4 tokens
    4 = N.

count_tokens_truncation(_Config) ->
    %% Build a minimal wordpiece tokenizer with max_length=4
    Vocab  = #{<<"[PAD]">> => 0, <<"[UNK]">> => 100, <<"[CLS]">> => 101,
               <<"[SEP]">> => 102, <<"hello">> => 200, <<"world">> => 201,
               <<"foo">> => 202, <<"bar">> => 203, <<"baz">> => 204},
    Tok = #{type => wordpiece, vocab => Vocab,
            ids_to_tokens => maps:fold(fun(K,V,A) -> A#{V=>K} end, #{}, Vocab),
            special_tokens => #{<<"[CLS]">> => 101, <<"[SEP]">> => 102},
            normalizer => #{clean_text => false, handle_chinese_chars => false,
                            strip_accents => false, lowercase => false},
            pre_tokenizer => bert,
            max_length => 4, pad_id => 0,
            unk_id => 100, cls_id => 101, sep_id => 102,
            max_chars_per_word => 100},
    %% "hello world foo bar baz" has 5 content tokens; max_length=4 means
    %% [CLS] + 2 content tokens + [SEP] = 4 real tokens
    4 = tok:count_tokens(Tok, <<"hello world foo bar baz">>).
