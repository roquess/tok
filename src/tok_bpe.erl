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

%% BPE merge: stub — Task 3 will implement this.
encode_word(_Word, _MergeRanks, _Vocab, _ByteFallback) ->
    error(not_implemented).
