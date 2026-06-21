BEGIN;

ALTER TABLE public.user_preferences
    ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz,
    ADD COLUMN IF NOT EXISTS subscription_offer_type integer,
    ADD COLUMN IF NOT EXISTS subscription_original_transaction_id text,
    ADD COLUMN IF NOT EXISTS subscription_environment text;

UPDATE public.user_preferences
SET trial_started_at = NULL,
    trial_ends_at = NULL
WHERE trial_started_at IS NOT NULL
   OR trial_ends_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.app_store_subscriptions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    original_transaction_id text NOT NULL UNIQUE,
    latest_transaction_id text NOT NULL UNIQUE,
    product_id text NOT NULL,
    environment text NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
    app_account_token uuid,
    purchase_date timestamptz,
    transaction_signed_at timestamptz NOT NULL,
    last_event_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    offer_type integer,
    is_active boolean NOT NULL DEFAULT false,
    notification_status integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_store_subscriptions_user
    ON public.app_store_subscriptions(user_id);

CREATE TABLE IF NOT EXISTS public.app_store_notifications (
    notification_uuid text PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_type text,
    subtype text,
    environment text,
    original_transaction_id text,
    received_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.app_store_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_store_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_manage_app_store_subscriptions"
    ON public.app_store_subscriptions;
CREATE POLICY "service_role_manage_app_store_subscriptions"
    ON public.app_store_subscriptions FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_manage_app_store_notifications"
    ON public.app_store_notifications;
CREATE POLICY "service_role_manage_app_store_notifications"
    ON public.app_store_notifications FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

COMMIT;
