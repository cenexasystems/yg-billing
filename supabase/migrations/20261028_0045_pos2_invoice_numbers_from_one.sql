-- ===================================================================
-- Migration 0045: Fireworks (POS 2) invoice numbers start again from 1
-- ===================================================================
--
-- POS 2 bills were numbered 50000001, 50000002, ... From now on the next
-- POS 2 bill is number 1 (stored as 00000001, shown as INV00000001),
-- then 2, 3, ...
--
-- Existing POS 2 bills keep their old 5000xxxx numbers, so old invoice
-- links and records still work.
--
-- Never creates a duplicate: if POS 2 already has bills in the new range
-- (below 10000001), the counter continues after the highest one.
-- POS 1 (10000001 and up) is not touched, and the ranges cannot collide
-- until POS 2 passes ten million bills.
--
-- SAFE / IDEMPOTENT: re-running gives the same result. Runs after 0042,
-- so re-running all migrations in order still ends on this numbering.
-- ===================================================================

BEGIN;

-- Hold off new bills while the counter is being set.
LOCK TABLE public.orders IN SHARE ROW EXCLUSIVE MODE;

SELECT setval(
  'public.invoice_number_seq_pos2',
  COALESCE((
    SELECT MAX(invoice_no::BIGINT) + 1 FROM public.orders
    WHERE branch = 'pos2'
      AND invoice_no ~ '^[0-9]+$'
      AND invoice_no::BIGINT BETWEEN 1 AND 10000000
  ), 1),
  FALSE
);

COMMIT;

-- Shows the next number each POS will use (reads only; uses up nothing).
SELECT
  (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM public.invoice_number_seq_pos1) AS pos1_next_bill,
  (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM public.invoice_number_seq_pos2) AS pos2_next_bill;
