-module(tok).
-export([load/1, encode/2, encode/3, encode_batch/2, decode/2, vocab_size/1, count_tokens/2]).
-opaque tokenizer() :: map().
-export_type([tokenizer/0]).

-spec load(file:filename()) -> {ok, tokenizer()} | {error, term()}.
load(Path) -> tok_loader:load(Path).

-spec encode(tokenizer(), binary()) ->
    {InputIds :: binary(), AttentionMask :: binary(), TokenTypeIds :: binary()}.
encode(Tok, Text) ->
    encode(Tok, Text, #{}).

-spec encode(tokenizer(), binary(), map()) ->
    {InputIds :: binary(), AttentionMask :: binary(), TokenTypeIds :: binary()}.
encode(Tok, Text, Opts) ->
    AddSpecial = maps:get(add_special_tokens, Opts, true),
    #{max_length := MaxLen, pad_id := PadId} = Tok,
    build_output(tokenize(Tok, Text, AddSpecial), MaxLen, PadId).

-spec count_tokens(tokenizer(), binary()) -> non_neg_integer().
count_tokens(Tok, Text) ->
    length(tokenize(Tok, Text, true)).

-spec encode_batch(tokenizer(), [binary()]) -> [{binary(), binary(), binary()}].
encode_batch(Tok, Texts) ->
    [encode(Tok, T) || T <- Texts].

-spec decode(tokenizer(), [integer()]) -> binary().
decode(#{type := wordpiece,
         ids_to_tokens := IdsToTokens, special_tokens := SpecialTokens}, Ids) ->
    SpecialIds = sets:from_list(maps:values(SpecialTokens)),
    Tokens = [maps:get(Id, IdsToTokens, <<"[UNK]">>) || Id <- Ids,
              not sets:is_element(Id, SpecialIds)],
    join_subwords(Tokens);

decode(#{type := bpe, pre_tokenizer := bytelevel,
         ids_to_tokens := IdsToTokens, special_tokens := SpecialTokens}, Ids) ->
    SpecialIds = sets:from_list(maps:values(SpecialTokens)),
    Tokens = [maps:get(Id, IdsToTokens, <<>>) || Id <- Ids,
              not sets:is_element(Id, SpecialIds)],
    tok_bpe:bytelevel_decode(iolist_to_binary(Tokens));

decode(#{type := bpe, pre_tokenizer := metaspace,
         ids_to_tokens := IdsToTokens, special_tokens := SpecialTokens}, Ids) ->
    SpecialIds = sets:from_list(maps:values(SpecialTokens)),
    Tokens = [maps:get(Id, IdsToTokens, <<>>) || Id <- Ids,
              not sets:is_element(Id, SpecialIds)],
    Concat = iolist_to_binary(Tokens),
    Result = binary:replace(Concat, <<"▁"/utf8>>, <<" ">>, [global]),
    case Result of
        <<" ", Rest/binary>> -> Rest;
        _                    -> Result
    end.

-spec vocab_size(tokenizer()) -> integer().
vocab_size(#{vocab := Vocab}) -> maps:size(Vocab).

%% Internal

tokenize(#{type := wordpiece,
           vocab := Vocab, normalizer := Norm,
           max_length := MaxLen, unk_id := UnkId,
           cls_id := ClsId, sep_id := SepId,
           max_chars_per_word := MaxChars}, Text, AddSpecial) ->
    Normalized = tok_normalizer:normalize(Norm, Text),
    Words      = tok_wordpiece:pre_tokenize(Normalized),
    ContentIds = tok_wordpiece:encode_words(Words, Vocab, UnkId, MaxChars),
    case AddSpecial of
        true ->
            Truncated = lists:sublist(ContentIds, MaxLen - 2),
            [ClsId | Truncated] ++ [SepId];
        false ->
            lists:sublist(ContentIds, MaxLen)
    end;

tokenize(#{type := bpe,
           vocab := Vocab, merges := MergeRanks, normalizer := Norm,
           pre_tokenizer := PreTok, add_prefix_space := AddPrefix,
           byte_fallback := ByteFallback, max_length := MaxLen,
           unk_id := UnkId, bos_id := BosId, eos_id := EosId}, Text, AddSpecial) ->
    Normalized = tok_normalizer:normalize(Norm, Text),
    PreTokSpec = case PreTok of
                     bytelevel -> bytelevel;
                     metaspace -> {metaspace, AddPrefix}
                 end,
    Words      = tok_bpe:pre_tokenize(PreTokSpec, Normalized),
    RawIds     = lists:flatmap(
                   fun(W) -> tok_bpe:encode_word(W, MergeRanks, Vocab, ByteFallback) end,
                   Words),
    ContentIds = [case Id of -1 -> UnkId; _ -> Id end || Id <- RawIds],
    case AddSpecial of
        true ->
            BosIds    = case BosId of none -> []; BosI -> [BosI] end,
            EosIds    = case EosId of none -> []; EosI -> [EosI] end,
            ExtraLen  = length(BosIds) + length(EosIds),
            Truncated = lists:sublist(ContentIds, MaxLen - ExtraLen),
            BosIds ++ Truncated ++ EosIds;
        false ->
            lists:sublist(ContentIds, MaxLen)
    end.

build_output(Ids, MaxLen, PadId) ->
    RealLen  = length(Ids),
    PadCount = MaxLen - RealLen,
    AllIds   = Ids ++ lists:duplicate(PadCount, PadId),
    IdsBin   = << <<Id:32/signed-little>> || Id <- AllIds >>,
    MaskReal = binary:copy(<<1:32/signed-little>>, RealLen),
    MaskPad  = binary:copy(<<0:32/signed-little>>, PadCount),
    MaskBin  = <<MaskReal/binary, MaskPad/binary>>,
    TypeBin  = binary:copy(<<0:32/signed-little>>, MaxLen),
    {IdsBin, MaskBin, TypeBin}.

join_subwords([]) -> <<>>;
join_subwords([First | Rest]) ->
    lists:foldl(fun(<<"##", Sub/binary>>, Acc) -> <<Acc/binary, Sub/binary>>;
                   (T,                   Acc)  -> <<Acc/binary, " ", T/binary>>
                end, First, Rest).
