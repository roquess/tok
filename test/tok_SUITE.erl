-module(tok_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0,
         encode_hello_world/1,
         encode_truncates/1,
         encode_batch/1,
         decode_removes_specials/1,
         vocab_size/1,
         fixture_replay/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [encode_hello_world, encode_truncates, encode_batch,
          decode_removes_specials, vocab_size, fixture_replay].

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
