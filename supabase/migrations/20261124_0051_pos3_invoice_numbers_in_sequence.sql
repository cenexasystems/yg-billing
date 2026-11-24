-- ===================================================================
-- Migration 0051: Christmas (POS 3) invoice numbers 1, 2, 3 ... in order
-- ===================================================================
--
-- POS 3 bills are stored in their own block (60000001, 60000002, ...) so
-- they can never clash with POS 1 (10000001+) or POS 2 (1, 2, 3 ...).
-- The app shows a POS 3 number as its place in that block:
-- 60000001 -> INV00000001, 60000002 -> INV00000002, ...
--
-- 1. Renumbers the existing POS 3 bills in date order, so they read
--    1, 2, 3, ... with no gaps, and updates the stock history that
--    points at them. Stored invoice PDFs are cleared so they rebuild
--    with the new number.
-- 2. From now on a POS 3 bill gets (highest POS 3 number + 1), worked out
--    inside the same transaction that saves the bill. A bill that fails
--    to save no longer uses up a number, so there are no gaps.
--    POS 1 and POS 2 numbering is unchanged.
--
-- SAFE TO RE-RUN: already-ordered bills keep their numbers.
-- ===================================================================

DO $$
DECLARE
  r RECORD;
BEGIN
  -- Hold off new bills while renumbering.
  LOCK TABLE public.orders IN SHARE ROW EXCLUSIVE MODE;

  CREATE TEMP TABLE _pos3_renumber ON COMMIT DROP AS
  SELECT id,
         invoice_no AS old_no,
         LPAD((60000000 + ROW_NUMBER() OVER (ORDER BY created_at, invoice_no))::TEXT, 8, '0') AS new_no
  FROM public.orders
  WHERE branch = 'pos3';

  -- Step 1: move changing bills to temporary numbers so no two bills ever share one.
  UPDATE public.orders o
  SET invoice_no = 'TMP' || r.id::TEXT
  FROM _pos3_renumber r
  WHERE o.id = r.id AND r.old_no <> r.new_no;

  -- Step 2: give them their final numbers.
  UPDATE public.orders o
  SET invoice_no = r.new_no,
      invoice_pdf_url = NULL
  FROM _pos3_renumber r
  WHERE o.id = r.id AND r.old_no <> r.new_no;

  -- Stock history and advance orders refer to bills by invoice number.
  FOR r IN SELECT old_no, new_no FROM _pos3_renumber WHERE old_no <> new_no LOOP
    UPDATE public.inventory_movements
    SET reference_id = 'TMP' || r.new_no
    WHERE branch = 'pos3' AND reference_id = r.old_no;
    UPDATE public.advance_orders
    SET invoice_number = 'TMP' || r.new_no
    WHERE branch = 'pos3' AND (invoice_number = r.old_no OR invoice_number = 'INV' || r.old_no);
  END LOOP;
  UPDATE public.inventory_movements SET reference_id = SUBSTRING(reference_id FROM 4)
  WHERE branch = 'pos3' AND reference_id LIKE 'TMP6%';
  UPDATE public.advance_orders SET invoice_number = SUBSTRING(invoice_number FROM 4)
  WHERE branch = 'pos3' AND invoice_number LIKE 'TMP6%';

  -- Keep the old counter in step too (used only as a fallback).
  PERFORM setval('public.invoice_number_seq_pos3',
    COALESCE((SELECT MAX(invoice_no::BIGINT) FROM public.orders
              WHERE branch = 'pos3' AND invoice_no ~ '^6[0-9]{7}$'), 60000000) + 1,
    FALSE);
END $$;

-- Gap-free numbering for POS 3: highest POS 3 number + 1, decided inside the
-- transaction that saves the bill (a per-POS lock stops two tills taking the
-- same number). If the bill fails, the transaction rolls back and the number
-- is free again.
CREATE OR REPLACE FUNCTION public.get_next_invoice_no(p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_next BIGINT;
BEGIN
  IF p_branch = 'pos3' THEN
    PERFORM pg_advisory_xact_lock(hashtext('invoice_no_pos3'));
    SELECT COALESCE(MAX(invoice_no::BIGINT), 60000000) + 1 INTO v_next
    FROM public.orders
    WHERE branch = 'pos3' AND invoice_no ~ '^6[0-9]{7}$';
    RETURN LPAD(v_next::TEXT, 8, '0');
  ELSIF p_branch = 'pos2' THEN
    RETURN LPAD(nextval('public.invoice_number_seq_pos2')::TEXT, 8, '0');
  ELSE
    RETURN LPAD(nextval('public.invoice_number_seq_pos1')::TEXT, 8, '0');
  END IF;
END;
$function$;

-- Result: POS 3 bills in order, and the number the next one will get.
SELECT invoice_no, created_at FROM public.orders WHERE branch = 'pos3' ORDER BY invoice_no;
SELECT LPAD((COALESCE((SELECT MAX(invoice_no::BIGINT) FROM public.orders
         WHERE branch = 'pos3' AND invoice_no ~ '^6[0-9]{7}$'), 60000000) + 1)::TEXT, 8, '0') AS pos3_next_bill;
