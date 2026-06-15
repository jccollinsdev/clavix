-- Seed launch-critical ETFs into the supported ticker universe.
-- index_membership='ETF' is used by the pipeline to treat fundamentals as ETF-style limited data.

INSERT INTO public.ticker_universe (
    ticker,
    company_name,
    exchange,
    sector,
    industry,
    index_membership,
    is_active,
    priority_rank,
    updated_at
)
VALUES
    ('QQQ', 'Invesco QQQ Trust', 'NASDAQ', 'Technology', 'ETF', 'ETF', true, 1, now()),
    ('XLF', 'Financial Select Sector SPDR Fund', 'NYSEARCA', 'Financials', 'ETF', 'ETF', true, 2, now()),
    ('XLK', 'Technology Select Sector SPDR Fund', 'NYSEARCA', 'Technology', 'ETF', 'ETF', true, 3, now()),
    ('XLE', 'Energy Select Sector SPDR Fund', 'NYSEARCA', 'Energy', 'ETF', 'ETF', true, 4, now()),
    ('XLV', 'Health Care Select Sector SPDR Fund', 'NYSEARCA', 'Health Care', 'ETF', 'ETF', true, 5, now()),
    ('XLI', 'Industrial Select Sector SPDR Fund', 'NYSEARCA', 'Industrials', 'ETF', 'ETF', true, 6, now()),
    ('XLC', 'Communication Services Select Sector SPDR Fund', 'NYSEARCA', 'Communication Services', 'ETF', 'ETF', true, 7, now()),
    ('XLY', 'Consumer Discretionary Select Sector SPDR Fund', 'NYSEARCA', 'Consumer Discretionary', 'ETF', 'ETF', true, 8, now()),
    ('XLP', 'Consumer Staples Select Sector SPDR Fund', 'NYSEARCA', 'Consumer Staples', 'ETF', 'ETF', true, 9, now()),
    ('XLU', 'Utilities Select Sector SPDR Fund', 'NYSEARCA', 'Utilities', 'ETF', 'ETF', true, 10, now()),
    ('XLRE', 'Real Estate Select Sector SPDR Fund', 'NYSEARCA', 'Real Estate', 'ETF', 'ETF', true, 11, now()),
    ('XLB', 'Materials Select Sector SPDR Fund', 'NYSEARCA', 'Materials', 'ETF', 'ETF', true, 12, now()),
    ('AGG', 'iShares Core U.S. Aggregate Bond ETF', 'NYSEARCA', 'Fixed Income', 'ETF', 'ETF', true, 13, now()),
    ('BND', 'Vanguard Total Bond Market ETF', 'NASDAQ', 'Fixed Income', 'ETF', 'ETF', true, 14, now()),
    ('VTI', 'Vanguard Total Stock Market ETF', 'NYSEARCA', 'Broad Market', 'ETF', 'ETF', true, 15, now()),
    ('IWM', 'iShares Russell 2000 ETF', 'NYSEARCA', 'Broad Market', 'ETF', 'ETF', true, 16, now()),
    ('SCHD', 'Schwab U.S. Dividend Equity ETF', 'NYSEARCA', 'Dividend Equity', 'ETF', 'ETF', true, 17, now())
ON CONFLICT (ticker) DO UPDATE SET
    company_name = EXCLUDED.company_name,
    exchange = EXCLUDED.exchange,
    sector = EXCLUDED.sector,
    industry = EXCLUDED.industry,
    index_membership = 'ETF',
    is_active = true,
    priority_rank = EXCLUDED.priority_rank,
    updated_at = now();
