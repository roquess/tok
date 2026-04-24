-module(tok_normalizer).
-export([normalize/2, clean_text/1, handle_chinese_chars/1, nfd_strip_accents/1, lowercase/1]).

normalize(_Config, _Text)   -> error(not_implemented).
clean_text(_Text)            -> error(not_implemented).
handle_chinese_chars(_Text)  -> error(not_implemented).
nfd_strip_accents(_Text)     -> error(not_implemented).
lowercase(_Text)             -> error(not_implemented).
