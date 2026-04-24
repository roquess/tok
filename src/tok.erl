-module(tok).
-export([load/1, encode/2, encode_batch/2, decode/2, vocab_size/1]).
-opaque tokenizer() :: map().
-export_type([tokenizer/0]).

load(_Path)           -> error(not_implemented).
encode(_Tok, _Text)   -> error(not_implemented).
encode_batch(_T, _Ts) -> error(not_implemented).
decode(_Tok, _Ids)    -> error(not_implemented).
vocab_size(_Tok)      -> error(not_implemented).
