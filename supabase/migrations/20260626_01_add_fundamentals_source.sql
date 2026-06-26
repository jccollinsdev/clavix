-- Add fundamentals_source column to ticker_metadata
-- Tracks whether financial ratios came from Finnhub or SEC EDGAR
ALTER TABLE ticker_metadata 
ADD COLUMN IF NOT EXISTS fundamentals_source text DEFAULT 'finnhub';

COMMENT ON COLUMN ticker_metadata.fundamentals_source IS 'Data source for financial ratios: finnhub or edgar';
