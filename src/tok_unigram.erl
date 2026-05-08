-module(tok_unigram).
-export([encode/3]).

%% Encode a pre-tokenized word binary into a list of vocab IDs using Viterbi.
-spec encode(binary(), #{binary() => float()}, #{binary() => integer()}) -> [integer()].
encode(Word, VocabScores, Vocab) ->
    CharList = to_chars(Word),
    N        = length(CharList),
    case N of
        0 -> [];
        _ ->
            Dp = fill_dp(1, N, CharList, VocabScores, #{0 => {0.0, 0}}),
            backtrack(N, Dp, CharList, Vocab)
    end.

%% Convert a UTF-8 binary to a list of single-codepoint binaries.
to_chars(<<>>) -> [];
to_chars(<<C/utf8, Rest/binary>>) ->
    [<<C/utf8>> | to_chars(Rest)].

%% Fill DP table. dp[i] = {best_score, predecessor_position_j}.
%% Position 0 = before first char, position i = after i-th char (1-indexed).
fill_dp(I, N, _CL, _VS, Dp) when I > N -> Dp;
fill_dp(I, N, CL, VS, Dp) ->
    Best  = try_j(0, I, CL, VS, Dp, none),
    Entry = case Best of
        none   -> {-1.0e10, I - 1};   % no match: advance one char (will become unk)
        {_,_}  -> Best
    end,
    fill_dp(I + 1, N, CL, VS, Dp#{I => Entry}).

%% Try every split point j in [0, I) and return {best_score, best_j}.
try_j(J, I, _CL, _VS, _Dp, Best) when J >= I -> Best;
try_j(J, I, CL, VS, Dp, Best) ->
    case maps:find(J, Dp) of
        error ->
            try_j(J + 1, I, CL, VS, Dp, Best);
        {ok, {PrevScore, _}} ->
            Tok = substr(CL, J, I),
            case maps:find(Tok, VS) of
                error ->
                    try_j(J + 1, I, CL, VS, Dp, Best);
                {ok, Score} ->
                    Total   = PrevScore + Score,
                    NewBest = case Best of
                        none                          -> {Total, J};
                        {BestSc, _} when Total > BestSc -> {Total, J};
                        _                             -> Best
                    end,
                    try_j(J + 1, I, CL, VS, Dp, NewBest)
            end
    end.

%% Backtrack through the DP table and return token IDs in forward order.
backtrack(I, Dp, CL, Vocab) ->
    lists:reverse(backtrack_rev(I, Dp, CL, Vocab, [])).

backtrack_rev(0, _Dp, _CL, _Vocab, Acc) -> Acc;
backtrack_rev(I, Dp,  CL, Vocab, Acc) ->
    {_Score, J} = maps:get(I, Dp),
    Tok = substr(CL, J, I),
    Id  = maps:get(Tok, Vocab, maps:get(<<"<unk>">>, Vocab, 0)),
    backtrack_rev(J, Dp, CL, Vocab, [Id | Acc]).

%% Extract chars from exclusive position J to inclusive position I (both 0-indexed).
%% CharList is 1-indexed in Erlang list terms, so chars at positions J+1..I.
substr(CL, J, I) ->
    iolist_to_binary(lists:sublist(CL, J + 1, I - J)).
