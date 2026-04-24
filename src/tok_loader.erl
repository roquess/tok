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
                error       -> {error, {missing_field, <<"model.type">>}};
                {ok, <<"WordPiece">>} -> build_wordpiece(Json, Model);
                {ok, <<"BPE">>}      -> build_bpe(Json, Model);
                {ok, T}              -> {error, {unsupported_tokenizer, T}}
            end
    end.

build_wordpiece(Json, Model) ->
    case maps:find(<<"vocab">>, Model) of
        error         -> {error, {missing_field, <<"model.vocab">>}};
        {ok, VocabMap} ->
            Vocab        = maps:fold(fun(T, Id, A) -> A#{T => Id} end, #{}, VocabMap),
            IdsToTokens  = maps:fold(fun(T, Id, A) -> A#{Id => T} end, #{}, Vocab),
            UnkToken     = maps:get(<<"unk_token">>, Model, <<"[UNK]">>),
            {ok, #{
                type               => wordpiece,
                vocab              => Vocab,
                ids_to_tokens      => IdsToTokens,
                special_tokens     => extract_special_tokens(Vocab),
                normalizer         => parse_normalizer(maps:get(<<"normalizer">>, Json, null)),
                pre_tokenizer      => parse_pre_tokenizer(maps:get(<<"pre_tokenizer">>, Json, null)),
                max_length         => parse_max_length(Json),
                pad_id             => parse_pad_id(Json, Vocab),
                unk_id             => maps:get(UnkToken, Vocab, 100),
                cls_id             => maps:get(<<"[CLS]">>, Vocab, 101),
                sep_id             => maps:get(<<"[SEP]">>, Vocab, 102),
                max_chars_per_word => maps:get(<<"max_input_chars_per_word">>, Model, 100)
            }}
    end.

build_bpe(_Json, _Model) ->
    {error, {unsupported_tokenizer, <<"BPE">>}}.

extract_special_tokens(Vocab) ->
    Keys = [<<"[PAD]">>, <<"[UNK]">>, <<"[CLS]">>, <<"[SEP]">>, <<"[MASK]">>],
    maps:filter(fun(K, _) -> lists:member(K, Keys) end, Vocab).

parse_normalizer(null) ->
    #{clean_text => false, handle_chinese_chars => false,
      strip_accents => false, lowercase => false};
parse_normalizer(#{<<"type">> := <<"BertNormalizer">>} = N) ->
    #{clean_text           => maps:get(<<"clean_text">>,           N, false),
      handle_chinese_chars => maps:get(<<"handle_chinese_chars">>, N, false),
      strip_accents        => null_to_false(maps:get(<<"strip_accents">>, N, null)),
      lowercase            => maps:get(<<"lowercase">>,            N, false)};
parse_normalizer(#{<<"type">> := T}) ->
    #{clean_text => false, handle_chinese_chars => false,
      strip_accents => false, lowercase => false,
      unsupported => T}.

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
