BEGIN;

ALTER TABLE public.position_analyses
  ADD COLUMN IF NOT EXISTS driver_cards JSONB,
  ADD COLUMN IF NOT EXISTS driver_cards_state TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS driver_cards_source TEXT;

ALTER TABLE public.position_analyses
  DROP CONSTRAINT IF EXISTS position_analyses_driver_cards_state_check;

ALTER TABLE public.position_analyses
  ADD CONSTRAINT position_analyses_driver_cards_state_check
  CHECK (driver_cards_state IN ('pending', 'ready', 'limited', 'empty'));

ALTER TABLE public.position_analyses
  DROP CONSTRAINT IF EXISTS position_analyses_driver_cards_source_check;

ALTER TABLE public.position_analyses
  ADD CONSTRAINT position_analyses_driver_cards_source_check
  CHECK (driver_cards_source IN ('generated', 'legacy_fallback'));

COMMENT ON COLUMN public.position_analyses.driver_cards IS
  'Structured driver cards for ticker and position detail rendering.';
COMMENT ON COLUMN public.position_analyses.driver_cards_state IS
  'Driver card readiness state for API consumers.';
COMMENT ON COLUMN public.position_analyses.driver_cards_source IS
  'Provenance for driver cards: generated or legacy_fallback.';

COMMIT;

-- Rollback:
-- BEGIN;
-- ALTER TABLE public.position_analyses DROP CONSTRAINT IF EXISTS position_analyses_driver_cards_source_check;
-- ALTER TABLE public.position_analyses DROP CONSTRAINT IF EXISTS position_analyses_driver_cards_state_check;
-- ALTER TABLE public.position_analyses DROP COLUMN IF EXISTS driver_cards_source;
-- ALTER TABLE public.position_analyses DROP COLUMN IF EXISTS driver_cards_state;
-- ALTER TABLE public.position_analyses DROP COLUMN IF EXISTS driver_cards;
-- COMMIT;
