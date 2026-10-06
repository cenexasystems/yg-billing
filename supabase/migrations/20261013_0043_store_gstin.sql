-- ===================================================================
-- Migration 0043: GST number (GSTIN) per POS
-- ===================================================================
--
-- Invoices and thermal receipts print the shop's GSTIN under the shop
-- details. It is stored per POS on store_settings and edited in
-- Admin -> Store Settings -> "GST Number (GSTIN)". An empty value hides it.
--
-- Fills in 33AJEPG5088P1ZS for both POS, but only where no GSTIN has been
-- saved yet, so re-running never overwrites a number changed in Settings.
--
-- Deploy order: run this BEFORE deploying the app build that reads and
-- saves the GSTIN (saving Store Settings needs the column to exist).
--
-- SAFE / IDEMPOTENT.
-- ===================================================================

BEGIN;

ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS gstin TEXT NOT NULL DEFAULT '';

UPDATE public.store_settings
SET gstin = '33AJEPG5088P1ZS', updated_at = NOW()
WHERE branch IN ('pos1', 'pos2')
  AND BTRIM(gstin) = '';

COMMIT;

NOTIFY pgrst, 'reload schema';

SELECT branch, gstin FROM public.store_settings ORDER BY branch;
