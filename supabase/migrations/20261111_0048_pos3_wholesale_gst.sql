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

-- Retail / Wholesale pricing belongs to the Christmas POS only: the database refuses it elsewhere.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_wholesale_pos3_only') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_wholesale_pos3_only
      CHECK (wholesale_price IS NULL OR branch = 'pos3');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'product_variants_wholesale_pos3_only') THEN
    ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_wholesale_pos3_only
      CHECK (wholesale_price IS NULL OR branch = 'pos3');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'store_settings_wholesale_gst_pos3_only') THEN
    ALTER TABLE public.store_settings ADD CONSTRAINT store_settings_wholesale_gst_pos3_only
      CHECK (branch = 'pos3' OR (NOT wholesale_gst_enabled AND wholesale_gst_rate = 0));
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

SELECT branch, gst_enabled, gst_rate, wholesale_gst_enabled, wholesale_gst_rate FROM public.store_settings ORDER BY id;
