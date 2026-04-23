#!/usr/bin/env python3
"""Submit a FOSSonCloud rebrand change set to the AWS Marketplace Catalog API.

Reads marketplace_config.yaml, validates product_info, builds UpdateInformation +
UpdateLogo changes, and submits them as a single change set. --dry-run prints the
change set JSON without calling AWS.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

from marketplace_rebrand_lib import (
    build_update_information_change,
    build_update_logo_change,
    load_product_info,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--config-path",
        default="marketplace_config.yaml",
        help="Path to marketplace_config.yaml (default: ./marketplace_config.yaml)",
    )
    p.add_argument(
        "--logo-path",
        default="logo.png",
        help="Path to logo.png (default: ./logo.png)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the change-set JSON and exit without calling AWS",
    )
    return p.parse_args(argv)


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
        print(f"ERROR: config file is not a YAML mapping: {args.config_path}", file=sys.stderr)
        return 2
    product_id = config.get("product_id")
    if not product_id:
        print("ERROR: config missing product_id", file=sys.stderr)
        return 2
    try:
        info = load_product_info(config)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    logo_path = Path(args.logo_path)
    if not logo_path.is_file():
        print(f"ERROR: logo file not found: {logo_path}", file=sys.stderr)
        return 2

    change_set = [
        build_update_information_change(product_id, info),
        build_update_logo_change(product_id, logo_path),
    ]

    if args.dry_run:
        # Don't leak the base64 logo blob into dry-run output; summarize instead.
        preview = [dict(c) for c in change_set]
        for c in preview:
            if c["ChangeType"] == "UpdateLogo":
                details = dict(c["DetailsDocument"])
                url = details.get("LogoUrl", "")
                details["LogoUrl"] = f"{url[:40]}...[{len(url)} chars total]"
                c["DetailsDocument"] = details
        print(json.dumps(preview, indent=2))
        return 0

    import boto3  # imported lazily so --dry-run works without AWS creds

    mpc = boto3.client("marketplace-catalog", region_name="us-east-1")
    response = mpc.start_change_set(
        Catalog="AWSMarketplace",
        ChangeSet=[
            {
                "ChangeType": c["ChangeType"],
                "Entity": c["Entity"],
                "DetailsDocument": c["DetailsDocument"],
            }
            for c in change_set
        ],
        ChangeSetName=f"rebrand-{product_id[:8]}",
    )
    change_set_id = response["ChangeSetId"]
    Path(".marketplace_changeset").write_text(change_set_id + "\n")
    print(f"Change set created: {change_set_id}")
    print("Check status with: make marketplace-status")
    return 0


if __name__ == "__main__":
    sys.exit(main())
