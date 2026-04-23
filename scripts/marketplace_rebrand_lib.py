"""Pure helpers for marketplace_rebrand — no AWS SDK calls, no I/O."""
from __future__ import annotations

import base64
from pathlib import Path
from typing import Any


REQUIRED_FIELDS = (
    "title",
    "short_description",
    "long_description",
    "highlights",
    "categories",
    "search_keywords",
    "resources",
    "support_description",
    "sku",
)


def load_product_info(config: dict[str, Any]) -> dict[str, Any]:
    """Extract and validate the product_info block from a marketplace_config dict.

    Raises ValueError if required fields are missing.
    """
    info = config.get("product_info")
    if not isinstance(info, dict):
        raise ValueError("config missing required 'product_info' block")
    missing = [f for f in REQUIRED_FIELDS if f not in info]
    if missing:
        raise ValueError(f"product_info missing required fields: {missing}")
    return info


def build_update_information_change(product_id: str, info: dict[str, Any]) -> dict[str, Any]:
    return {
        "ChangeType": "UpdateInformation",
        "Entity": {"Identifier": product_id, "Type": "AmiProduct@1.0"},
        "DetailsDocument": {
            "ProductTitle": info["title"],
            "ShortDescription": info["short_description"],
            "LongDescription": info["long_description"],
            "Highlights": info["highlights"],
            "Categories": info["categories"],
            "SearchKeywords": info["search_keywords"],
            "Resources": [
                {"Type": "Text", "Text": r["name"], "Url": r["url"]}
                for r in info["resources"]
            ],
            "SupportDescription": info["support_description"],
            "Sku": info["sku"],
        },
    }


def build_update_logo_change(product_id: str, logo_path: Path) -> dict[str, Any]:
    raw = Path(logo_path).read_bytes()
    encoded = base64.b64encode(raw).decode("ascii")
    return {
        "ChangeType": "UpdateLogo",
        "Entity": {"Identifier": product_id, "Type": "AmiProduct@1.0"},
        "DetailsDocument": {
            "LogoUrl": f"data:image/png;base64,{encoded}",
        },
    }
