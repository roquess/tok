-module(tok_loader).
-export([load/1]).

load(Path) ->
    case file:read_file(Path) of
        {error, _}   -> {error, bad_file};
        {ok, Bin}    ->
            case thoas:decode(Bin) of
                {error, Reason} -> {error, {parse_failed, Reason}};
                {ok, Json}      -> build(Json)
            end
    end.

build(Json) ->
    case maps:find(<<"model">>, Json) of
        error         -> {error, {missing_field, <<"model">>}};
        {ok, Model}   ->
            case maps:find(<<"type">>, Model) of
                error                -> {error, {missing_field, <<"model.type">>}};
                {ok, <<"WordPiece">>} -> build_wordpiece(Json, Model);
                {ok, <<"BPE">>}      -> build_bpe(Json, Model);
                {ok, T}              -> {error, {unsupported_tokenizer, T}}
            end
    end.

build_wordpiece(Json, Model) ->
    case maps:find(<<"vocab">>, Model) of
        error          -> {error, {missing_field, <<"model.vocab">>}};
        {ok, VocabMap} ->
            Vocab       = VocabMap,
            IdsToTokens = maps:fold(fun(T, Id, A) -> A#{Id => T} end, #{}, Vocab),
            UnkToken    = maps:get(<<"unk_token">>, Model, <<"[UNK]">>),
            case parse_normalizer(maps:get(<<"normalizer">>, Json, null)) of
                {error, _} = Err -> Err;
                {ok, Norm}       ->
                    {ok, #{
                        type               => wordpiece,
                        vocab              => Vocab,
                        ids_to_tokens      => IdsToTokens,
                        special_tokens     => extract_special_tokens(Vocab),
                        normalizer         => Norm,
                        pre_tokenizer      => parse_pre_tokenizer(maps:get(<<"pre_tokenizer">>, Json, null)),
                        max_length         => parse_max_length(Json),
                        pad_id             => parse_pad_id(Json, Vocab),
                        unk_id             => maps:get(UnkToken, Vocab, 100),
                        cls_id             => maps:get(<<"[CLS]">>, Vocab, 101),
                        sep_id             => maps:get(<<"[SEP]">>, Vocab, 102),
                        max_chars_per_word => maps:get(<<"max_input_chars_per_word">>, Model, 100)
                    }}
            end
    end.

build_bpe(Json, Model) ->
    case maps:find(<<"vocab">>, Model) of
        error          -> {error, {missing_field, <<"model.vocab">>}};
        {ok, VocabMap} ->
            case maps:find(<<"merges">>, Model) of
                error           -> {error, {missing_field, <<"model.merges">>}};
                {ok, MergeList} ->
                    Vocab        = VocabMap,
                    IdsToTokens  = maps:fold(fun(T, Id, A) -> A#{Id => T} end, #{}, Vocab),
                    MergeRanks   = build_merge_ranks(MergeList),
                    ByteFallback = maps:get(<<"byte_fallback">>, Model, false),
                    UnkToken     = maps:get(<<"unk_token">>, Model, null),
                    UnkId        = case UnkToken of
                                       null -> -1;
                                       T    -> maps:get(T, Vocab, -1)
                                   end,
                    PostProcessor       = maps:get(<<"post_processor">>, Json, null),
                    {PreTok, AddPrefix} = parse_pre_tokenizer_bpe(
                                            maps:get(<<"pre_tokenizer">>, Json, null)),
                    {BosId, EosId}      = parse_bos_eos(PostProcessor, Vocab),
                    case parse_normalizer(maps:get(<<"normalizer">>, Json, null)) of
                        {error, _} = Err -> Err;
                        {ok, Norm}       ->
                            {ok, #{
                                type             => bpe,
                                vocab            => Vocab,
                                ids_to_tokens    => IdsToTokens,
                                merges           => MergeRanks,
                                special_tokens   => extract_bpe_special_tokens(PostProcessor, Vocab),
                                normalizer       => Norm,
                                pre_tokenizer    => PreTok,
                                add_prefix_space => AddPrefix,
                                byte_fallback    => ByteFallback,
                                max_length       => parse_max_length(Json),
                                pad_id           => parse_pad_id(Json, Vocab),
                                unk_id           => UnkId,
                                bos_id           => BosId,
                                eos_id           => EosId
                            }}
                    end
            end
    end.

build_merge_ranks(MergeList) ->
    maps:from_list([{Merge, Rank}
                    || {Rank, Merge} <- lists:zip(
                           lists:seq(0, length(MergeList) - 1), MergeList)]).

parse_pre_tokenizer_bpe(null) ->
    {bytelevel, false};
parse_pre_tokenizer_bpe(#{<<"type">> := <<"ByteLevel">>} = P) ->
    {bytelevel, maps:get(<<"add_prefix_space">>, P, false)};
parse_pre_tokenizer_bpe(#{<<"type">> := <<"Metaspace">>} = P) ->
    Default = case maps:is_key(<<"prepend_scheme">>, P) of
                  true  -> true;
                  false -> false
              end,
    AddPrefix = maps:get(<<"add_prefix_space">>, P, Default),
    {metaspace, AddPrefix};
parse_pre_tokenizer_bpe(_) ->
    {bytelevel, false}.

parse_bos_eos(null, _Vocab) ->
    {none, none};
parse_bos_eos(#{<<"type">>   := <<"TemplateProcessing">>,
                <<"single">> := Single}, Vocab) ->
    Parts    = binary:split(Single, <<" ">>, [global]),
    SpecToks = [strip_type_suffix(P) || P <- Parts, not is_seq_var(P)],
    BosId    = case SpecToks of
                   [First | _] -> maps:get(First, Vocab, none);
                   []          -> none
               end,
    EosId    = case length(SpecToks) >= 2 of
                   true  -> maps:get(lists:last(SpecToks), Vocab, none);
                   false -> none
               end,
    {BosId, EosId};
parse_bos_eos(_, _Vocab) ->
    {none, none}.

is_seq_var(<<"$A", _/binary>>) -> true;
is_seq_var(<<"$B", _/binary>>) -> true;
is_seq_var(_)                  -> false.

strip_type_suffix(Token) ->
    case binary:split(Token, <<":">>) of
        [T, _] -> T;
        [T]    -> T
    end.

extract_special_tokens(Vocab) ->
    Keys = [<<"[PAD]">>, <<"[UNK]">>, <<"[CLS]">>, <<"[SEP]">>, <<"[MASK]">>],
    maps:filter(fun(K, _) -> lists:member(K, Keys) end, Vocab).

extract_bpe_special_tokens(null, _Vocab) ->
    #{};
extract_bpe_special_tokens(#{<<"special_tokens">> := SpecMap}, Vocab) when is_map(SpecMap) ->
    Keys = maps:keys(SpecMap),
    maps:filter(fun(K, _) -> lists:member(K, Keys) end, Vocab);
extract_bpe_special_tokens(_, _Vocab) ->
    #{}.

parse_normalizer(null) ->
    {ok, #{clean_text => false, handle_chinese_chars => false,
           strip_accents => false, lowercase => false}};
parse_normalizer(#{<<"type">> := <<"BertNormalizer">>} = N) ->
    {ok, #{clean_text           => maps:get(<<"clean_text">>,           N, false),
           handle_chinese_chars => maps:get(<<"handle_chinese_chars">>, N, false),
           strip_accents        => null_to_false(maps:get(<<"strip_accents">>, N, null)),
           lowercase            => maps:get(<<"lowercase">>,            N, false)}};
parse_normalizer(#{<<"type">> := <<"NFC">>}) ->
    {ok, #{clean_text => false, handle_chinese_chars => false,
           strip_accents => false, lowercase => false}};
parse_normalizer(#{<<"type">> := <<"Prepend">>}) ->
    {ok, #{clean_text => false, handle_chinese_chars => false,
           strip_accents => false, lowercase => false}};
parse_normalizer(#{<<"type">> := T}) ->
    {error, {unsupported_normalizer, T}}.

parse_pre_tokenizer(null)                                      -> bert;
parse_pre_tokenizer(#{<<"type">> := <<"BertPreTokenizer">>})   -> bert;
parse_pre_tokenizer(#{<<"type">> := <<"Whitespace">>})         -> whitespace;
parse_pre_tokenizer(_)                                         -> bert.

parse_max_length(Json) ->
    case maps:find(<<"truncation">>, Json) of
        {ok, T} when is_map(T) -> maps:get(<<"max_length">>, T, 512);
        _                      -> 512
    end.

parse_pad_id(Json, Vocab) ->
    case maps:find(<<"padding">>, Json) of
        {ok, P} when is_map(P) -> maps:get(<<"pad_id">>, P, 0);
        _                      -> maps:get(<<"[PAD]">>, Vocab, 0)
    end.

null_to_false(null)  -> false;
null_to_false(true)  -> true;
null_to_false(false) -> false.
