-- ===================================================================
-- Migration 0048: Christmas POS (POS 3) - GST for Wholesale bills
-- ===================================================================
-- A Christmas POS bill is billed at either the Retail or the Wholesale
-- price list. Retail bills keep using store_settings.gst_enabled / gst_rate;
-- these two columns hold the GST setting for Wholesale bills.
-- Only the pos3 row uses them. SAFE / IDEMPOTENT.
-- ===================================================================

ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS wholesale_gst_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS wholesale_gst_rate NUMERIC(5,2) NOT NULL DEFAULT 0;

NOTIFY pgrst, 'reload schema';

SELECT branch, gst_enabled, gst_rate, wholesale_gst_enabled, wholesale_gst_rate FROM public.store_settings ORDER BY id;
