"""IDX symbol normalization shared across data + logos."""

from __future__ import annotations

IHSG_SYMBOL = "^JKSE"


def normalize_idx_symbol(symbol: str) -> str:
    letters = "".join(c for c in symbol.upper() if c.isalpha())
    if not letters:
        raise ValueError("Kode saham kosong")
    if letters in ("IHSG", "JKSE", "IDX", "COMPOSITE"):
        return IHSG_SYMBOL
    raw = symbol.strip().upper().replace("#", "").split()
    if raw and raw[0].startswith("^"):
        return raw[0]
    if letters.endswith("JK") and len(letters) > 2:
        return f"{letters[:-2]}.JK"
    if symbol.strip().upper().endswith(".JK"):
        base = "".join(c for c in symbol.upper().split(".")[0] if c.isalpha())
        return f"{base}.JK"
    return f"{letters}.JK"
