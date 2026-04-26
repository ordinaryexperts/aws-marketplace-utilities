import pytest
from scripts.marketplace_rebrand_lib import (
    build_update_information_change,
    load_product_info,
)


def test_load_product_info_happy_path():
    cfg = {
        "product_id": "abc",
        "product_info": {
            "title": "Zulip on AWS by FOSSonCloud",
            "short_description": "Short",
            "long_description": "Long",
            "highlights": ["one", "two", "three"],
            "categories": ["Application Stacks"],
            "search_keywords": ["zulip"],
            "resources": [{"name": "Docs", "url": "https://example.com"}],
            "support_description": "Email support",
            "sku": "OE_PATTERNS_ZULIP",
        },
    }
    info = load_product_info(cfg)
    assert info["title"] == "Zulip on AWS by FOSSonCloud"
    assert info["highlights"] == ["one", "two", "three"]


def test_load_product_info_missing_block_raises():
    with pytest.raises(ValueError, match="product_info"):
        load_product_info({"product_id": "abc"})


def test_load_product_info_missing_title_raises():
    cfg = {"product_info": {"short_description": "x"}}
    with pytest.raises(ValueError, match="title"):
        load_product_info(cfg)


def test_update_information_change_shape():
    product_info = {
        "title": "Zulip on AWS by FOSSonCloud",
        "short_description": "Short",
        "long_description": "Long",
        "highlights": ["a", "b"],
        "categories": ["Application Stacks"],
        "search_keywords": ["zulip"],
        "resources": [{"name": "Docs", "url": "https://example.com"}],
        "support_description": "Email support",
        "sku": "OE_PATTERNS_ZULIP",
    }
    change = build_update_information_change("prod-id-123", product_info)
    assert change["ChangeType"] == "UpdateInformation"
    assert change["Entity"] == {"Identifier": "prod-id-123", "Type": "AmiProduct@1.0"}
    details = change["DetailsDocument"]
    assert details["ProductTitle"] == "Zulip on AWS by FOSSonCloud"
    assert details["ShortDescription"] == "Short"
    assert details["LongDescription"] == "Long"
    assert details["Highlights"] == ["a", "b"]
    assert details["Categories"] == ["Application Stacks"]
    assert details["SearchKeywords"] == ["zulip"]
    assert details["AdditionalResources"] == [{"Text": "Docs", "Url": "https://example.com"}]
    assert details["SupportDescription"] == "Email support"
    assert details["Sku"] == "OE_PATTERNS_ZULIP"
    assert "LogoUrl" not in details


def test_update_information_change_includes_logo_url_when_provided():
    product_info = {
        "title": "Zulip on AWS by FOSSonCloud",
        "short_description": "Short",
        "long_description": "Long",
        "highlights": ["a", "b"],
        "categories": ["Application Stacks"],
        "search_keywords": ["zulip"],
        "resources": [{"name": "Docs", "url": "https://example.com"}],
        "support_description": "Email support",
        "sku": "OE_PATTERNS_ZULIP",
    }
    change = build_update_information_change(
        "prod-id-123", product_info, logo_url="https://example.com/logo.png"
    )
    assert change["DetailsDocument"]["LogoUrl"] == "https://example.com/logo.png"
