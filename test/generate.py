#!/usr/bin/env python3
"""
Generate reference token ID vectors for tok conformance tests.
Requires: pip install transformers
Output: test/tok_SUITE_data/wordpiece_cases.json
"""
import json, os
from transformers import AutoTokenizer

MODEL = "bert-base-multilingual-cased"
OUT   = os.path.join(os.path.dirname(__file__), "tok_SUITE_data", "wordpiece_cases.json")

tok = AutoTokenizer.from_pretrained(MODEL)

cases = [
    "Hello world",
    "Bonjour le monde",
    "Guten Tag",
    "café résumé naïve",
    "Hello! How are you? 😊",
    " ".join(["word"] * 600),   # truncation
    "",                          # empty string
]

fixtures = []
for text in cases:
    enc = tok(text, max_length=512, padding="max_length", truncation=True)
    fixtures.append({
        "text":     text,
        "input_ids": enc["input_ids"],
        "attention_mask": enc["attention_mask"]
    })

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(fixtures, f, ensure_ascii=False, indent=2)

print(f"Written {len(fixtures)} cases to {OUT}")
