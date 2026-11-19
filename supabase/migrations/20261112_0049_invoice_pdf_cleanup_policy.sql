-- ===================================================================
-- Migration 0049: let the app remove old invoice PDFs from Storage
-- ===================================================================
-- Storage space is limited on the free plan. The app now deletes surplus
-- invoice PDFs itself (see src/lib/invoiceRetention.ts): only Fireworks (POS 2)
-- keeps its newest 200; POS 1 and Christmas PDFs are never touched. A PDF is rebuilt
-- on demand when its invoice is opened, so nothing is lost.
-- This only allows deleting files in the 'invoices' bucket. SAFE / IDEMPOTENT.
-- ===================================================================

DROP POLICY IF EXISTS invoices_portal_delete ON storage.objects;
CREATE POLICY invoices_portal_delete ON storage.objects
  FOR DELETE TO anon, authenticated
  USING (bucket_id = 'invoices');
