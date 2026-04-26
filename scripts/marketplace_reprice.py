#!/usr/bin/env python3
"""Flatten an AWS Marketplace Offer's UsageBasedPricingTerm to a single price.

Reads marketplace_config.yaml for product_id and flat_price. Discovers the
offer for that product (or honors offer_id / --offer-id), fetches its current
pricing, mutates every Price to the configured flat value, and submits an
UpdatePricingTerms change set.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

from marketplace_reprice_lib import (
    build_update_pricing_change,
    flatten_usage_pricing,
    load_flat_price,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--config-path",
        default="marketplace_config.yaml",
        help="Path to marketplace_config.yaml (default: ./marketplace_config.yaml)",
    )
    p.add_argument(
        "--offer-id",
        default=None,
        help="Override the offer ID (skips auto-discovery and config offer_id)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the change-set JSON and exit without submitting (still calls AWS read-only APIs to discover the offer + fetch its current pricing)",
    )
    return p.parse_args(argv)


def _resolve_offer_id(mpc, product_id: str, config: dict, cli_offer_id: str | None) -> str:
    if cli_offer_id:
        return cli_offer_id
    if config.get("offer_id"):
        return config["offer_id"]
    resp = mpc.list_entities(
        Catalog="AWSMarketplace",
        EntityType="Offer",
        FilterList=[{"Name": "ProductId", "ValueList": [product_id]}],
    )
    offers = resp.get("EntitySummaryList", [])
    if not offers:
        raise SystemExit(f"ERROR: no Offer entity found for product_id={product_id}")
    if len(offers) > 1:
        ids = [o["EntityId"] for o in offers]
        raise SystemExit(
            f"ERROR: multiple offers found for product_id={product_id}: {ids}\n"
            f"Set 'offer_id' in marketplace_config.yaml or pass --offer-id."
        )
    return offers[0]["EntityId"]


def _extract_usage_term(details: dict) -> dict:
    terms = details.get("Terms", [])
    usage = [t for t in terms if t.get("Type") == "UsageBasedPricingTerm"]
    if len(usage) == 0:
        raise SystemExit("ERROR: offer has no UsageBasedPricingTerm — cannot reprice")
    if len(usage) > 1:
        raise SystemExit(
            f"ERROR: offer has {len(usage)} UsageBasedPricingTerms; expected 1"
        )
    return usage[0]


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        config = yaml.safe_load(Path(args.config_path).read_text())
    except FileNotFoundError:
        print(f"ERROR: config file not found: {args.config_path}", file=sys.stderr)
        return 2
    except yaml.YAMLError as e:
        print(f"ERROR: could not parse config: {e}", file=sys.stderr)
        return 2
    if not isinstance(config, dict):
        print(f"ERROR: config is not a YAML mapping: {args.config_path}", file=sys.stderr)
        return 2

    product_id = config.get("product_id")
    if not product_id:
        print("ERROR: config missing product_id", file=sys.stderr)
        return 2

    try:
        flat_price = load_flat_price(config)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    import boto3  # imported lazily so module-load is cheap and dry-run-friendly
    mpc = boto3.client("marketplace-catalog", region_name="us-east-1")

    offer_id = _resolve_offer_id(mpc, product_id, config, args.offer_id)
    print(f"Using offer: {offer_id}", file=sys.stderr)

    ent = mpc.describe_entity(Catalog="AWSMarketplace", EntityId=offer_id)
    details = ent["DetailsDocument"]
    if isinstance(details, str):
        details = json.loads(details)

    usage_term = _extract_usage_term(details)
    flat_term = flatten_usage_pricing(usage_term, flat_price)

    # Sanity report — show before/after range so the operator can spot
    # an unintended price increase before it ships.
    old_prices = sorted(set(float(d["Price"]) for d in usage_term["RateCards"][0]["RateCard"]))
    n = len(flat_term["RateCards"][0]["RateCard"])
    old_lo, old_hi = old_prices[0], old_prices[-1]
    new_p = float(flat_price)
    direction = (
        "no-op" if old_lo == old_hi == new_p else
        "raises" if new_p >= old_hi else
        "lowers" if new_p <= old_lo else
        "spans"
    )
    print(
        f"Flattening {n} dimensions: was ${old_lo:.2f}-${old_hi:.2f} "
        f"-> ${flat_price} ({direction})",
        file=sys.stderr,
    )

    change = build_update_pricing_change(offer_id, flat_term)

    if args.dry_run:
        print(json.dumps([change], indent=2))
        return 0

    response = mpc.start_change_set(
        Catalog="AWSMarketplace",
        ChangeSet=[
            {
                "ChangeType": change["ChangeType"],
                "Entity": change["Entity"],
                "DetailsDocument": change["DetailsDocument"],
            }
        ],
        ChangeSetName=f"reprice-{offer_id[:8]}",
    )
    cs_id = response["ChangeSetId"]
    Path(".marketplace_changeset_pricing").write_text(cs_id + "\n")
    print(f"Change set created: {cs_id}")
    print("Check status with: make marketplace-status")
    return 0


if __name__ == "__main__":
    sys.exit(main())
