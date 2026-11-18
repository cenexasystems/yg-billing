-- ===================================================================
-- Migration 0047: POS 3 (Christmas POS) as a fully isolated branch
-- ===================================================================
--
-- Adds a third counter, branch id 'pos3', next to 'pos1' and 'pos2'.
-- It follows the isolation design from 0020 / 0032 / 0035:
--   * every branch-scoped table accepts 'pos3' in its branch CHECK
--   * its own invoice-number sequence (60000001+, disjoint from POS 1 at
--     10000001+, and POS 2 at 1.. / 5000xxxx, so orders.invoice_no stays unique)
--   * its own barcode sequences and prefix (P3P / P3V)
--   * the sale / stock / expense / delete RPCs and the branch-integrity
--     triggers resolve 'pos3' instead of silently falling back to 'pos1'
--   * its own store_settings row, expense categories and staff login key
--
-- POS 3 has NO Advance Orders and NO Coupons. That is enforced here in the
-- database, not just in the UI:
--   * advance_orders and coupons keep their ('pos1','pos2') CHECK, so a
--     'pos3' row cannot be written there
--   * a trigger on orders rejects any 'pos3' bill that is an advance order
--     or carries a coupon code / coupon discount
--
-- Also adds an optional wholesale_price to products / product_variants
-- (all branches; NULL = no wholesale price set).
--
-- SAFE / IDEMPOTENT: re-running changes nothing the second time.
-- POS 1 and POS 2 data and behaviour are untouched: the function patches
-- only widen the branch lookup, and every other line is left exactly as is.
-- ===================================================================

-- 1. Sequences --------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq_pos3 START WITH 60000001;
CREATE SEQUENCE IF NOT EXISTS public.barcode_product_seq_pos3 START WITH 10000001;
CREATE SEQUENCE IF NOT EXISTS public.barcode_variant_seq_pos3 START WITH 10000001;

CREATE OR REPLACE FUNCTION public.get_next_invoice_no(p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_branch = 'pos3' THEN
    RETURN LPAD(nextval('public.invoice_number_seq_pos3')::TEXT, 8, '0');
  ELSIF p_branch = 'pos2' THEN
    RETURN LPAD(nextval('public.invoice_number_seq_pos2')::TEXT, 8, '0');
  ELSE
    RETURN LPAD(nextval('public.invoice_number_seq_pos1')::TEXT, 8, '0');
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.generate_barcode_value(p_entity_type TEXT, p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
AS $function$
BEGIN
  IF p_branch = 'pos3' THEN
    IF p_entity_type = 'variant' THEN
      RETURN 'P3V' || LPAD(nextval('public.barcode_variant_seq_pos3')::TEXT, 8, '0');
    ELSE
      RETURN 'P3P' || LPAD(nextval('public.barcode_product_seq_pos3')::TEXT, 8, '0');
    END IF;
  ELSIF p_branch = 'pos2' THEN
    IF p_entity_type = 'variant' THEN
      RETURN 'P2V' || LPAD(nextval('public.barcode_variant_seq_pos2')::TEXT, 8, '0');
    ELSE
      RETURN 'P2P' || LPAD(nextval('public.barcode_product_seq_pos2')::TEXT, 8, '0');
    END IF;
  ELSE
    -- POS 1: unchanged from before the branch split.
    IF p_entity_type = 'variant' THEN
      RETURN 'PBV' || LPAD(nextval('public.barcode_variant_seq')::TEXT, 8, '0');
    ELSE
      RETURN 'PBP' || LPAD(nextval('public.barcode_product_seq')::TEXT, 8, '0');
    END IF;
  END IF;
END;
$function$;

-- 2. Branch CHECK constraints ----------------------------------------
-- Every *_branch_check that currently allows ('pos1','pos2') also allows
-- 'pos3', EXCEPT advance_orders and coupons (POS 3 has neither).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass AS tbl, c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE c.contype = 'c'
      AND n.nspname = 'public'
      AND c.conname LIKE '%\_branch\_check'
      AND pg_get_constraintdef(c.oid) LIKE '%pos2%'
      AND pg_get_constraintdef(c.oid) NOT LIKE '%pos3%'
      AND t.relname NOT IN ('advance_orders', 'coupons')
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (branch IN (''pos1'', ''pos2'', ''pos3''))', r.tbl, r.conname);
  END LOOP;
END $$;

-- Staff login keys: allow the POS 3 staff password override.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'portal_credentials_role_key_check') THEN
    ALTER TABLE public.portal_credentials DROP CONSTRAINT portal_credentials_role_key_check;
  END IF;
  ALTER TABLE public.portal_credentials
    ADD CONSTRAINT portal_credentials_role_key_check
    CHECK (role_key IN ('admin', 'pos1_staff', 'pos2_staff', 'pos3_staff'));
END $$;

-- 3. Branch-aware functions and triggers ------------------------------
-- Widens `CASE WHEN <x> = 'pos2' THEN 'pos2' ELSE 'pos1' END` to also
-- resolve 'pos3', in every public function that uses it. Nothing else in
-- those functions changes. Without this, a 'pos3' sale would silently be
-- written to POS 1.
DO $$
DECLARE
  r RECORD;
  v_def TEXT;
  v_new TEXT;
  v_patched INT := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ~ 'CASE WHEN [A-Za-z_.]+ = ''pos2'' THEN ''pos2'' ELSE ''pos1'' END'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := regexp_replace(
      v_def,
      'CASE WHEN ([A-Za-z_.]+) = ''pos2'' THEN ''pos2'' ELSE ''pos1'' END',
      'CASE WHEN \1 IN (''pos2'', ''pos3'') THEN \1 ELSE ''pos1'' END',
      'g'
    );
    EXECUTE v_new;
    v_patched := v_patched + 1;
    RAISE NOTICE 'patched branch lookup in %', r.proname;
  END LOOP;
  RAISE NOTICE 'branch lookup widened in % function(s)', v_patched;
END $$;

-- 4. POS 3 has no advance orders and no coupons (database-level guard) ---
CREATE OR REPLACE FUNCTION public.reject_pos3_advance_and_coupons()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.branch = 'pos3' THEN
    IF COALESCE(NEW.order_type, '') = 'advance_order' THEN
      RAISE EXCEPTION 'POS 3 (Christmas POS) does not support advance orders';
    END IF;
    IF COALESCE(BTRIM(NEW.coupon_code), '') <> '' OR COALESCE(NEW.discount_amount, 0) > 0 THEN
      RAISE EXCEPTION 'POS 3 (Christmas POS) does not support coupons';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_reject_pos3_advance_and_coupons ON public.orders;
CREATE TRIGGER trg_reject_pos3_advance_and_coupons
  BEFORE INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.reject_pos3_advance_and_coupons();

-- 5. Wholesale price (optional, all branches) -------------------------
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS wholesale_price NUMERIC(12,2);
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS wholesale_price NUMERIC(12,2);

-- 6. POS 3 starter rows -----------------------------------------------
-- store_settings.id is limited to the counters' ids (1, 2); allow 3.
ALTER TABLE public.store_settings DROP CONSTRAINT IF EXISTS store_settings_id_check;
ALTER TABLE public.store_settings ADD CONSTRAINT store_settings_id_check CHECK (id IN (1, 2, 3));

-- Store profile (id 3 follows 1 = POS 1, 2 = POS 2). GST starts off; set the
-- rate in Admin -> Store Settings -> Christmas POS.
INSERT INTO public.store_settings (id, branch, name, owner_name, phone, email, address, business_type, theme_color, gst_enabled)
SELECT 3, 'pos3', s.name, s.owner_name, s.phone, s.email, s.address, 'Christmas Stock', '#1E7B43', FALSE
FROM public.store_settings s
WHERE s.branch = 'pos1'
  AND NOT EXISTS (SELECT 1 FROM public.store_settings WHERE branch = 'pos3')
LIMIT 1;

-- Default expense categories, same names POS 2 starts with.
INSERT INTO public.expense_categories (name, is_active, branch)
SELECT c.name, TRUE, 'pos3'
FROM public.expense_categories c
WHERE c.branch = 'pos2'
  AND NOT EXISTS (
    SELECT 1 FROM public.expense_categories e
    WHERE e.branch = 'pos3' AND LOWER(BTRIM(e.name)) = LOWER(BTRIM(c.name))
  );

-- Verification (reads only) -------------------------------------------
SELECT branch, id, name, business_type, theme_color FROM public.store_settings ORDER BY id;
SELECT sequencename, start_value, last_value FROM pg_sequences WHERE schemaname = 'public' AND sequencename LIKE '%pos3' ORDER BY 1;
