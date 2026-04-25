-module(tok_onyx_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, suite/0, init_per_suite/1,
         embedding_norm_is_one/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [embedding_norm_is_one].

init_per_suite(Config) ->
    DataDir   = ?config(data_dir, Config),
    ModelPath = filename:join(DataDir, "model.onnx"),
    TokPath   = filename:join(DataDir, "tokenizer.json"),
    OnyxAvail = code:ensure_loaded(onyx) =:= {module, onyx},
    case {OnyxAvail, filelib:is_regular(ModelPath), filelib:is_regular(TokPath)} of
        {true, true, true} -> [{model_path, ModelPath}, {tok_path, TokPath} | Config];
        {false, _, _}      -> {skip, "onyx application not available"};
        _                  -> {skip, "model.onnx or tokenizer.json not present in data_dir"}
    end.

embedding_norm_is_one(Config) ->
    ModelPath = ?config(model_path, Config),
    TokPath   = ?config(tok_path,   Config),
    {ok, Tok}   = tok:load(TokPath),
    {ok, Model} = apply(onyx, load, [ModelPath]),
    {IdsBin, MaskBin, TypeBin} = tok:encode(Tok, <<"Bonjour le monde">>),
    {ok, #{<<"sentence_embedding">> := {EmbBin, [1, Dim], f32}}} =
        apply(onyx, run, [Model, #{
            <<"input_ids">>      => {IdsBin,  [1, 512], i32},
            <<"attention_mask">> => {MaskBin, [1, 512], i32},
            <<"token_type_ids">> => {TypeBin, [1, 512], i32}
        }]),
    Floats = apply(onyx, to_list, [{EmbBin, [1, Dim], f32}]),
    SumSq  = lists:foldl(fun(V, Acc) -> Acc + V * V end, 0.0, Floats),
    Norm   = math:sqrt(SumSq),
    true   = abs(Norm - 1.0) < 0.01,
    apply(onyx, unload, [Model]).
