-- ===================================================================
-- Migration 0050: Low stock settings per POS
-- ===================================================================
--
-- Adds two columns to store_settings (one row per POS, so each POS keeps
-- its own values):
--   low_stock_alerts_enabled  - turn the low stock alarm on / off
--   low_stock_threshold       - alert level used for new products
--
-- Changed in Admin -> Store Settings -> Low Stock.
--
-- SAFE / IDEMPOTENT: only adds columns; nothing else is changed, and
-- re-running it does nothing.
-- ===================================================================

BEGIN;

ALTER TABLE public.store_settings
  ADD COLUMN IF NOT EXISTS low_stock_alerts_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.store_settings
  ADD COLUMN IF NOT EXISTS low_stock_threshold INTEGER NOT NULL DEFAULT 5;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'store_settings_low_stock_threshold_check') THEN
    ALTER TABLE public.store_settings
      ADD CONSTRAINT store_settings_low_stock_threshold_check CHECK (low_stock_threshold >= 1 AND low_stock_threshold <= 100000);
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
