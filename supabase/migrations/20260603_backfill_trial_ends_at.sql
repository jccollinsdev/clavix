-- Backfill trial_ends_at for users who have trial_started_at but no trial_ends_at.
-- New users get trial_ends_at set at account creation time by the backend.
-- Existing users get 14 days from their trial_started_at (or from now if also null).
UPDATE public.user_preferences
SET trial_ends_at = COALESCE(trial_started_at, now()) + INTERVAL '14 days'
WHERE trial_ends_at IS NULL;
