from app.services.ticker_metadata import build_ticker_metadata, _infer_asset_class_from_finnhub


def test_known_etf_builds_etf_asset_class():
    assert (
        _infer_asset_class_from_finnhub(
            "VOO",
            {
                "name": "Vanguard S&P 500 ETF",
                "finnhubIndustry": "",
                "sector": "",
                "industry": "",
            },
        )
        == "etf"
    )


def test_operating_company_keeps_equity_asset_class():
    metadata = build_ticker_metadata(
        "AAPL",
        finnhub_data={
            "ticker": "AAPL",
            "company_name": "Apple Inc",
            "asset_class": "large_cap_equity",
            "exchange": "NASDAQ",
            "sector": "Technology",
            "industry": "Consumer Electronics",
            "market_cap": 3_000_000_000_000,
            "price": 200.0,
        },
    )

    assert metadata is not None
    assert metadata["asset_class"] == "large_cap_equity"
