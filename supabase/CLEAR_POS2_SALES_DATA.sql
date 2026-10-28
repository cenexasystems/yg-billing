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
-- Safety: runs as one statement and stops (rolling everything back)
-- if POS 2 stock totals or any POS 1 row count would change.
--
-- Already run once on 2026-10-28.
--
-- THIS CANNOT BE UNDONE. Run it once, in the Supabase SQL Editor.
-- ===================================================================

-- Everything runs inside ONE DO block, so the Supabase SQL Editor treats it
-- as a single statement and the safety check can roll it all back.
DO $$
DECLARE
  v_p2_prod NUMERIC; v_p2_var NUMERIC;
  v_p1_orders BIGINT; v_p1_adv BIGINT; v_p1_exp BIGINT; v_p1_mov BIGINT;
BEGIN
  -- Hold off new bills/expenses while clearing.
  LOCK TABLE public.orders, public.advance_orders, public.expenses, public.inventory_movements
    IN SHARE ROW EXCLUSIVE MODE;

  SELECT COALESCE(SUM(stock_quantity), 0) INTO v_p2_prod FROM public.products WHERE branch = 'pos2';
  SELECT COALESCE(SUM(stock), 0) INTO v_p2_var FROM public.product_variants WHERE branch = 'pos2';
  SELECT COUNT(*) INTO v_p1_orders FROM public.orders WHERE branch = 'pos1';
  SELECT COUNT(*) INTO v_p1_adv FROM public.advance_orders WHERE branch = 'pos1';
  SELECT COUNT(*) INTO v_p1_exp FROM public.expenses WHERE branch = 'pos1';
  SELECT COUNT(*) INTO v_p1_mov FROM public.inventory_movements WHERE branch = 'pos1';

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
  PERFORM setval('public.invoice_number_seq_pos2', 1, FALSE);

  -- Stop and undo everything if stock or POS 1 data would change.
  IF v_p2_prod <> (SELECT COALESCE(SUM(stock_quantity), 0) FROM public.products WHERE branch = 'pos2')
     OR v_p2_var <> (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE branch = 'pos2') THEN
    RAISE EXCEPTION 'POS 2 stock would change - nothing was deleted';
  END IF;
  IF v_p1_orders <> (SELECT COUNT(*) FROM public.orders WHERE branch = 'pos1')
     OR v_p1_adv <> (SELECT COUNT(*) FROM public.advance_orders WHERE branch = 'pos1')
     OR v_p1_exp <> (SELECT COUNT(*) FROM public.expenses WHERE branch = 'pos1')
     OR v_p1_mov <> (SELECT COUNT(*) FROM public.inventory_movements WHERE branch = 'pos1') THEN
    RAISE EXCEPTION 'POS 1 data would change - nothing was deleted';
  END IF;
END $$;

-- Result: everything below should be 0, and the next bill number 1.
SELECT
  (SELECT COUNT(*) FROM public.orders WHERE branch = 'pos2') AS pos2_bills,
  (SELECT COUNT(*) FROM public.advance_orders WHERE branch = 'pos2') AS pos2_advance_orders,
  (SELECT COUNT(*) FROM public.expenses WHERE branch = 'pos2') AS pos2_expenses,
  (SELECT COUNT(*) FROM public.inventory_movements WHERE branch = 'pos2') AS pos2_stock_history,
  (SELECT COUNT(*) FROM public.products WHERE branch = 'pos2') AS pos2_products_kept,
  (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM public.invoice_number_seq_pos2) AS pos2_next_bill;
