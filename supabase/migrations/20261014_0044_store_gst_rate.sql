-- ===================================================================
-- Migration 0044: One GST rate per POS, applied to every bill
-- ===================================================================
--
-- GST is no longer typed in on each bill. Each POS has a GST rate in
-- Admin -> Store Settings ("Apply GST to every bill" + "GST rate %"), and
-- the POS adds it to every bill automatically, split into CGST + SGST.
--
-- store_settings.gst_enabled already existed; this adds gst_rate and turns
-- GST on at 18% for both POS. Change either at any time in Store Settings.
--
-- Deploy order: run this BEFORE deploying the app build that reads the
-- rate (until then the app treats GST as off).
--
-- SAFE / IDEMPOTENT: the 18% default is only applied once (when the column
-- is first added), so re-running never overwrites a rate set in Settings.
-- ===================================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'store_settings' AND column_name = 'gst_rate'
  ) THEN
    ALTER TABLE public.store_settings
      ADD COLUMN gst_rate NUMERIC(5,2) NOT NULL DEFAULT 18
      CONSTRAINT store_settings_gst_rate_check CHECK (gst_rate >= 0 AND gst_rate <= 100);

    UPDATE public.store_settings
    SET gst_enabled = TRUE, gst_rate = 18, updated_at = NOW()
    WHERE branch IN ('pos1', 'pos2');
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

SELECT branch, gst_enabled, gst_rate FROM public.store_settings ORDER BY branch;
