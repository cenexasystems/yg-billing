-- ===================================================================
-- Migration 0046: Google review link per POS
-- ===================================================================
--
-- Adds store_settings.google_review_url, set in Admin -> Store Settings.
-- The Fireworks (POS 2) WhatsApp message includes it so customers can
-- leave a Google review.
--
-- SAFE / IDEMPOTENT: re-running changes nothing.
-- ===================================================================

ALTER TABLE public.store_settings
  ADD COLUMN IF NOT EXISTS google_review_url TEXT NOT NULL DEFAULT '';

NOTIFY pgrst, 'reload schema';

SELECT branch, google_review_url FROM public.store_settings ORDER BY branch;
