from __future__ import annotations


import re


def resolve_asset(assets: dict[str, str], asset: str) -> str | None:
    key = assets.get(asset)
    if not key or any(
        part in {"", ".", ".."} or not re.fullmatch(r"[a-zA-Z0-9_.-]+", part)
        for part in key.split("/")
    ):
        return None
    return f"s3://cog/{key}"
