-- ===================================================================
-- ONE-OFF: clear Fireworks (POS 2) sales data, keep stock
-- ===================================================================
--
-- Deletes, for POS 2 ONLY:
--   * all bills (orders) and their line items
--   * advance / deposit orders (with their payments and timeline)
--   * expenses (expense categories are kept)
--   * stock movement history (inventory_movements)
-- and then:
--   * resets coupon "times used" to 0 (coupons themselves are kept)
--   * restarts POS 2 invoice numbers at 1 (next bill = INV00000001)
--
-- KEPT: products, stock quantities, variants, barcodes, categories,
-- coupons, shop settings. POS 1 (Jute & Wedding) is not touched at all.
--
-- Safety: runs in one transaction and stops (rolling everything back)
-- if POS 2 stock totals or any POS 1 row count would change.
--
-- THIS CANNOT BE UNDONE. Run it once, in the Supabase SQL Editor.
-- ===================================================================

BEGIN;

-- Hold off new bills/expenses while clearing.
LOCK TABLE public.orders, public.advance_orders, public.expenses, public.inventory_movements
  IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMP TABLE _before ON COMMIT DROP AS
SELECT
  (SELECT COALESCE(SUM(stock_quantity), 0) FROM public.products WHERE branch = 'pos2') AS pos2_product_stock,
  (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE branch = 'pos2') AS pos2_variant_stock,
  (SELECT COUNT(*) FROM public.orders WHERE branch = 'pos1') AS pos1_orders,
  (SELECT COUNT(*) FROM public.advance_orders WHERE branch = 'pos1') AS pos1_advance,
  (SELECT COUNT(*) FROM public.expenses WHERE branch = 'pos1') AS pos1_expenses,
  (SELECT COUNT(*) FROM public.inventory_movements WHERE branch = 'pos1') AS pos1_movements;

-- Advance orders first (their payments/timeline cascade), then bills.
DELETE FROM public.advance_orders WHERE branch = 'pos2';
DELETE FROM public.order_items
  WHERE order_id IN (SELECT id FROM public.orders WHERE branch = 'pos2');
DELETE FROM public.orders WHERE branch = 'pos2';
DELETE FROM public.expenses WHERE branch = 'pos2';
DELETE FROM public.inventory_movements WHERE branch = 'pos2';

-- The bills that used the coupons are gone.
UPDATE public.coupons SET usage_count = 0 WHERE branch = 'pos2';

-- Invoice numbers start again at 1 (no POS 2 bills remain).
SELECT setval('public.invoice_number_seq_pos2', 1, FALSE);

-- Stop and undo everything if stock or POS 1 data would change.
DO $$
DECLARE b RECORD;
BEGIN
  SELECT * INTO b FROM _before;
  IF b.pos2_product_stock <> (SELECT COALESCE(SUM(stock_quantity), 0) FROM public.products WHERE branch = 'pos2')
     OR b.pos2_variant_stock <> (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE branch = 'pos2') THEN
    RAISE EXCEPTION 'POS 2 stock would change - nothing was deleted';
  END IF;
  IF b.pos1_orders <> (SELECT COUNT(*) FROM public.orders WHERE branch = 'pos1')
     OR b.pos1_advance <> (SELECT COUNT(*) FROM public.advance_orders WHERE branch = 'pos1')
     OR b.pos1_expenses <> (SELECT COUNT(*) FROM public.expenses WHERE branch = 'pos1')
     OR b.pos1_movements <> (SELECT COUNT(*) FROM public.inventory_movements WHERE branch = 'pos1') THEN
    RAISE EXCEPTION 'POS 1 data would change - nothing was deleted';
  END IF;
END $$;

COMMIT;

-- Result: everything below should be 0, and the next bill number 1.
SELECT
  (SELECT COUNT(*) FROM public.orders WHERE branch = 'pos2') AS pos2_bills,
  (SELECT COUNT(*) FROM public.advance_orders WHERE branch = 'pos2') AS pos2_advance_orders,
  (SELECT COUNT(*) FROM public.expenses WHERE branch = 'pos2') AS pos2_expenses,
  (SELECT COUNT(*) FROM public.inventory_movements WHERE branch = 'pos2') AS pos2_stock_history,
  (SELECT COUNT(*) FROM public.products WHERE branch = 'pos2') AS pos2_products_kept,
  (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM public.invoice_number_seq_pos2) AS pos2_next_bill;
