"""Pure helpers for marketplace_reprice — no AWS SDK calls, no I/O."""
from __future__ import annotations

import copy
from typing import Any


def load_flat_price(config: dict[str, Any]) -> str:
    """Extract and validate flat_price from a marketplace_config dict.

    Returns the price as a string (the API wants strings, not floats).
    Raises ValueError if missing or not a non-empty string.
    """
    val = config.get("flat_price")
    if val is None or val == "":
        raise ValueError("config missing required 'flat_price' field")
    if not isinstance(val, str):
        raise ValueError(
            f"'flat_price' must be a quoted string in YAML "
            f"(got {type(val).__name__}: {val!r})"
        )
    try:
        float(val)
    except ValueError:
        raise ValueError(
            f"'flat_price' must parse as a number (got {val!r})"
        ) from None
    return val


def flatten_usage_pricing(term: dict[str, Any], flat_price: str) -> dict[str, Any]:
    """Return a deep copy of the UsageBasedPricingTerm with every Price replaced.

    Preserves DimensionKey, CurrencyCode, and overall structure. Does not mutate
    the input.
    """
    if term.get("Type") != "UsageBasedPricingTerm":
        raise ValueError(
            f"flatten_usage_pricing expected Type=UsageBasedPricingTerm, "
            f"got {term.get('Type')!r}"
        )
    out = copy.deepcopy(term)
    for rate_card in out.get("RateCards", []):
        for dim in rate_card.get("RateCard", []):
            dim["Price"] = flat_price
    return out


def build_update_pricing_change(
    offer_id: str, flat_term: dict[str, Any]
) -> dict[str, Any]:
    """Build a change-set element for the AWS Marketplace Catalog API.

    Wraps a single UsageBasedPricingTerm (already flattened) in the DetailsDocument
    envelope per the AWS spec. Returns a dict suitable for passing to start-change-set.
    """
    return {
        "ChangeType": "UpdatePricingTerms",
        "Entity": {"Identifier": offer_id, "Type": "Offer@1.0"},
        "DetailsDocument": {
            "PricingModel": "Usage",
            "Terms": [flat_term],
        },
    }
