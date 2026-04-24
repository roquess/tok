-module(tok_normalizer).
-export([normalize/2, clean_text/1, handle_chinese_chars/1, nfd_strip_accents/1, lowercase/1]).

normalize(Config, Text) ->
    Steps = [
        {clean_text,           maps:get(clean_text,           Config, false), fun clean_text/1},
        {handle_chinese_chars, maps:get(handle_chinese_chars, Config, false), fun handle_chinese_chars/1},
        {nfd_strip_accents,    maps:get(strip_accents,        Config, false), fun nfd_strip_accents/1},
        {lowercase,            maps:get(lowercase,            Config, false), fun lowercase/1}
    ],
    lists:foldl(fun({_, true,  Fun}, Acc) -> Fun(Acc);
                   ({_, false, _},   Acc) -> Acc
                end, Text, Steps).

clean_text(Bin) ->
    Chars = unicode:characters_to_list(Bin),
    unicode:characters_to_binary(clean_chars(Chars, [])).

clean_chars([], Acc) -> lists:reverse(Acc);
clean_chars([C | Rest], Acc) ->
    case C of
        0       -> clean_chars(Rest, Acc);
        16#FFFD -> clean_chars(Rest, Acc);
        _ ->
            case is_whitespace(C) of
                true  -> clean_chars(Rest, [32 | Acc]);
                false ->
                    case is_control(C) of
                        true  -> clean_chars(Rest, Acc);
                        false -> clean_chars(Rest, [C | Acc])
                    end
            end
    end.

is_whitespace(C) when C =:= 32; C =:= 9; C =:= 10; C =:= 13    -> true;
is_whitespace(16#00A0)                                            -> true;
is_whitespace(_)                                                  -> false.

is_control(C) when C >= 1,   C =< 8   -> true;
is_control(C) when C >= 11,  C =< 12  -> true;
is_control(C) when C >= 14,  C =< 31  -> true;
is_control(C) when C >= 127, C =< 159 -> true;
is_control(_)                          -> false.

handle_chinese_chars(Bin) ->
    Chars = unicode:characters_to_list(Bin),
    Spaced = lists:flatmap(fun(C) ->
        case is_cjk(C) of
            true  -> [32, C, 32];
            false -> [C]
        end
    end, Chars),
    unicode:characters_to_binary(Spaced).

is_cjk(C) when C >= 16#4E00,  C =< 16#9FFF  -> true;
is_cjk(C) when C >= 16#3400,  C =< 16#4DBF  -> true;
is_cjk(C) when C >= 16#20000, C =< 16#2A6DF -> true;
is_cjk(C) when C >= 16#2A700, C =< 16#2B73F -> true;
is_cjk(C) when C >= 16#2B740, C =< 16#2B81F -> true;
is_cjk(C) when C >= 16#2B820, C =< 16#2CEAF -> true;
is_cjk(C) when C >= 16#F900,  C =< 16#FAFF  -> true;
is_cjk(C) when C >= 16#2F800, C =< 16#2FA1F -> true;
is_cjk(_)                                    -> false.

nfd_strip_accents(Bin) ->
    NfdBin = unicode:characters_to_nfd_binary(Bin),
    Chars = unicode:characters_to_list(NfdBin),
    unicode:characters_to_binary([C || C <- Chars, not is_mn(C)]).

is_mn(C) when C >= 16#0300, C =< 16#036F -> true;
is_mn(C) when C >= 16#1AB0, C =< 16#1AFF -> true;
is_mn(C) when C >= 16#1DC0, C =< 16#1DFF -> true;
is_mn(C) when C >= 16#20D0, C =< 16#20FF -> true;
is_mn(C) when C >= 16#FE20, C =< 16#FE2F -> true;
is_mn(_)                                   -> false.

lowercase(Bin) -> string:lowercase(Bin).
