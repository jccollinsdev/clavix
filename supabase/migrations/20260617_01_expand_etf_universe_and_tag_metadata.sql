-- Expand the launch ETF universe and make ETF classification durable.
-- Clavix scores funds differently from operating companies, so existing and
-- future ETF metadata rows must carry asset_class='etf'.

WITH etfs(ticker, company_name, exchange, sector, priority_rank) AS (
    VALUES
        ('SPY', 'SPDR S&P 500 ETF Trust', 'NYSEARCA', 'Broad Market', 1),
        ('VOO', 'Vanguard S&P 500 ETF', 'NYSEARCA', 'Broad Market', 2),
        ('IVV', 'iShares Core S&P 500 ETF', 'NYSEARCA', 'Broad Market', 3),
        ('QQQ', 'Invesco QQQ Trust', 'NASDAQ', 'Technology', 4),
        ('VTI', 'Vanguard Total Stock Market ETF', 'NYSEARCA', 'Broad Market', 5),
        ('IWM', 'iShares Russell 2000 ETF', 'NYSEARCA', 'Broad Market', 6),
        ('IJH', 'iShares Core S&P Mid-Cap ETF', 'NYSEARCA', 'Broad Market', 7),
        ('EFA', 'iShares MSCI EAFE ETF', 'NYSEARCA', 'International Equity', 8),
        ('IEFA', 'iShares Core MSCI EAFE ETF', 'NYSEARCA', 'International Equity', 9),
        ('EEM', 'iShares MSCI Emerging Markets ETF', 'NYSEARCA', 'Emerging Markets', 10),
        ('SCHD', 'Schwab U.S. Dividend Equity ETF', 'NYSEARCA', 'Dividend Equity', 11),
        ('ARKK', 'ARK Innovation ETF', 'NYSEARCA', 'Thematic Equity', 12),
        ('SOXX', 'iShares Semiconductor ETF', 'NASDAQ', 'Technology', 13),
        ('VNQ', 'Vanguard Real Estate ETF', 'NYSEARCA', 'Real Estate', 14),
        ('AGG', 'iShares Core U.S. Aggregate Bond ETF', 'NYSEARCA', 'Fixed Income', 15),
        ('BND', 'Vanguard Total Bond Market ETF', 'NASDAQ', 'Fixed Income', 16),
        ('TLT', 'iShares 20+ Year Treasury Bond ETF', 'NASDAQ', 'Fixed Income', 17),
        ('SHY', 'iShares 1-3 Year Treasury Bond ETF', 'NASDAQ', 'Fixed Income', 18),
        ('BIL', 'SPDR Bloomberg 1-3 Month T-Bill ETF', 'NYSEARCA', 'Fixed Income', 19),
        ('HYG', 'iShares iBoxx $ High Yield Corporate Bond ETF', 'NYSEARCA', 'Fixed Income', 20),
        ('LQD', 'iShares iBoxx $ Investment Grade Corporate Bond ETF', 'NYSEARCA', 'Fixed Income', 21),
        ('GLD', 'SPDR Gold Shares', 'NYSEARCA', 'Commodity', 22),
        ('IAU', 'iShares Gold Trust', 'NYSEARCA', 'Commodity', 23),
        ('SLV', 'iShares Silver Trust', 'NYSEARCA', 'Commodity', 24),
        ('USO', 'United States Oil Fund', 'NYSEARCA', 'Commodity', 25),
        ('XLK', 'Technology Select Sector SPDR Fund', 'NYSEARCA', 'Technology', 26),
        ('XLF', 'Financial Select Sector SPDR Fund', 'NYSEARCA', 'Financials', 27),
        ('XLE', 'Energy Select Sector SPDR Fund', 'NYSEARCA', 'Energy', 28),
        ('XLV', 'Health Care Select Sector SPDR Fund', 'NYSEARCA', 'Health Care', 29),
        ('XLI', 'Industrial Select Sector SPDR Fund', 'NYSEARCA', 'Industrials', 30),
        ('XLC', 'Communication Services Select Sector SPDR Fund', 'NYSEARCA', 'Communication Services', 31),
        ('XLY', 'Consumer Discretionary Select Sector SPDR Fund', 'NYSEARCA', 'Consumer Discretionary', 32),
        ('XLP', 'Consumer Staples Select Sector SPDR Fund', 'NYSEARCA', 'Consumer Staples', 33),
        ('XLU', 'Utilities Select Sector SPDR Fund', 'NYSEARCA', 'Utilities', 34),
        ('XLRE', 'Real Estate Select Sector SPDR Fund', 'NYSEARCA', 'Real Estate', 35),
        ('XLB', 'Materials Select Sector SPDR Fund', 'NYSEARCA', 'Materials', 36)
)
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
SELECT
    ticker,
    company_name,
    exchange,
    sector,
    'ETF',
    'ETF',
    true,
    priority_rank,
    now()
FROM etfs
ON CONFLICT (ticker) DO UPDATE SET
    company_name = EXCLUDED.company_name,
    exchange = EXCLUDED.exchange,
    sector = EXCLUDED.sector,
    industry = 'ETF',
    index_membership = 'ETF',
    is_active = true,
    priority_rank = EXCLUDED.priority_rank,
    updated_at = now();

WITH etfs(ticker, company_name, exchange, sector) AS (
    VALUES
        ('SPY', 'SPDR S&P 500 ETF Trust', 'NYSEARCA', 'Broad Market'),
        ('VOO', 'Vanguard S&P 500 ETF', 'NYSEARCA', 'Broad Market'),
        ('IVV', 'iShares Core S&P 500 ETF', 'NYSEARCA', 'Broad Market'),
        ('QQQ', 'Invesco QQQ Trust', 'NASDAQ', 'Technology'),
        ('VTI', 'Vanguard Total Stock Market ETF', 'NYSEARCA', 'Broad Market'),
        ('IWM', 'iShares Russell 2000 ETF', 'NYSEARCA', 'Broad Market'),
        ('IJH', 'iShares Core S&P Mid-Cap ETF', 'NYSEARCA', 'Broad Market'),
        ('EFA', 'iShares MSCI EAFE ETF', 'NYSEARCA', 'International Equity'),
        ('IEFA', 'iShares Core MSCI EAFE ETF', 'NYSEARCA', 'International Equity'),
        ('EEM', 'iShares MSCI Emerging Markets ETF', 'NYSEARCA', 'Emerging Markets'),
        ('SCHD', 'Schwab U.S. Dividend Equity ETF', 'NYSEARCA', 'Dividend Equity'),
        ('ARKK', 'ARK Innovation ETF', 'NYSEARCA', 'Thematic Equity'),
        ('SOXX', 'iShares Semiconductor ETF', 'NASDAQ', 'Technology'),
        ('VNQ', 'Vanguard Real Estate ETF', 'NYSEARCA', 'Real Estate'),
        ('AGG', 'iShares Core U.S. Aggregate Bond ETF', 'NYSEARCA', 'Fixed Income'),
        ('BND', 'Vanguard Total Bond Market ETF', 'NASDAQ', 'Fixed Income'),
        ('TLT', 'iShares 20+ Year Treasury Bond ETF', 'NASDAQ', 'Fixed Income'),
        ('SHY', 'iShares 1-3 Year Treasury Bond ETF', 'NASDAQ', 'Fixed Income'),
        ('BIL', 'SPDR Bloomberg 1-3 Month T-Bill ETF', 'NYSEARCA', 'Fixed Income'),
        ('HYG', 'iShares iBoxx $ High Yield Corporate Bond ETF', 'NYSEARCA', 'Fixed Income'),
        ('LQD', 'iShares iBoxx $ Investment Grade Corporate Bond ETF', 'NYSEARCA', 'Fixed Income'),
        ('GLD', 'SPDR Gold Shares', 'NYSEARCA', 'Commodity'),
        ('IAU', 'iShares Gold Trust', 'NYSEARCA', 'Commodity'),
        ('SLV', 'iShares Silver Trust', 'NYSEARCA', 'Commodity'),
        ('USO', 'United States Oil Fund', 'NYSEARCA', 'Commodity'),
        ('XLK', 'Technology Select Sector SPDR Fund', 'NYSEARCA', 'Technology'),
        ('XLF', 'Financial Select Sector SPDR Fund', 'NYSEARCA', 'Financials'),
        ('XLE', 'Energy Select Sector SPDR Fund', 'NYSEARCA', 'Energy'),
        ('XLV', 'Health Care Select Sector SPDR Fund', 'NYSEARCA', 'Health Care'),
        ('XLI', 'Industrial Select Sector SPDR Fund', 'NYSEARCA', 'Industrials'),
        ('XLC', 'Communication Services Select Sector SPDR Fund', 'NYSEARCA', 'Communication Services'),
        ('XLY', 'Consumer Discretionary Select Sector SPDR Fund', 'NYSEARCA', 'Consumer Discretionary'),
        ('XLP', 'Consumer Staples Select Sector SPDR Fund', 'NYSEARCA', 'Consumer Staples'),
        ('XLU', 'Utilities Select Sector SPDR Fund', 'NYSEARCA', 'Utilities'),
        ('XLRE', 'Real Estate Select Sector SPDR Fund', 'NYSEARCA', 'Real Estate'),
        ('XLB', 'Materials Select Sector SPDR Fund', 'NYSEARCA', 'Materials')
)
INSERT INTO public.ticker_metadata (
    ticker,
    company_name,
    asset_class,
    exchange,
    sector,
    industry,
    is_supported,
    updated_at
)
SELECT
    ticker,
    company_name,
    'etf',
    exchange,
    sector,
    'ETF',
    true,
    now()
FROM etfs
ON CONFLICT (ticker) DO UPDATE SET
    company_name = COALESCE(public.ticker_metadata.company_name, EXCLUDED.company_name),
    asset_class = 'etf',
    exchange = COALESCE(public.ticker_metadata.exchange, EXCLUDED.exchange),
    sector = COALESCE(public.ticker_metadata.sector, EXCLUDED.sector),
    industry = 'ETF',
    is_supported = true,
    updated_at = now();
