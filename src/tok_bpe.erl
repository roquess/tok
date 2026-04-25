-module(tok_bpe).
-export([byte_to_unicode/1, unicode_to_byte/1,
         pre_tokenize/2,
         encode_word/4,
         bytelevel_decode/1]).

%% GPT-2 byte-to-unicode mapping.
%% Ranges 33-126, 161-172, 174-255 map to themselves.
%% Ranges 0-32 map to 256+B.
%% 127 maps to 289.
%% 128-160 map to 162+B.
%% 173 maps to 323.
byte_to_unicode(B) when B >= 33,  B =< 126 -> B;
byte_to_unicode(B) when B >= 161, B =< 172 -> B;
byte_to_unicode(B) when B >= 174, B =< 255 -> B;
byte_to_unicode(B) when B >= 0,   B =< 32  -> 256 + B;
byte_to_unicode(127)                        -> 289;
byte_to_unicode(B) when B >= 128, B =< 160 -> 162 + B;
byte_to_unicode(173)                        -> 323.

unicode_to_byte(C) when C >= 33,  C =< 126 -> C;
unicode_to_byte(C) when C >= 161, C =< 172 -> C;
unicode_to_byte(C) when C >= 174, C =< 255 -> C;
unicode_to_byte(C) when C >= 256, C =< 288 -> C - 256;
unicode_to_byte(289)                        -> 127;
unicode_to_byte(C) when C >= 290, C =< 322 -> C - 162;
unicode_to_byte(323)                        -> 173.

%% ByteLevel pre-tokenizer: map each byte to its unicode codepoint,
%% then split on G-breve (U+0120 = 288), keeping it as word prefix.
pre_tokenize(bytelevel, <<>>) -> [];
pre_tokenize(bytelevel, Text) ->
    Bytes  = binary_to_list(Text),
    Mapped = [byte_to_unicode(B) || B <- Bytes],
    split_on_marker(Mapped, 288, []);

%% Metaspace pre-tokenizer: replace spaces with U+2581 (9601),
%% optionally prepend it, then split on boundaries.
pre_tokenize({metaspace, _}, <<>>) -> [];
pre_tokenize({metaspace, AddPrefix}, Text) ->
    Chars    = unicode:characters_to_list(Text),
    Replaced = [case C of 32 -> 9601; _ -> C end || C <- Chars],
    WithPfx  = case AddPrefix of
                   true  -> [9601 | Replaced];
                   false -> Replaced
               end,
    split_on_marker(WithPfx, 9601, []).

%% Generic split: Marker starts a new word (kept as prefix of the new word).
split_on_marker([], _M, Acc) ->
    emit(Acc, []);
split_on_marker([M | Rest], M, []) ->
    %% marker at very start — begin first word with it
    split_on_marker(Rest, M, [M]);
split_on_marker([M | Rest], M, Cur) ->
    %% marker mid-stream — end current word, start new one with marker
    Word = unicode:characters_to_binary(lists:reverse(Cur)),
    split_on_marker_new(Rest, M, [M], [Word]);
split_on_marker([C | Rest], M, Cur) ->
    split_on_marker(Rest, M, [C | Cur]).

split_on_marker_new([], _M, Cur, Acc) ->
    emit(Cur, Acc);
split_on_marker_new([M | Rest], M, Cur, Acc) ->
    Word = unicode:characters_to_binary(lists:reverse(Cur)),
    split_on_marker_new(Rest, M, [M], [Word | Acc]);
split_on_marker_new([C | Rest], M, Cur, Acc) ->
    split_on_marker_new(Rest, M, [C | Cur], Acc).

emit([], Acc)  -> lists:reverse(Acc);
emit(Cur, Acc) ->
    Word = unicode:characters_to_binary(lists:reverse(Cur)),
    lists:reverse([Word | Acc]).

%% Decode a ByteLevel-encoded binary back to UTF-8.
bytelevel_decode(Bin) ->
    Chars = unicode:characters_to_list(Bin),
    list_to_binary([unicode_to_byte(C) || C <- Chars]).

%% Encode a single pre-tokenized word binary into a list of vocabulary IDs.
encode_word(Word, MergeRanks, Vocab, ByteFallback) ->
    case maps:find(Word, Vocab) of
        {ok, ID} -> [ID];
        error ->
            InitTokens = word_to_initial_tokens(Word, Vocab, ByteFallback),
            Merged     = bpe_merge(InitTokens, MergeRanks),
            [maps:get(T, Vocab, -1) || T <- Merged]
    end.

%% Split a word into its initial character tokens.
%% Unknown chars: if byte_fallback, emit <0xNN> per UTF-8 byte; else emit char as-is.
word_to_initial_tokens(Word, Vocab, ByteFallback) ->
    Chars = unicode:characters_to_list(Word),
    lists:flatmap(fun(C) ->
        ChBin = unicode:characters_to_binary([C]),
        case maps:is_key(ChBin, Vocab) of
            true                    -> [ChBin];
            false when ByteFallback ->
                [byte_token(B) || <<B>> <= ChBin];
            false                   ->
                [ChBin]
        end
    end, Chars).

byte_token(B) ->
    High = hex_digit(B bsr 4),
    Low  = hex_digit(B band 15),
    <<$<, $0, $x, High, Low, $>>>.

hex_digit(N) when N < 10 -> $0 + N;
hex_digit(N)              -> $a + N - 10.

%% Greedy BPE merge: find best pair (lowest rank), apply, repeat.
bpe_merge(Tokens, _MergeRanks) when length(Tokens) =< 1 ->
    Tokens;
bpe_merge(Tokens, MergeRanks) ->
    case find_best_pair(Tokens, MergeRanks) of
        none         -> Tokens;
        {_R, {A, B}} -> bpe_merge(do_merge(Tokens, A, B), MergeRanks)
    end.

find_best_pair(Tokens, MergeRanks) ->
    consecutive_pairs(Tokens, MergeRanks, none).

consecutive_pairs([], _MergeRanks, Best) ->
    Best;
consecutive_pairs([_], _MergeRanks, Best) ->
    Best;
consecutive_pairs([A, B | Rest], MergeRanks, Best) ->
    Key = <<A/binary, " ", B/binary>>,
    NewBest = case maps:find(Key, MergeRanks) of
        error      -> Best;
        {ok, Rank} ->
            case Best of
                none                          -> {Rank, {A, B}};
                {BestR, _} when Rank < BestR -> {Rank, {A, B}};
                _                             -> Best
            end
    end,
    consecutive_pairs([B | Rest], MergeRanks, NewBest).

do_merge([], _A, _B) -> [];
do_merge([_] = Ts, _A, _B) -> Ts;
do_merge([A, B | Rest], A, B) ->
    [<<A/binary, B/binary>> | do_merge(Rest, A, B)];
do_merge([T | Rest], A, B) ->
    [T | do_merge(Rest, A, B)].
