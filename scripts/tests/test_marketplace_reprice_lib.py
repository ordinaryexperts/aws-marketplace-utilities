import pytest
from scripts.marketplace_reprice_lib import (
    load_flat_price,
    flatten_usage_pricing,
    build_update_pricing_change,
)


def test_load_flat_price_happy_path():
    assert load_flat_price({"flat_price": "0.02"}) == "0.02"


def test_load_flat_price_missing_raises():
    with pytest.raises(ValueError, match="flat_price"):
        load_flat_price({})


def test_load_flat_price_empty_raises():
    with pytest.raises(ValueError, match="flat_price"):
        load_flat_price({"flat_price": ""})


def test_load_flat_price_non_string_raises():
    # A YAML float would be a footgun: "0.20" != "0.2" after str(float).
    # Force authors to quote the value.
    with pytest.raises(ValueError, match="string"):
        load_flat_price({"flat_price": 0.02})


def test_load_flat_price_non_numeric_string_raises():
    # Catch a typo'd config (e.g. flat_price: "abc") at load time, before
    # any AWS round-trip submits an unparseable price.
    with pytest.raises(ValueError, match="number"):
        load_flat_price({"flat_price": "abc"})


def _sample_term():
    return {
        "Type": "UsageBasedPricingTerm",
        "CurrencyCode": "USD",
        "RateCards": [
            {
                "RateCard": [
                    {"DimensionKey": "m5.large", "Price": "0.02"},
                    {"DimensionKey": "m5.xlarge", "Price": "0.03"},
                    {"DimensionKey": "m5.24xlarge", "Price": "0.73"},
                ]
            }
        ],
    }


def test_flatten_sets_every_price():
    flat = flatten_usage_pricing(_sample_term(), "0.02")
    prices = [d["Price"] for d in flat["RateCards"][0]["RateCard"]]
    assert prices == ["0.02", "0.02", "0.02"]


def test_flatten_preserves_dimension_keys_and_currency():
    flat = flatten_usage_pricing(_sample_term(), "0.02")
    keys = [d["DimensionKey"] for d in flat["RateCards"][0]["RateCard"]]
    assert keys == ["m5.large", "m5.xlarge", "m5.24xlarge"]
    assert flat["CurrencyCode"] == "USD"
    assert flat["Type"] == "UsageBasedPricingTerm"


def test_flatten_does_not_mutate_input():
    original = _sample_term()
    flatten_usage_pricing(original, "0.02")
    # Original third dimension was 0.73 — confirm untouched
    assert original["RateCards"][0]["RateCard"][2]["Price"] == "0.73"


def test_flatten_rejects_non_usage_term():
    bogus = {"Type": "FixedUpfrontPricingTerm"}
    with pytest.raises(ValueError, match="UsageBasedPricingTerm"):
        flatten_usage_pricing(bogus, "0.02")


def test_build_update_pricing_change_shape():
    flat_term = {
        "Type": "UsageBasedPricingTerm",
        "CurrencyCode": "USD",
        "RateCards": [
            {
                "RateCard": [
                    {"DimensionKey": "m5.large", "Price": "0.02"},
                ]
            }
        ],
    }
    change = build_update_pricing_change("offer-abc-123", flat_term)
    assert change["ChangeType"] == "UpdatePricingTerms"
    assert change["Entity"] == {"Identifier": "offer-abc-123", "Type": "Offer@1.0"}
    details = change["DetailsDocument"]
    assert details["PricingModel"] == "Usage"
    assert details["Terms"] == [flat_term]
