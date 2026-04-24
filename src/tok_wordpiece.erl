-module(tok_wordpiece).
-export([pre_tokenize/1, encode_words/4]).

pre_tokenize(<<>>) -> [];
pre_tokenize(Bin) ->
    Chars = unicode:characters_to_list(Bin),
    Tokens = split_chars(Chars, [], []),
    [unicode:characters_to_binary(T) || T <- Tokens, T =/= []].

split_chars([], Cur, Acc) ->
    lists:reverse(drop_empty([lists:reverse(Cur) | Acc]));
split_chars([C | Rest], Cur, Acc) ->
    case is_whitespace(C) of
        true ->
            split_chars(Rest, [], drop_empty([lists:reverse(Cur) | Acc]));
        false ->
            case is_punctuation(C) of
                true ->
                    split_chars(Rest, [], [[C] | drop_empty([lists:reverse(Cur) | Acc])]);
                false ->
                    split_chars(Rest, [C | Cur], Acc)
            end
    end.

drop_empty(L) -> [T || T <- L, T =/= []].

is_whitespace(C) when C =:= 32; C =:= 9; C =:= 10; C =:= 13 -> true;
is_whitespace(160)                                             -> true;
is_whitespace(_)                                               -> false.

is_punctuation(C) when C >= 33,      C =< 47     -> true;
is_punctuation(C) when C >= 58,      C =< 64     -> true;
is_punctuation(C) when C >= 91,      C =< 96     -> true;
is_punctuation(C) when C >= 123,     C =< 126    -> true;
is_punctuation(C) when C >= 16#00A1, C =< 16#00BF -> true;  %% Latin-1 punct: «»¡¿·§¶
is_punctuation(C) when C >= 16#2010, C =< 16#205E -> true;  %% General Punctuation: dashes, quotes, ellipsis
is_punctuation(C) when C >= 16#2E00, C =< 16#2E7F -> true;  %% Supplemental Punctuation
is_punctuation(_)                                  -> false.

encode_words(Words, Vocab, UnkId, MaxChars) ->
    lists:flatmap(fun(W) -> encode_word(W, Vocab, UnkId, MaxChars) end, Words).

encode_word(Word, Vocab, UnkId, MaxChars) ->
    Chars = unicode:characters_to_list(Word),
    Len = length(Chars),
    case Len > MaxChars of
        true -> [UnkId];
        false ->
            case greedy(Chars, 0, Len, Vocab, []) of
                {ok, Ids} -> Ids;
                error     -> [UnkId]
            end
    end.

greedy(_Chars, Start, Total, _Vocab, Acc) when Start >= Total ->
    {ok, lists:reverse(Acc)};
greedy(Chars, Start, Total, Vocab, Acc) ->
    case longest(Chars, Total, Start, Vocab) of
        not_found    -> error;
        {Id, NewEnd} -> greedy(Chars, NewEnd, Total, Vocab, [Id | Acc])
    end.

longest(_Chars, End, Start, _Vocab) when End =< Start -> not_found;
longest(Chars, End, Start, Vocab) ->
    Sub = lists:sublist(Chars, Start + 1, End - Start),
    SubBin = unicode:characters_to_binary(Sub),
    Key = case Start of
        0 -> SubBin;
        _ -> <<"##", SubBin/binary>>
    end,
    case maps:find(Key, Vocab) of
        {ok, Id} -> {Id, End};
        error    -> longest(Chars, End - 1, Start, Vocab)
    end.
