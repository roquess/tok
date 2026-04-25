#!/usr/bin/env python3
"""Generate reference token ID vectors for tok BPE conformance tests."""
import json, os
from transformers import AutoTokenizer

CASES = [
    "Hello world",
    "Bonjour le monde",
    "Guten Tag",
    "Hello! How are you? \U0001f60a",
    " ".join(["word"] * 600),
    "",
]

def generate(model_id, out_dir, max_length=512):
    os.makedirs(out_dir, exist_ok=True)
    tok = AutoTokenizer.from_pretrained(model_id)
    tok.save_pretrained(out_dir)
    fixtures = []
    for text in CASES:
        # Truncate without padding first, then manually pad with 0
        # to match tok_loader's pad_id default of 0
        enc = tok(text, max_length=max_length, truncation=True,
                  return_tensors=None)
        ids  = enc["input_ids"]
        mask = enc["attention_mask"]
        pad_len = max_length - len(ids)
        ids  = ids  + [0] * pad_len
        mask = mask + [0] * pad_len
        fixtures.append({
            "text":           text,
            "input_ids":      ids,
            "attention_mask": mask
        })
    out = os.path.join(out_dir, "wordpiece_cases.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(fixtures, f, ensure_ascii=False, indent=2)
    print(f"Written {len(fixtures)} cases to {out}")

if __name__ == "__main__":
    base = os.path.join(os.path.dirname(__file__), "tok_bpe_SUITE_data")
    generate("gpt2", os.path.join(base, "gpt2"), max_length=512)
