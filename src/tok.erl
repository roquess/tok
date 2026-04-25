-module(tok).
-export([load/1, encode/2, encode_batch/2, decode/2, vocab_size/1]).
-opaque tokenizer() :: map().
-export_type([tokenizer/0]).

-spec load(file:filename()) -> {ok, tokenizer()} | {error, term()}.
load(Path) -> tok_loader:load(Path).

-spec encode(tokenizer(), binary()) ->
    {InputIds :: binary(), AttentionMask :: binary(), TokenTypeIds :: binary()}.
encode(#{type := wordpiece,
         vocab := Vocab, normalizer := Norm,
         max_length := MaxLen, pad_id := PadId,
         unk_id := UnkId, cls_id := ClsId, sep_id := SepId,
         max_chars_per_word := MaxChars}, Text) ->
    % pre_tokenizer dispatch is not yet consulted — only BertPreTokenizer
    % is supported; wire up whitespace/other dispatch when adding v0.2 BPE
    Normalized  = tok_normalizer:normalize(Norm, Text),
    Words       = tok_wordpiece:pre_tokenize(Normalized),
    ContentIds  = tok_wordpiece:encode_words(Words, Vocab, UnkId, MaxChars),
    Truncated   = lists:sublist(ContentIds, MaxLen - 2),
    AllIds      = [ClsId | Truncated] ++ [SepId],
    build_output(AllIds, MaxLen, PadId);
encode(#{type := bpe}, _Text) ->
    error({not_implemented, bpe}).

-spec encode_batch(tokenizer(), [binary()]) -> [{binary(), binary(), binary()}].
encode_batch(Tok, Texts) ->
    [encode(Tok, T) || T <- Texts].

-spec decode(tokenizer(), [integer()]) -> binary().
decode(#{ids_to_tokens := IdsToTokens, special_tokens := SpecialTokens}, Ids) ->
    SpecialIds = sets:from_list(maps:values(SpecialTokens)),
    Tokens = [maps:get(Id, IdsToTokens, <<"[UNK]">>) || Id <- Ids,
              not sets:is_element(Id, SpecialIds)],
    join_subwords(Tokens).

-spec vocab_size(tokenizer()) -> integer().
vocab_size(#{vocab := Vocab}) -> maps:size(Vocab).

%% Internal

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
