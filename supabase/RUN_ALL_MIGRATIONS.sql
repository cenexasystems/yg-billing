-- ====================================================================
-- COMBINED MIGRATION: run this single file in the Supabase SQL Editor
-- !! FOR A BRAND-NEW, EMPTY DATABASE ONLY. !!
-- This file REPLAYS the entire history from 0001. Running it against a
-- database that is already populated will re-execute old seeds and
-- re-apply historical UPDATEs. In particular, 0024's catalog section
-- carries an unconditional DELETE scoped to POS 2 - the seed_ledger
-- guards added in 0036 stop that from firing on a re-run, but only once
-- 0036 has been applied. On a live database, apply the individual
-- migrations/supabase/migrations/*.sql you actually need instead.
--
-- Contains the ENTIRE migration history for this project, in filename
-- order, from the base schema through the POS1/POS2 branch split,
-- CHAJI data cleanup, starter catalog seed, staff attendance, the POS1/POS2
-- branch-isolation hardening and the POS 1 store-identity repair.
--
-- Use this if your Supabase project is EMPTY (no `products`/`orders`
-- tables yet) â€” running only the later branch-split files will fail
-- with "relation ... does not exist" otherwise, since they only ALTER
-- tables that the base schema (section 1) creates.
--
-- Each original file keeps its own BEGIN/COMMIT block, so this still
-- runs as N sequential transactions, exactly as if you'd pasted every
-- file in supabase/migrations/ one by one in order. Safe to re-run in
-- full from the top at any point (every statement is idempotent via
-- IF NOT EXISTS / IF EXISTS / ON CONFLICT / DROP-before-CREATE guards).
-- ====================================================================

-- ============================================================
-- SECTION 1 / 32 â€” 20260716_0001_purple_boutique_schema.sql
-- ============================================================

-- YG Enterprises billing schema.
-- Safe to run against a fresh project or the existing YG Enterprises project.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  customer_code TEXT UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  mobile TEXT NOT NULL DEFAULT '',
  email TEXT,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('admin', 'customer')),
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE SEQUENCE IF NOT EXISTS public.customer_code_seq START WITH 1;

CREATE TABLE IF NOT EXISTS public.categories (
  id BIGSERIAL PRIMARY KEY,
  name_en TEXT NOT NULL UNIQUE,
  name_ta TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.products (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  name_ta TEXT NOT NULL DEFAULT '',
  tamil_name TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  category_id BIGINT REFERENCES public.categories(id) ON DELETE SET NULL,
  remedy TEXT[] NOT NULL DEFAULT '{}',
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  offer_price NUMERIC(12,2),
  purchase_price NUMERIC(12,2) NOT NULL DEFAULT 0,
  mrp NUMERIC(12,2) NOT NULL DEFAULT 0,
  gst_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
  unit_type TEXT NOT NULL DEFAULT 'unit' CHECK (unit_type IN ('unit', 'weight', 'volume', 'bundle')),
  unit_label TEXT NOT NULL DEFAULT 'piece',
  unit TEXT NOT NULL DEFAULT 'piece',
  base_quantity NUMERIC(12,3) NOT NULL DEFAULT 1,
  stock_quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
  opening_stock NUMERIC(12,3) NOT NULL DEFAULT 0,
  stock INTEGER NOT NULL DEFAULT 0,
  stock_unit TEXT NOT NULL DEFAULT 'piece',
  low_stock_alert NUMERIC(12,3) NOT NULL DEFAULT 5,
  allow_decimal_quantity BOOLEAN NOT NULL DEFAULT FALSE,
  predefined_options JSONB NOT NULL DEFAULT '[]'::JSONB,
  description TEXT NOT NULL DEFAULT '',
  description_ta TEXT NOT NULL DEFAULT '',
  benefits TEXT NOT NULL DEFAULT '',
  benefits_ta TEXT NOT NULL DEFAULT '',
  image TEXT,
  image_url TEXT,
  sku TEXT,
  barcode TEXT,
  brand TEXT,
  supplier TEXT,
  size TEXT,
  color TEXT,
  rating NUMERIC(3,1) NOT NULL DEFAULT 5,
  has_variants BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS products_category_name_unique
  ON public.products (category_id, LOWER(BTRIM(name)))
  WHERE is_active = true;

CREATE TABLE IF NOT EXISTS public.product_variants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id BIGINT NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  variant_name TEXT NOT NULL,
  size_label TEXT,
  weight_value NUMERIC(12,3),
  weight_unit TEXT,
  sku TEXT,
  barcode TEXT,
  purchase_price NUMERIC(12,2),
  mrp NUMERIC(12,2),
  price NUMERIC(12,2) NOT NULL DEFAULT 0,
  stock NUMERIC(12,3) NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  image_url TEXT,
  group_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS product_variants_product_name_unique
  ON public.product_variants (product_id, LOWER(BTRIM(variant_name)))
  WHERE is_active = true;

CREATE TABLE IF NOT EXISTS public.coupons (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL,
  percentage NUMERIC(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 100),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  expiry_date TIMESTAMPTZ,
  usage_limit INTEGER CHECK (usage_limit IS NULL OR usage_limit > 0),
  usage_count INTEGER NOT NULL DEFAULT 0 CHECK (usage_count >= 0),
  min_order_value NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS coupons_code_upper_unique ON public.coupons (UPPER(BTRIM(code)));

CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_no TEXT NOT NULL UNIQUE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  customer_name TEXT NOT NULL DEFAULT 'Customer',
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  items JSONB NOT NULL DEFAULT '[]'::JSONB,
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  shipping NUMERIC(12,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  order_mode TEXT NOT NULL DEFAULT 'offline',
  order_type TEXT NOT NULL DEFAULT 'pos_sale',
  delivery_charge NUMERIC(12,2) NOT NULL DEFAULT 0,
  discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  manual_discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  manual_discount_type TEXT NOT NULL DEFAULT 'flat',
  manual_discount_value NUMERIC(12,2) NOT NULL DEFAULT 0,
  coupon_code TEXT,
  coupon_percentage NUMERIC(5,2) NOT NULL DEFAULT 0,
  total_gst NUMERIC(12,2) NOT NULL DEFAULT 0,
  gst_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  gst_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  payment_method TEXT NOT NULL DEFAULT 'cash',
  payment_mode TEXT NOT NULL DEFAULT 'cash',
  split_details JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.order_items (
  id BIGSERIAL PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id BIGINT REFERENCES public.products(id) ON DELETE SET NULL,
  variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
  product_name TEXT NOT NULL DEFAULT 'Product',
  name TEXT NOT NULL DEFAULT 'Product',
  product_tamil_name TEXT,
  tamil_name TEXT,
  quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
  unit TEXT NOT NULL DEFAULT 'piece',
  unit_type TEXT NOT NULL DEFAULT 'unit',
  base_quantity NUMERIC(12,3) NOT NULL DEFAULT 1,
  base_price NUMERIC(12,2) NOT NULL DEFAULT 0,
  line_total NUMERIC(12,2) NOT NULL DEFAULT 0,
  image_url TEXT,
  is_manual BOOLEAN NOT NULL DEFAULT FALSE,
  discount NUMERIC(12,2) NOT NULL DEFAULT 0,
  gst_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  gst_rate NUMERIC(5,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.invoice_counter (
  id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  counter BIGINT NOT NULL DEFAULT 0,
  year INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM NOW())::INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.invoice_counter (id, counter, year)
VALUES (1, 0, EXTRACT(YEAR FROM NOW())::INTEGER)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.store_settings (
  id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  name TEXT NOT NULL DEFAULT 'YG Enterprises',
  owner_name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '+60 11-3312 7107',
  email TEXT NOT NULL DEFAULT 'mypurpleboutique05@gmail.com',
  address TEXT NOT NULL DEFAULT 'FR-02-05A TAMARIND SUITE, Persiaran Multimedia, CYBER 10, 63000 Cyberjaya, Selangor',
  gst_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed the default profile only when the row does not exist yet.
-- WHY NOT "DO UPDATE ...": this ran on every re-run and reset id = 1 back to
-- these Purple Boutique / Cyberjaya defaults, which re-armed the retired
-- CLAD seed in section 12 and silently wiped any profile the owner had saved
-- from Admin -> Store Settings. A seed must never clobber live data.
INSERT INTO public.store_settings (id, name, phone, email, address)
VALUES (
  1,
  'YG Enterprises',
  '+60 11-3312 7107',
  'mypurpleboutique05@gmail.com',
  'FR-02-05A TAMARIND SUITE, Persiaran Multimedia, CYBER 10, 63000 Cyberjaya, Selangor'
)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := CASE WHEN COALESCE(NEW.raw_user_meta_data ->> 'role', '') = 'admin' THEN 'admin' ELSE 'customer' END;
BEGIN
  INSERT INTO public.profiles (id, customer_code, name, mobile, email, role)
  VALUES (
    NEW.id,
    'CUST-' || LPAD(nextval('public.customer_code_seq')::TEXT, 5, '0'),
    COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'name'), ''), split_part(COALESCE(NEW.email, ''), '@', 1), 'Customer'),
    COALESCE(NEW.raw_user_meta_data ->> 'mobile', ''),
    NEW.email,
    v_role
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    mobile = EXCLUDED.mobile,
    email = EXCLUDED.email,
    updated_at = NOW();

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::JSONB) || jsonb_build_object('role', v_role)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION public.sync_product_category_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.category_id IS NOT NULL THEN
    SELECT name_en INTO NEW.category FROM public.categories WHERE id = NEW.category_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_product_category_name_trigger ON public.products;
CREATE TRIGGER sync_product_category_name_trigger
BEFORE INSERT OR UPDATE OF category_id ON public.products
FOR EACH ROW EXECUTE FUNCTION public.sync_product_category_name();

CREATE OR REPLACE FUNCTION public.sync_category_name_to_products()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.name_en IS DISTINCT FROM OLD.name_en THEN
    UPDATE public.products SET category = NEW.name_en, updated_at = NOW() WHERE category_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_category_name_to_products_trigger ON public.categories;
CREATE TRIGGER sync_category_name_to_products_trigger
AFTER UPDATE OF name_en ON public.categories
FOR EACH ROW EXECUTE FUNCTION public.sync_category_name_to_products();

CREATE OR REPLACE FUNCTION public.ensure_one_default_variant()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.is_default THEN
    UPDATE public.product_variants
    SET is_default = FALSE, updated_at = NOW()
    WHERE product_id = NEW.product_id AND id <> NEW.id AND is_default;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ensure_one_default_variant_trigger ON public.product_variants;
CREATE TRIGGER ensure_one_default_variant_trigger
AFTER INSERT OR UPDATE OF is_default ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.ensure_one_default_variant();

CREATE OR REPLACE FUNCTION public.get_next_invoice_no()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year INTEGER := EXTRACT(YEAR FROM NOW())::INTEGER;
  v_counter BIGINT;
  v_existing_max BIGINT;
BEGIN
  SELECT COALESCE(MAX(SUBSTRING(invoice_no FROM '^PB-' || v_year || '-([0-9]+)$')::BIGINT), 0)
  INTO v_existing_max
  FROM public.orders
  WHERE invoice_no ~ ('^PB-' || v_year || '-[0-9]+$');

  INSERT INTO public.invoice_counter (id, counter, year)
  VALUES (1, 1, v_year)
  ON CONFLICT (id) DO UPDATE SET
    counter = CASE
      WHEN public.invoice_counter.year = v_year
        THEN GREATEST(public.invoice_counter.counter, v_existing_max) + 1
      ELSE 1
    END,
    year = v_year,
    updated_at = NOW()
  RETURNING counter INTO v_counter;

  RETURN 'PB-' || v_year || '-' || LPAD(v_counter::TEXT, 6, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.create_order_with_stock(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'pending',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC(12,2) := 0;
  v_total NUMERIC(12,2);
  v_item JSONB;
  v_product_id BIGINT;
  v_variant_id UUID;
  v_attempt INTEGER;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one order item is required';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_subtotal := v_subtotal + COALESCE((v_item ->> 'line_total')::NUMERIC, 0);
  END LOOP;

  v_total := GREATEST(
    0,
    v_subtotal + COALESCE(p_total_gst, 0) + COALESCE(p_delivery_charge, 0) + COALESCE(p_shipping, 0)
      - COALESCE(p_discount_amount, 0) - COALESCE(p_manual_discount_amount, 0)
  );

  FOR v_attempt IN 1..5 LOOP
    v_invoice_no := public.get_next_invoice_no();
    BEGIN
      INSERT INTO public.orders (
        invoice_no, user_id, customer_name, phone, address, items, subtotal, shipping, total,
        status, order_mode, order_type, delivery_charge, discount_amount, manual_discount_amount,
        manual_discount_type, manual_discount_value, coupon_code, coupon_percentage, total_gst,
        gst_amount, gst_enabled, payment_method, payment_mode, split_details
      ) VALUES (
        v_invoice_no, auth.uid(), COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Customer'),
        COALESCE(BTRIM(p_phone), ''), COALESCE(BTRIM(p_address), ''), p_items, v_subtotal,
        COALESCE(p_shipping, 0), v_total, COALESCE(NULLIF(BTRIM(p_status), ''), 'pending'),
        COALESCE(NULLIF(BTRIM(p_order_mode), ''), 'offline'), COALESCE(NULLIF(BTRIM(p_order_type), ''), 'pos_sale'),
        COALESCE(p_delivery_charge, 0), COALESCE(p_discount_amount, 0), COALESCE(p_manual_discount_amount, 0),
        COALESCE(NULLIF(BTRIM(p_manual_discount_type), ''), 'flat'), COALESCE(p_manual_discount_value, 0),
        NULLIF(BTRIM(COALESCE(p_coupon_code, '')), ''), COALESCE(p_coupon_percentage, 0),
        COALESCE(p_total_gst, 0), COALESCE(p_total_gst, 0), COALESCE(p_gst_enabled, FALSE),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'), COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(p_split_details, '{}'::JSONB)
      ) RETURNING id INTO v_order_id;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt = 5 THEN RAISE; END IF;
    END;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name, product_tamil_name, tamil_name,
      quantity, unit, unit_type, base_quantity, base_price, line_total, image_url, is_manual,
      discount, gst_amount, gst_rate
    ) VALUES (
      v_order_id, v_product_id, v_variant_id,
      COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'), COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
      NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'tamil_name', ''),
      COALESCE((v_item ->> 'quantity')::NUMERIC, 0), COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'),
      COALESCE(NULLIF(v_item ->> 'unit_type', ''), 'unit'), COALESCE((v_item ->> 'base_quantity')::NUMERIC, 1),
      COALESCE((v_item ->> 'base_price')::NUMERIC, 0), COALESCE((v_item ->> 'line_total')::NUMERIC, 0),
      NULLIF(v_item ->> 'image_url', ''), COALESCE(v_item ->> 'source' = 'manual', FALSE),
      COALESCE((v_item ->> 'discount')::NUMERIC, 0), COALESCE((v_item ->> 'gst_amount')::NUMERIC, 0),
      COALESCE((v_item ->> 'gst_rate')::NUMERIC, 0)
    );

    IF v_product_id IS NOT NULL THEN
      UPDATE public.products
      SET stock_quantity = GREATEST(stock_quantity - COALESCE((v_item ->> 'quantity')::NUMERIC, 0), 0),
          stock = GREATEST(FLOOR(stock_quantity - COALESCE((v_item ->> 'quantity')::NUMERIC, 0)), 0)::INTEGER,
          updated_at = NOW()
      WHERE id = v_product_id;
    END IF;

    IF v_variant_id IS NOT NULL THEN
      UPDATE public.product_variants
      SET stock = GREATEST(stock - COALESCE((v_item ->> 'quantity')::NUMERIC, 0), 0), updated_at = NOW()
      WHERE id = v_variant_id;
    END IF;
  END LOOP;

  IF NULLIF(BTRIM(COALESCE(p_coupon_code, '')), '') IS NOT NULL THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1, updated_at = NOW()
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code))
      AND is_active
      AND (usage_limit IS NULL OR usage_count < usage_limit);
  END IF;

  RETURN jsonb_build_object('orderId', v_order_id, 'invoiceNo', v_invoice_no, 'createdAt', NOW());
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_invoice_by_number(p_invoice_no TEXT)
RETURNS SETOF public.orders
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM public.orders WHERE invoice_no = NULLIF(BTRIM(p_invoice_no), '') LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_public_invoice_by_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_invoice_by_number(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_order_with_stock(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB
) TO anon, authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_portal_manage ON public.profiles;
CREATE POLICY profiles_portal_manage ON public.profiles FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS categories_portal_manage ON public.categories;
CREATE POLICY categories_portal_manage ON public.categories FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS products_portal_manage ON public.products;
CREATE POLICY products_portal_manage ON public.products FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS product_variants_portal_manage ON public.product_variants;
CREATE POLICY product_variants_portal_manage ON public.product_variants FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS coupons_portal_manage ON public.coupons;
CREATE POLICY coupons_portal_manage ON public.coupons FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS orders_portal_manage ON public.orders;
CREATE POLICY orders_portal_manage ON public.orders FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS order_items_portal_manage ON public.order_items;
CREATE POLICY order_items_portal_manage ON public.order_items FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS store_settings_portal_manage ON public.store_settings;
CREATE POLICY store_settings_portal_manage ON public.store_settings FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('invoices', 'invoices', TRUE, 10485760, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = TRUE, file_size_limit = 10485760, allowed_mime_types = ARRAY['application/pdf'];

DROP POLICY IF EXISTS invoices_public_read ON storage.objects;
CREATE POLICY invoices_public_read ON storage.objects FOR SELECT TO public USING (bucket_id = 'invoices');
DROP POLICY IF EXISTS invoices_portal_upload ON storage.objects;
CREATE POLICY invoices_portal_upload ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK (bucket_id = 'invoices');
DROP POLICY IF EXISTS invoices_portal_update ON storage.objects;
CREATE POLICY invoices_portal_update ON storage.objects FOR UPDATE TO anon, authenticated USING (bucket_id = 'invoices') WITH CHECK (bucket_id = 'invoices');

CREATE INDEX IF NOT EXISTS products_category_id_idx ON public.products(category_id);
CREATE INDEX IF NOT EXISTS products_active_sort_idx ON public.products(is_active, sort_order);
CREATE INDEX IF NOT EXISTS variants_product_id_idx ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS orders_created_at_idx ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS orders_phone_idx ON public.orders(phone);
CREATE INDEX IF NOT EXISTS order_items_order_id_idx ON public.order_items(order_id);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

-- ============================================================
-- SECTION 2 / 32 â€” 20260716_0002_purple_boutique_catalog.sql
-- ============================================================

-- YG Enterprises initial catalog. Existing matching products are preserved.
--
-- ============================================================================
-- IDEMPOTENCE / DELETION SAFETY  (see migration 0036)
-- ============================================================================
-- An earlier version guarded the product insert with a NAME-based
-- `WHERE NOT EXISTS (SELECT 1 FROM products WHERE <same name>)` check.
-- That guard is name-based, not run-based: once an operator DELETES a
-- seeded product the row is gone, the NOT EXISTS check passes again, and
-- re-running this file silently RE-CREATED the deleted product at its
-- placeholder price and 999 opening stock. Deleting a catalog item was
-- therefore not durable.
--
-- Every statement below is now additionally gated on public.seed_ledger, a
-- run-once marker table created by migration 0036. Once this seed has run
-- once, re-running the file is a complete no-op no matter what has since
-- been deleted, so operator deletions stay permanent.
--
-- On a brand-new database public.seed_ledger does not exist yet (0036 has
-- not run), so the DO block below creates it empty, the marker row is absent,
-- and all guards evaluate to TRUE -- the seed runs normally.
-- ============================================================================

-- Marker row for THIS seed. The plpgsql DO block only creates the table
-- when it is missing (fresh-database bootstrap) and never inserts the
-- marker itself, so the guards below decide whether the seed runs.
DO $$
BEGIN
  IF to_regclass('public.seed_ledger') IS NULL THEN
    CREATE TABLE public.seed_ledger (
      seed_key   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  END IF;
END $$;

INSERT INTO public.categories (name_en, name_ta, is_active, sort_order)
SELECT v.name_en, v.name_ta, TRUE, v.sort_order
FROM (VALUES
  ('Tailoring', '', 1),
  ('Jewellery & Accessories', '', 2),
  ('Posstore', '', 3)
) AS v(name_en, name_ta, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260716_0002_purple_boutique_catalog'
)
-- A name guard, not ON CONFLICT (name_en): migration 0039 makes category
-- names unique per POS branch, so a replay of this file after 0039 would
-- otherwise fail with 42P10 (no matching unique constraint).
AND NOT EXISTS (
  SELECT 1 FROM public.categories c
  WHERE LOWER(BTRIM(c.name_en)) = LOWER(BTRIM(v.name_en))
);

WITH catalog(category_name, product_name, sort_order) AS (
  VALUES
    ('Tailoring', 'Saree Blouse', 101),
    ('Tailoring', 'Saree Blouse + Cup', 102),
    ('Tailoring', 'Readymade Saree', 103),
    ('Tailoring', 'Punjabi Suit', 104),
    ('Tailoring', 'Punjabi Suit + Salwar', 105),
    ('Tailoring', 'Baju Kurung', 106),
    ('Tailoring', 'Baju Kebaya', 107),
    ('Tailoring', 'Baju Melaya', 108),
    ('Tailoring', 'Lehelga', 109),
    ('Tailoring', 'Alterations', 110),
    ('Tailoring', 'Pavadai Sattai', 111),
    ('Tailoring', 'Designs', 112),
    ('Tailoring', 'Add-ons', 113),
    ('Jewellery & Accessories', 'Earrings', 201),
    ('Jewellery & Accessories', 'Bridal Jewellery Rent', 202),
    ('Jewellery & Accessories', 'Choker Set', 203),
    ('Jewellery & Accessories', 'Anklet', 204),
    ('Jewellery & Accessories', 'Add-ons', 205),
    ('Posstore', 'Claim Parcel', 301),
    ('Posstore', 'Perfume', 302),
    ('Posstore', 'Add-ons', 303)
), resolved AS (
  SELECT c.id AS category_id, c.name_en AS category_name, catalog.product_name, catalog.sort_order
  FROM catalog
  JOIN public.categories c ON LOWER(c.name_en) = LOWER(catalog.category_name)
)
INSERT INTO public.products (
  name, category, category_id, price, purchase_price, mrp, unit_type, unit_label,
  unit, base_quantity, stock_quantity, opening_stock, stock, stock_unit,
  allow_decimal_quantity, predefined_options, description, is_active, sort_order
)
SELECT
  resolved.product_name,
  resolved.category_name,
  resolved.category_id,
  0,
  0,
  0,
  'unit',
  'piece',
  'piece',
  1,
  999,
  999,
  999,
  'piece',
  FALSE,
  '[]'::JSONB,
  resolved.product_name || ' service or product',
  TRUE,
  resolved.sort_order
FROM resolved
WHERE NOT EXISTS (
  SELECT 1
  FROM public.products p
  WHERE p.category_id = resolved.category_id
    AND LOWER(BTRIM(p.name)) = LOWER(BTRIM(resolved.product_name))
)
AND NOT EXISTS (
  SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260716_0002_purple_boutique_catalog'
);

UPDATE public.products p
SET is_active = TRUE,
    category = c.name_en,
    updated_at = NOW()
FROM public.categories c
WHERE p.category_id = c.id
  AND c.name_en IN ('Tailoring', 'Jewellery & Accessories', 'Posstore')
  AND NOT EXISTS (
    SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260716_0002_purple_boutique_catalog'
  );

WITH catalog(category_name, product_name, sort_order) AS (
  VALUES
    ('Tailoring', 'Saree Blouse', 101),
    ('Tailoring', 'Saree Blouse + Cup', 102),
    ('Tailoring', 'Readymade Saree', 103),
    ('Tailoring', 'Punjabi Suit', 104),
    ('Tailoring', 'Punjabi Suit + Salwar', 105),
    ('Tailoring', 'Baju Kurung', 106),
    ('Tailoring', 'Baju Kebaya', 107),
    ('Tailoring', 'Baju Melaya', 108),
    ('Tailoring', 'Lehelga', 109),
    ('Tailoring', 'Alterations', 110),
    ('Tailoring', 'Pavadai Sattai', 111),
    ('Tailoring', 'Designs', 112),
    ('Tailoring', 'Add-ons', 113),
    ('Jewellery & Accessories', 'Earrings', 201),
    ('Jewellery & Accessories', 'Bridal Jewellery Rent', 202),
    ('Jewellery & Accessories', 'Choker Set', 203),
    ('Jewellery & Accessories', 'Anklet', 204),
    ('Jewellery & Accessories', 'Add-ons', 205),
    ('Posstore', 'Claim Parcel', 301),
    ('Posstore', 'Perfume', 302),
    ('Posstore', 'Add-ons', 303)
)
UPDATE public.products p
SET name = catalog.product_name,
    sort_order = catalog.sort_order,
    updated_at = NOW()
FROM catalog
JOIN public.categories c ON LOWER(c.name_en) = LOWER(catalog.category_name)
WHERE p.category_id = c.id
  AND LOWER(BTRIM(p.name)) = LOWER(BTRIM(catalog.product_name))
  AND NOT EXISTS (
    SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260716_0002_purple_boutique_catalog'
  );

-- Mark this seed as applied. From now on every guard above is a no-op, so a
-- future re-run can never resurrect a product an operator has deleted.
INSERT INTO public.seed_ledger (seed_key)
VALUES ('20260716_0002_purple_boutique_catalog')
ON CONFLICT (seed_key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 3 / 32 â€” 20260716_0003_order_rpc_compatibility.sql
-- ============================================================

-- Align the live legacy billing schema with the current YG Enterprises RPC payload.
-- Idempotent: safe for both upgraded and freshly migrated projects.

BEGIN;

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS gst_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS split_details JSONB NOT NULL DEFAULT '{}'::JSONB;

-- Keep one order-item shape that works with both the legacy and current schemas.
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS variant_name TEXT;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'catalogue';
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS note TEXT;

CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq;

-- Prevent collisions when a sequence is introduced after invoices already exist.
DO $$
DECLARE
  v_max_suffix BIGINT;
  v_sequence_value BIGINT;
BEGIN
  SELECT COALESCE(MAX((regexp_match(invoice_no, '-([0-9]+)$'))[1]::BIGINT), 0)
  INTO v_max_suffix
  FROM public.orders
  WHERE invoice_no ~ '-[0-9]+$';

  SELECT last_value INTO v_sequence_value FROM public.invoice_number_seq;
  PERFORM setval(
    'public.invoice_number_seq',
    GREATEST(v_max_suffix, v_sequence_value, 1),
    TRUE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_next_invoice_no()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
VOLATILE
AS $$
  SELECT 'PB-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
         LPAD(nextval('public.invoice_number_seq')::TEXT, 6, '0');
$$;

CREATE OR REPLACE FUNCTION public.create_order_with_stock(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'pending',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC(12,2) := 0;
  v_total NUMERIC(12,2);
  v_item JSONB;
  v_quantity NUMERIC(12,3);
  v_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_source TEXT;
  v_attempt INTEGER;
  v_uses_typed_item_ids BOOLEAN;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one order item is required';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_quantity := GREATEST(COALESCE(NULLIF(v_item ->> 'quantity', '')::NUMERIC, 0), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_item ->> 'base_price', '')::NUMERIC, 0), 0);
    v_line_total := GREATEST(
      COALESCE(NULLIF(v_item ->> 'line_total', '')::NUMERIC, v_quantity * v_price),
      0
    );

    IF v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero';
    END IF;

    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(
    ROUND(
      v_subtotal + GREATEST(COALESCE(p_shipping, 0), 0)
        + GREATEST(COALESCE(p_delivery_charge, 0), 0)
        + GREATEST(COALESCE(p_total_gst, 0), 0)
        - GREATEST(COALESCE(p_discount_amount, 0), 0)
        - GREATEST(COALESCE(p_manual_discount_amount, 0), 0),
      2
    ),
    0
  );

  SELECT data_type = 'bigint'
  INTO v_uses_typed_item_ids
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'order_items' AND column_name = 'product_id';

  FOR v_attempt IN 1..5 LOOP
    v_invoice_no := public.get_next_invoice_no();
    v_order_id := gen_random_uuid();

    BEGIN
      INSERT INTO public.orders (
        id, invoice_no, user_id, customer_name, phone, address, items, subtotal, shipping, total,
        status, order_mode, order_type, delivery_charge, discount_amount, manual_discount_amount,
        manual_discount_type, manual_discount_value, coupon_code, coupon_percentage, total_gst,
        gst_amount, gst_enabled, payment_method, payment_mode, split_details, created_at, updated_at
      ) VALUES (
        v_order_id, v_invoice_no, auth.uid(),
        COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Walk-in Customer'),
        COALESCE(BTRIM(p_phone), ''), COALESCE(NULLIF(BTRIM(p_address), ''), 'POS Counter'),
        p_items, v_subtotal, GREATEST(COALESCE(p_shipping, 0), 0), v_total,
        COALESCE(NULLIF(BTRIM(p_status), ''), 'pending'),
        COALESCE(NULLIF(BTRIM(p_order_mode), ''), 'offline'),
        COALESCE(NULLIF(BTRIM(p_order_type), ''), 'pos_sale'),
        GREATEST(COALESCE(p_delivery_charge, 0), 0),
        GREATEST(COALESCE(p_discount_amount, 0), 0),
        GREATEST(COALESCE(p_manual_discount_amount, 0), 0),
        COALESCE(NULLIF(BTRIM(p_manual_discount_type), ''), 'flat'),
        GREATEST(COALESCE(p_manual_discount_value, 0), 0),
        NULLIF(BTRIM(COALESCE(p_coupon_code, '')), ''),
        GREATEST(COALESCE(p_coupon_percentage, 0), 0),
        GREATEST(COALESCE(p_total_gst, 0), 0), GREATEST(COALESCE(p_total_gst, 0), 0),
        COALESCE(p_gst_enabled, FALSE),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(p_split_details, '{}'::JSONB), NOW(), NOW()
      );
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt = 5 THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_quantity := GREATEST(COALESCE(NULLIF(v_item ->> 'quantity', '')::NUMERIC, 0), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_item ->> 'base_price', '')::NUMERIC, 0), 0);
    v_line_total := GREATEST(
      COALESCE(NULLIF(v_item ->> 'line_total', '')::NUMERIC, v_quantity * v_price),
      0
    );
    v_source := COALESCE(NULLIF(v_item ->> 'source', ''), 'catalogue');

    IF v_uses_typed_item_ids THEN
      INSERT INTO public.order_items (
        order_id, product_id, variant_id, product_name, tamil_name, variant_name,
        quantity, unit, unit_price, line_total, is_manual, source, note
      ) VALUES (
        v_order_id, NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), '')::BIGINT,
        NULLIF(v_item ->> 'variant_id', '')::UUID, COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
        NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'variant_name', ''),
        v_quantity, COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'), v_price, v_line_total,
        v_source = 'manual', v_source, NULLIF(v_item ->> 'note', '')
      );
    ELSE
      INSERT INTO public.order_items (
        order_id, product_id, variant_id, product_name, tamil_name, variant_name,
        quantity, unit, unit_price, line_total, is_manual, source, note
      ) VALUES (
        v_order_id, NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), ''),
        NULLIF(v_item ->> 'variant_id', ''), COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
        NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'variant_name', ''),
        v_quantity, COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'), v_price, v_line_total,
        v_source = 'manual', v_source, NULLIF(v_item ->> 'note', '')
      );
    END IF;

    IF COALESCE(v_item ->> 'product_id', v_item ->> 'id', '') ~ '^[0-9]+$' THEN
      UPDATE public.products
      SET stock_quantity = GREATEST(stock_quantity - v_quantity, 0),
          stock = GREATEST(FLOOR(stock_quantity - v_quantity), 0)::INTEGER,
          updated_at = NOW()
      WHERE id::TEXT = COALESCE(v_item ->> 'product_id', v_item ->> 'id');
    END IF;

    IF NULLIF(v_item ->> 'variant_id', '') IS NOT NULL THEN
      UPDATE public.product_variants
      SET stock = GREATEST(stock - v_quantity, 0), updated_at = NOW()
      WHERE id::TEXT = v_item ->> 'variant_id';
    END IF;
  END LOOP;

  IF NULLIF(BTRIM(COALESCE(p_coupon_code, '')), '') IS NOT NULL THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code))
      AND is_active
      AND (usage_limit IS NULL OR usage_count < usage_limit);
  END IF;

  RETURN jsonb_build_object(
    'orderId', v_order_id,
    'invoiceNo', v_invoice_no,
    'createdAt', NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_with_stock(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_order_with_stock(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;



-- ============================================================
-- SECTION 4 / 32 â€” 20260719_0004_advance_orders.sql
-- ============================================================

begin;

create sequence if not exists public.deposit_number_seq start 1;

alter table public.order_items add column if not exists category text;

create table if not exists public.advance_orders (
  id uuid primary key default gen_random_uuid(),
  deposit_id text not null unique,
  customer_name text not null,
  phone text not null,
  address text not null default '',
  product_name text not null,
  products jsonb not null default '[]'::jsonb,
  category text not null default '',
  description text not null default '',
  total_amount numeric(12,2) not null check (total_amount > 0),
  deposit_amount numeric(12,2) not null check (deposit_amount > 0),
  remaining_balance numeric(12,2) generated always as (total_amount - deposit_amount) stored,
  expected_delivery_date date not null,
  status text not null default 'pending_deposit' check (status in ('pending_deposit','ready_for_delivery','waiting_final_payment','completed','cancelled')),
  remarks text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_by_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  completed_order_id uuid unique references public.orders(id),
  invoice_number text unique,
  final_payment_method text,
  constraint advance_deposit_less_than_total check (deposit_amount < total_amount)
);

alter table public.advance_orders add column if not exists products jsonb not null default '[]'::jsonb;

create table if not exists public.advance_order_timeline (
  id bigint generated always as identity primary key,
  advance_order_id uuid not null references public.advance_orders(id) on delete cascade,
  event_type text not null,
  label text not null,
  remarks text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.advance_order_payments (
  id uuid primary key default gen_random_uuid(),
  advance_order_id uuid not null references public.advance_orders(id) on delete cascade,
  payment_type text not null check (payment_type in ('deposit','remaining')),
  amount numeric(12,2) not null check (amount >= 0),
  payment_method text not null check (payment_method in ('cash','upi','card')),
  remarks text not null default '',
  received_by uuid references auth.users(id) on delete set null,
  received_at timestamptz not null default now(),
  unique (advance_order_id, payment_type)
);

create index if not exists advance_orders_created_idx on public.advance_orders(created_at desc);
create index if not exists advance_orders_status_idx on public.advance_orders(status);
create index if not exists advance_orders_delivery_idx on public.advance_orders(expected_delivery_date);
create index if not exists advance_order_timeline_order_idx on public.advance_order_timeline(advance_order_id, created_at);
create index if not exists advance_order_payments_order_idx on public.advance_order_payments(advance_order_id, received_at);

drop function if exists public.create_advance_order(text,text,text,text,text,text,numeric,numeric,date,text,text,text);
create or replace function public.create_advance_order(
  p_customer_name text, p_phone text, p_address text, p_product_name text,
  p_category text, p_description text, p_total_amount numeric, p_deposit_amount numeric,
  p_expected_delivery_date date, p_remarks text, p_payment_method text, p_created_by_name text,
  p_products jsonb default '[]'::jsonb
)
returns public.advance_orders
language plpgsql security definer set search_path = public
as $$
declare v_order public.advance_orders; v_now timestamptz := now(); v_deposit_id text;
begin
  if trim(coalesce(p_customer_name,'')) = '' then raise exception 'Customer name is required'; end if;
  if trim(coalesce(p_phone,'')) = '' then raise exception 'Phone number is required'; end if;
  if trim(coalesce(p_product_name,'')) = '' then raise exception 'Product name is required'; end if;
  if coalesce(p_total_amount,0) <= 0 then raise exception 'Total amount must be greater than zero'; end if;
  if coalesce(p_deposit_amount,0) <= 0 or p_deposit_amount >= p_total_amount then raise exception 'Deposit must be greater than zero and less than the total amount'; end if;
  if lower(coalesce(p_payment_method,'')) not in ('cash','upi','card') then raise exception 'Select a valid deposit payment method'; end if;
  v_deposit_id := 'DEP-' || to_char(v_now at time zone 'Asia/Kolkata','YYYYMMDD') || '-' || lpad(nextval('public.deposit_number_seq')::text,4,'0');
  insert into public.advance_orders(deposit_id,customer_name,phone,address,product_name,products,category,description,total_amount,deposit_amount,expected_delivery_date,remarks,created_by,created_by_name,created_at,updated_at)
  values(v_deposit_id,trim(p_customer_name),trim(p_phone),trim(coalesce(p_address,'')),trim(p_product_name),case when jsonb_typeof(coalesce(p_products,'[]'::jsonb))='array' then coalesce(p_products,'[]'::jsonb) else '[]'::jsonb end,trim(coalesce(p_category,'')),trim(coalesce(p_description,'')),round(p_total_amount,2),round(p_deposit_amount,2),p_expected_delivery_date,trim(coalesce(p_remarks,'')),auth.uid(),trim(coalesce(p_created_by_name,'')),v_now,v_now)
  returning * into v_order;
  insert into public.advance_order_payments(advance_order_id,payment_type,amount,payment_method,remarks,received_by,received_at)
  values(v_order.id,'deposit',v_order.deposit_amount,lower(p_payment_method),coalesce(p_remarks,''),auth.uid(),v_now);
  insert into public.advance_order_timeline(advance_order_id,event_type,label,created_by,created_at) values
    (v_order.id,'created','Created',auth.uid(),v_now),
    (v_order.id,'deposit_received','Deposit Received',auth.uid(),v_now);
  return v_order;
end;
$$;

drop function if exists public.update_advance_order_status(uuid, text, text);
create or replace function public.update_advance_order_status(p_order_id uuid, p_status text, p_remarks text default '')
returns public.advance_orders
language plpgsql security definer set search_path = public
as $$
declare v_order public.advance_orders; v_label text;
begin
  if p_status not in ('pending_deposit','ready_for_delivery','waiting_final_payment','cancelled') then raise exception 'Invalid status transition'; end if;
  select * into v_order from public.advance_orders where id=p_order_id for update;
  if not found then raise exception 'Advance order not found'; end if;
  if v_order.status='completed' then raise exception 'A completed order cannot be changed'; end if;
  v_label := case p_status when 'ready_for_delivery' then 'Tailoring Completed' when 'waiting_final_payment' then 'Customer Contacted' when 'cancelled' then 'Cancelled' else 'Pending Deposit' end;
  update public.advance_orders set status=p_status,remarks=case when trim(coalesce(p_remarks,''))='' then remarks else p_remarks end,updated_at=now() where id=p_order_id returning * into v_order;
  insert into public.advance_order_timeline(advance_order_id,event_type,label,remarks,created_by) values(p_order_id,p_status,v_label,coalesce(p_remarks,''),auth.uid());
  return v_order;
end;
$$;

create or replace function public.add_advance_order_event(p_order_id uuid, p_event_type text, p_label text, p_remarks text default '')
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not exists(select 1 from public.advance_orders where id=p_order_id) then raise exception 'Advance order not found'; end if;
  insert into public.advance_order_timeline(advance_order_id,event_type,label,remarks,created_by) values(p_order_id,p_event_type,p_label,coalesce(p_remarks,''),auth.uid());
end;
$$;

create or replace function public.complete_advance_order(p_order_id uuid, p_payment_method text, p_remarks text default '')
returns table(order_id uuid, invoice_no text, completed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare v_advance public.advance_orders; v_order_id uuid := gen_random_uuid(); v_invoice text; v_now timestamptz := now(); v_items jsonb; v_item jsonb;
begin
  if lower(coalesce(p_payment_method,'')) not in ('cash','upi','card') then raise exception 'Select a valid payment method'; end if;
  select * into v_advance from public.advance_orders where id=p_order_id for update;
  if not found then raise exception 'Advance order not found'; end if;
  if v_advance.status='cancelled' then raise exception 'A cancelled order cannot be completed'; end if;
  if v_advance.completed_order_id is not null or v_advance.invoice_number is not null then raise exception 'Invoice already generated for this order'; end if;
  v_invoice := 'PB-' || to_char(v_now at time zone 'Asia/Kolkata','YYYYMMDD') || '-' || lpad(nextval('public.invoice_number_seq')::text,6,'0');
  v_items := case when jsonb_typeof(v_advance.products)='array' and jsonb_array_length(v_advance.products)>0 then v_advance.products else jsonb_build_array(jsonb_build_object('name',v_advance.product_name,'category',v_advance.category,'description',v_advance.description,'quantity',1,'base_price',v_advance.total_amount,'line_total',v_advance.total_amount,'unit','piece','unit_type','unit','source','advance_order')) end;
  insert into public.orders(id,invoice_no,customer_name,phone,address,user_id,items,subtotal,total,status,order_mode,order_type,shipping,delivery_charge,discount_amount,manual_discount_amount,payment_mode,payment_method,created_at,updated_at)
  values(v_order_id,v_invoice,v_advance.customer_name,v_advance.phone,v_advance.address,auth.uid(),v_items,v_advance.total_amount,v_advance.total_amount,'completed','offline','advance_order',0,0,0,0,lower(p_payment_method),lower(p_payment_method),v_now,v_now);
  for v_item in select value from jsonb_array_elements(v_items) loop
    insert into public.order_items(order_id,product_name,category,quantity,unit,unit_price,line_total,is_manual,source,note)
    values(v_order_id,coalesce(nullif(v_item->>'name',''),'Product'),coalesce(nullif(v_item->>'category',''),v_advance.category),greatest(coalesce(nullif(v_item->>'quantity','')::numeric,1),0),coalesce(nullif(v_item->>'unit',''),'piece'),greatest(coalesce(nullif(v_item->>'base_price','')::numeric,0),0),greatest(coalesce(nullif(v_item->>'line_total','')::numeric,0),0),false,'advance_order',coalesce(nullif(v_item->>'note',''),v_advance.description));
  end loop;
  insert into public.advance_order_payments(advance_order_id,payment_type,amount,payment_method,remarks,received_by,received_at)
  values(p_order_id,'remaining',v_advance.remaining_balance,lower(p_payment_method),coalesce(p_remarks,''),auth.uid(),v_now);
  update public.advance_orders set status='completed',completed_at=v_now,completed_order_id=v_order_id,invoice_number=v_invoice,final_payment_method=lower(p_payment_method),remarks=case when trim(coalesce(p_remarks,''))='' then remarks else p_remarks end,updated_at=v_now where id=p_order_id;
  insert into public.advance_order_timeline(advance_order_id,event_type,label,remarks,created_by,created_at) values
    (p_order_id,'remaining_payment_received','Remaining Payment Received',coalesce(p_remarks,''),auth.uid(),v_now),
    (p_order_id,'invoice_generated','Invoice Generated',v_invoice,auth.uid(),v_now);
  return query select v_order_id,v_invoice,v_now;
end;
$$;

alter table public.advance_orders enable row level security;
alter table public.advance_order_timeline enable row level security;
alter table public.advance_order_payments enable row level security;

drop policy if exists "Allow all for advance orders" on public.advance_orders;
create policy "Allow all for advance orders" on public.advance_orders for all using (true) with check (true);

drop policy if exists "Allow all for advance timeline" on public.advance_order_timeline;
create policy "Allow all for advance timeline" on public.advance_order_timeline for all using (true) with check (true);

drop policy if exists "Allow all for advance payments" on public.advance_order_payments;
create policy "Allow all for advance payments" on public.advance_order_payments for all using (true) with check (true);

grant usage, select on sequence public.deposit_number_seq to public, anon, authenticated;
grant usage, select on sequence public.invoice_number_seq to public, anon, authenticated;

grant select, insert, update, delete on public.advance_orders to public, anon, authenticated;
grant select, insert, update, delete on public.advance_order_timeline to public, anon, authenticated;
grant select, insert, update, delete on public.advance_order_payments to public, anon, authenticated;

grant execute on function public.create_advance_order(text,text,text,text,text,text,numeric,numeric,date,text,text,text,jsonb) to public, anon, authenticated;
grant execute on function public.update_advance_order_status(uuid,text,text) to public, anon, authenticated;
grant execute on function public.add_advance_order_event(uuid,text,text,text) to public, anon, authenticated;
grant execute on function public.complete_advance_order(uuid,text,text) to public, anon, authenticated;

notify pgrst, 'reload schema';
commit;

-- ============================================================
-- SECTION 5 / 32 â€” 20260722_0005_eight_digit_invoice_numbers.sql
-- ============================================================

-- Migration: 8-digit Invoice Number Generation
-- Ensures invoice numbers are strictly 8 digits in total (e.g., 10000001, 10000002...)

CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq START WITH 10000001;

CREATE OR REPLACE FUNCTION public.get_next_invoice_no()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
VOLATILE
AS $$
  SELECT LPAD(nextval('public.invoice_number_seq')::TEXT, 8, '0');
$$;

-- ============================================================
-- SECTION 6 / 32 â€” 20260724_0006_fix_complete_advance_order.sql
-- ============================================================

-- Migration: Fix complete_advance_order RPC
-- The previous version referenced columns (unit_price, source, note) that do
-- not exist in the order_items table. This patch corrects the insert to use
-- the actual column names: base_price, line_total, is_manual.

CREATE OR REPLACE FUNCTION public.complete_advance_order(
  p_order_id uuid,
  p_payment_method text,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_item           jsonb;
BEGIN
  -- Validate payment method
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  -- Lock and fetch the advance order
  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;
  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;
  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    RAISE EXCEPTION 'Invoice already generated for this order';
  END IF;

  -- Generate invoice number using the existing 8-digit sequence
  v_invoice := LPAD(nextval('public.invoice_number_seq')::TEXT, 8, '0');

  -- Build items JSONB â€” prefer products array, fall back to single product
  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;

  -- Create the final sale order
  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    payment_mode, payment_method, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_items, v_advance.total_amount, v_advance.total_amount,
    'completed', 'offline', 'advance_order',
    0, 0, 0, 0,
    lower(p_payment_method), lower(p_payment_method),
    v_now, v_now
  );

  -- Insert order_items using the CORRECT column names from the schema
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    INSERT INTO public.order_items (
      order_id, product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id,
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      greatest(coalesce((v_item->>'quantity')::numeric, 1), 0),
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );
  END LOOP;

  -- Record the final payment received
  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', v_advance.remaining_balance,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  -- Mark advance order as completed
  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  -- Timeline events
  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

-- Re-grant execute permission
GRANT EXECUTE ON FUNCTION public.complete_advance_order(uuid, text, text)
  TO public, anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 7 / 32 â€” 20260724_0008_fix_public_invoice_rpc.sql
-- ============================================================

-- Migration: Fix missing get_public_invoice_by_number RPC
-- Re-creates the function and forces a schema cache reload to resolve 404 errors on the /invoice page

CREATE OR REPLACE FUNCTION public.get_public_invoice_by_number(p_invoice_no TEXT)
RETURNS SETOF public.orders
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM public.orders WHERE invoice_no = NULLIF(BTRIM(p_invoice_no), '') LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_public_invoice_by_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_invoice_by_number(TEXT) TO anon, authenticated;

-- Force PostgREST to reload the schema cache
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 8 / 32 â€” 20260724_0009_create_invoices_bucket.sql
-- ============================================================

-- Migration: Create invoices storage bucket
-- Creates the 'invoices' bucket and sets up public read access and upload policies

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('invoices', 'invoices', TRUE, 10485760, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = TRUE, file_size_limit = 10485760, allowed_mime_types = ARRAY['application/pdf'];

DROP POLICY IF EXISTS invoices_public_read ON storage.objects;
CREATE POLICY invoices_public_read ON storage.objects FOR SELECT TO public USING (bucket_id = 'invoices');

DROP POLICY IF EXISTS invoices_portal_upload ON storage.objects;
CREATE POLICY invoices_portal_upload ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK (bucket_id = 'invoices');

DROP POLICY IF EXISTS invoices_portal_update ON storage.objects;
CREATE POLICY invoices_portal_update ON storage.objects FOR UPDATE TO anon, authenticated USING (bucket_id = 'invoices') WITH CHECK (bucket_id = 'invoices');

-- ============================================================
-- SECTION 9 / 32 â€” 20260726_0007_update_complete_advance_order_discount.sql
-- ============================================================

-- Migration: Update complete_advance_order to handle final amount, discounts, and coupons
-- This creates a new version of the RPC (v2) which is called from the frontend.

CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;
BEGIN
  -- Validate payment method
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  -- Lock and fetch the advance order
  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;
  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;
  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    RAISE EXCEPTION 'Invoice already generated for this order';
  END IF;

  -- Calculate the total discount from manual discount and coupon
  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  -- Generate invoice number using the existing 8-digit sequence
  v_invoice := LPAD(nextval('public.invoice_number_seq')::TEXT, 8, '0');

  -- Build items JSONB - prefer products array, fall back to single product
  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;

  -- Create the final sale order, storing the discount information
  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_items, v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method),
    v_now, v_now
  );

  -- Insert order_items using the CORRECT column names from the schema
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    INSERT INTO public.order_items (
      order_id, product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id,
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      greatest(coalesce((v_item->>'quantity')::numeric, 1), 0),
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );
  END LOOP;

  -- Record the final payment received
  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  -- Mark advance order as completed. Note that remaining_balance is GENERATED ALWAYS AS (total_amount - deposit_amount)
  -- so we do not update remaining_balance directly, but the UI considers it "paid".
  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  -- Timeline events
  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text)
  TO public, anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 10 / 32 â€” 20260728_0010_final_audit_fixes.sql
-- ============================================================

-- ============================================================
-- Migration 0010: Final audit fixes
-- Date: 2026-07-28
-- Purpose: Fix all remaining production issues found in audit
-- ============================================================

-- 1. Create store_reviews table (used by Home.tsx but never created in any migration)
CREATE TABLE IF NOT EXISTS public.store_reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id    text,
  reviewer    text,
  rating      integer CHECK (rating BETWEEN 1 AND 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
DROP FUNCTION IF EXISTS update_advance_order_status(uuid, text, text);
ALTER TABLE public.store_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can insert reviews" ON public.store_reviews;
CREATE POLICY "Anyone can insert reviews" ON public.store_reviews FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Anyone can read reviews" ON public.store_reviews;
CREATE POLICY "Anyone can read reviews"  ON public.store_reviews FOR SELECT USING (true);

-- 2. Make completed_order_id FK in advance_orders ON DELETE SET NULL
--    so that deleting an order from the orders table does not require
--    manually clearing advance_orders.completed_order_id first.
--    (Our frontend now also clears it first, but this is the proper DB-level safety net)
ALTER TABLE public.advance_orders
  DROP CONSTRAINT IF EXISTS advance_orders_completed_order_id_fkey;

ALTER TABLE public.advance_orders
  ADD CONSTRAINT advance_orders_completed_order_id_fkey
  FOREIGN KEY (completed_order_id)
  REFERENCES public.orders(id)
  ON DELETE SET NULL;

-- 3. Ensure invoice_no column in advance_orders stores the INV-prefixed number
--    (already works via complete_advance_order_v2, but add index for faster lookup)
CREATE INDEX IF NOT EXISTS idx_advance_orders_invoice_number ON public.advance_orders(invoice_number);
CREATE INDEX IF NOT EXISTS idx_advance_orders_status ON public.advance_orders(status);
CREATE INDEX IF NOT EXISTS idx_advance_orders_created_at ON public.advance_orders(created_at DESC);

-- 4. Ensure orders table has index on invoice_no for fast public invoice lookups
CREATE INDEX IF NOT EXISTS idx_orders_invoice_no ON public.orders(invoice_no);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);

-- 5. Ensure update_advance_order_status RPC is up to date and handles all statuses
CREATE OR REPLACE FUNCTION public.update_advance_order_status(
  p_order_id uuid,
  p_status   text,
  p_remarks  text DEFAULT ''
)
RETURNS SETOF public.advance_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.advance_orders;
BEGIN
  SELECT * INTO v_order FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order % not found', p_order_id;
  END IF;

  UPDATE public.advance_orders SET
    status     = p_status,
    remarks    = CASE WHEN trim(coalesce(p_remarks,'')) = '' THEN remarks ELSE p_remarks END,
    updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (advance_order_id, event_type, label, remarks, created_by, created_at)
  VALUES (
    p_order_id,
    p_status,
    CASE p_status
      WHEN 'pending_deposit'      THEN 'Status: Pending Deposit'
      WHEN 'waiting_final_payment' THEN 'Status: Waiting for Final Payment'
      WHEN 'ready_for_delivery'   THEN 'Status: Ready to Collect'
      WHEN 'completed'            THEN 'Order Completed'
      WHEN 'cancelled'            THEN 'Order Cancelled'
      ELSE p_status
    END,
    coalesce(p_remarks, ''),
    auth.uid(),
    now()
  );

  RETURN QUERY SELECT * FROM public.advance_orders WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_advance_order_status(uuid, text, text) TO authenticated, anon, public;

-- 6. Ensure add_advance_order_event RPC is robust
CREATE OR REPLACE FUNCTION public.add_advance_order_event(
  p_order_id   uuid,
  p_event_type text,
  p_label      text,
  p_remarks    text DEFAULT ''
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.advance_order_timeline (advance_order_id, event_type, label, remarks, created_by, created_at)
  VALUES (p_order_id, p_event_type, p_label, coalesce(p_remarks,''), auth.uid(), now());
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_advance_order_event(uuid, text, text, text) TO authenticated, anon, public;

-- 7. Ensure profiles RLS allows staff to update their own profile (avatar etc)
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- 8. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 11 / 32 â€” 20260808_0011_billing_date_and_order_fields.sql
-- ============================================================

-- ============================================================
-- Migration 0011: Add billing_date and ensure order metadata columns exist
-- Date: 2026-08-08
-- Purpose:
--   1. Add optional billing_date column to orders table so admins
--      can backdate or set a custom billing date/time per sale.
--   2. Ensure remarks and reference_number columns exist (they were
--      added via the dashboard and used in existing client code).
-- ============================================================

BEGIN;

-- Ensure remarks column exists (used by Pos.tsx update call)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS remarks TEXT NOT NULL DEFAULT '';

-- Ensure reference_number column exists (used by Pos.tsx update call)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS reference_number TEXT NOT NULL DEFAULT '';

-- Add optional billing_date column.
-- When NULL the UI falls back to created_at for display.
-- When set, it represents the admin-chosen billing date/time.
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS billing_date TIMESTAMPTZ;

-- Index for fast lookup by billing_date in analytics
CREATE INDEX IF NOT EXISTS idx_orders_billing_date ON public.orders(billing_date);

-- Reload PostgREST schema cache so the new column is immediately accessible
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- SECTION 12 / 32 â€” 20260901_0012_inventory_barcode_addon.sql
-- ============================================================

-- ====================================================================
-- Migration 0012: Barcode Management & Inventory Movement Ledger Addon
-- ====================================================================

BEGIN;

-- 1. Sequences for Barcode Generation
CREATE SEQUENCE IF NOT EXISTS public.barcode_product_seq START WITH 10000001;
CREATE SEQUENCE IF NOT EXISTS public.barcode_variant_seq START WITH 10000001;

-- 2. Canonical Barcode Registry
CREATE TABLE IF NOT EXISTS public.barcode_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode_value TEXT NOT NULL UNIQUE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('product', 'variant')),
  product_id BIGINT NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  variant_id UUID REFERENCES public.product_variants(id) ON DELETE RESTRICT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by_name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_barcode_entity_target CHECK (
    (entity_type = 'product' AND variant_id IS NULL) OR
    (entity_type = 'variant' AND variant_id IS NOT NULL)
  )
);

-- 3. Inventory Movement Ledger
CREATE TABLE IF NOT EXISTS public.inventory_movements (
  id BIGSERIAL PRIMARY KEY,
  product_id BIGINT REFERENCES public.products(id) ON DELETE SET NULL,
  variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
  barcode_id UUID REFERENCES public.barcode_registry(id) ON DELETE SET NULL,
  movement_type TEXT NOT NULL CHECK (
    movement_type IN ('INITIAL_BARCODE_STOCK', 'RESTOCK', 'SALE', 'RETURN', 'DAMAGE', 'CORRECTION', 'VOID')
  ),
  quantity_delta NUMERIC NOT NULL,
  quantity_before NUMERIC NOT NULL,
  quantity_after NUMERIC NOT NULL,
  unit_cost NUMERIC DEFAULT NULL,
  reference_type TEXT DEFAULT NULL, -- 'order', 'adjustment', 'barcode_receipt'
  reference_id TEXT DEFAULT NULL,   -- order_id or invoice_no
  note TEXT DEFAULT '',
  created_by_name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Indexes for Rapid POS Lookup & Audit Reports
CREATE INDEX IF NOT EXISTS idx_barcode_registry_val ON public.barcode_registry(barcode_value);
CREATE INDEX IF NOT EXISTS idx_barcode_registry_prod ON public.barcode_registry(product_id);
CREATE INDEX IF NOT EXISTS idx_barcode_registry_var ON public.barcode_registry(variant_id) WHERE variant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inv_movements_prod ON public.inventory_movements(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inv_movements_var ON public.inventory_movements(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inv_movements_type ON public.inventory_movements(movement_type, created_at DESC);

-- 5. Enable RLS and Policies
ALTER TABLE public.barcode_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS barcode_registry_all ON public.barcode_registry;
CREATE POLICY barcode_registry_all ON public.barcode_registry FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS inventory_movements_all ON public.inventory_movements;
CREATE POLICY inventory_movements_all ON public.inventory_movements FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- 6. Helper Function: Generate Unique Barcode String
--
-- Re-run safety: 0020 replaces this with a branch-aware two-argument
-- version generate_barcode_value(TEXT, TEXT). If this file is ever run
-- again AFTER 0020, a plain CREATE OR REPLACE would register a SECOND
-- overload instead of replacing the existing one (signatures differ), and
-- because 0020's p_branch has a DEFAULT, every one-argument call becomes
-- ambiguous:
--     ERROR 42725: function public.generate_barcode_value(text) is not unique
-- which breaks "Generate & Print" for every SKU. So only create this
-- legacy single-argument form when the branch-aware one is absent.
DO $$
BEGIN
  IF to_regprocedure('public.generate_barcode_value(TEXT,TEXT)') IS NULL THEN
    EXECUTE $fn$
      CREATE FUNCTION public.generate_barcode_value(p_entity_type TEXT)
      RETURNS TEXT
      LANGUAGE plpgsql
      AS $body$
      BEGIN
        IF p_entity_type = 'variant' THEN
          RETURN 'PBV' || LPAD(nextval('public.barcode_variant_seq')::TEXT, 8, '0');
        ELSE
          RETURN 'PBP' || LPAD(nextval('public.barcode_product_seq')::TEXT, 8, '0');
        END IF;
      END;
      $body$;
    $fn$;
  END IF;
END;
$$;

-- 7. Transactional RPC: Create Barcode & Receive Stock (With Barcode Reuse on Restock)
CREATE OR REPLACE FUNCTION public.create_barcode_and_receive_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_quantity_received NUMERIC DEFAULT 0,
  p_unit_cost NUMERIC DEFAULT NULL,
  p_created_by_name TEXT DEFAULT '',
  p_custom_barcode TEXT DEFAULT NULL,
  p_note TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entity_type TEXT;
  v_barcode_id UUID;
  v_barcode_value TEXT;
  v_is_new_barcode BOOLEAN := FALSE;
  v_movement_type TEXT;
  v_qty_before NUMERIC := 0;
  v_qty_after NUMERIC := 0;
  v_prod_name TEXT;
  v_var_name TEXT := '';
BEGIN
  IF p_quantity_received < 0 THEN
    RAISE EXCEPTION 'Quantity received cannot be negative';
  END IF;

  -- 1. Check Parent Product Exists
  SELECT name INTO v_prod_name FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product with ID % not found', p_product_id;
  END IF;

  -- 2. Verify Variant Belongs to Product if Variant is Provided
  IF p_variant_id IS NOT NULL THEN
    v_entity_type := 'variant';
    SELECT variant_name, stock INTO v_var_name, v_qty_before
    FROM public.product_variants
    WHERE id = p_variant_id AND product_id = p_product_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Variant % does not belong to Product %', p_variant_id, p_product_id;
    END IF;
  ELSE
    v_entity_type := 'product';
    SELECT stock_quantity INTO v_qty_before
    FROM public.products
    WHERE id = p_product_id;
  END IF;

  -- 3. Check for Existing Active Barcode in barcode_registry (SKU Identity)
  IF v_entity_type = 'variant' THEN
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE variant_id = p_variant_id AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  ELSE
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  -- 4. Reuse Existing or Create New Barcode
  IF v_barcode_id IS NOT NULL THEN
    v_is_new_barcode := FALSE;
    v_movement_type := CASE WHEN v_qty_before = 0 THEN 'INITIAL_BARCODE_STOCK' ELSE 'RESTOCK' END;
  ELSE
    v_is_new_barcode := TRUE;
    v_movement_type := 'INITIAL_BARCODE_STOCK';
    v_barcode_value := COALESCE(NULLIF(UPPER(BTRIM(p_custom_barcode)), ''), public.generate_barcode_value(v_entity_type));

    INSERT INTO public.barcode_registry (
      barcode_value, entity_type, product_id, variant_id, is_active, created_by_name
    )
    VALUES (
      v_barcode_value, v_entity_type, p_product_id, p_variant_id, TRUE, COALESCE(p_created_by_name, '')
    )
    RETURNING id INTO v_barcode_id;
  END IF;

  -- 5. Synchronize compatibility column on target table
  IF v_entity_type = 'variant' THEN
    UPDATE public.product_variants
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_variant_id;
  ELSE
    UPDATE public.products
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- 6. Apply Stock Increment & Parent Aggregate Sync
  v_qty_after := v_qty_before + p_quantity_received;

  IF p_quantity_received > 0 THEN
    IF v_entity_type = 'variant' THEN
      UPDATE public.product_variants
      SET stock = v_qty_after, updated_at = NOW()
      WHERE id = p_variant_id;
  
      -- Refresh parent aggregate stock cache
      UPDATE public.products
      SET stock_quantity = (
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ),
          stock = FLOOR((
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ))::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    ELSE
      UPDATE public.products
      SET stock_quantity = v_qty_after,
          stock = FLOOR(v_qty_after)::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    END IF;
  END IF;

  -- 7. Record Immutable Inventory Movement
  IF p_quantity_received > 0 THEN
    INSERT INTO public.inventory_movements (
      product_id, variant_id, barcode_id, movement_type,
      quantity_delta, quantity_before, quantity_after,
      unit_cost, reference_type, reference_id, note, created_by_name
    )
    VALUES (
      p_product_id, p_variant_id, v_barcode_id, v_movement_type,
      p_quantity_received, v_qty_before, v_qty_after,
      p_unit_cost, 'barcode_receipt', v_barcode_value,
      COALESCE(p_note, ''), COALESCE(p_created_by_name, '')
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'barcode_id', v_barcode_id,
    'barcode_value', v_barcode_value,
    'is_new_barcode', v_is_new_barcode,
    'movement_type', v_movement_type,
    'quantity_before', v_qty_before,
    'quantity_received', p_quantity_received,
    'quantity_after', v_qty_after,
    'product_id', p_product_id,
    'variant_id', p_variant_id,
    'product_name', v_prod_name,
    'variant_name', v_var_name
  );
END;
$$;

-- 8. Transactional RPC: Adjust Stock (Restock, Damage, Correction, Return)
CREATE OR REPLACE FUNCTION public.adjust_inventory_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_new_quantity NUMERIC DEFAULT 0,
  p_reason TEXT DEFAULT 'RESTOCK',
  p_note TEXT DEFAULT '',
  p_created_by_name TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qty_before NUMERIC := 0;
  v_delta NUMERIC := 0;
  v_barcode_id UUID;
BEGIN
  IF p_new_quantity < 0 THEN
    RAISE EXCEPTION 'Stock quantity cannot be negative';
  END IF;

  -- Verify variant if supplied
  IF p_variant_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_variants WHERE id = p_variant_id AND product_id = p_product_id) THEN
      RAISE EXCEPTION 'Variant does not belong to specified Product';
    END IF;

    SELECT stock INTO v_qty_before FROM public.product_variants WHERE id = p_variant_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = p_variant_id AND is_active = TRUE LIMIT 1;
    
    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.product_variants
    SET stock = p_new_quantity, updated_at = NOW()
    WHERE id = p_variant_id;

    -- Refresh parent aggregate
    UPDATE public.products
    SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE),
        stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE))::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  ELSE
    SELECT stock_quantity INTO v_qty_before FROM public.products WHERE id = p_product_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.products
    SET stock_quantity = p_new_quantity,
        stock = FLOOR(p_new_quantity)::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- Record Movement
  INSERT INTO public.inventory_movements (
    product_id, variant_id, barcode_id, movement_type,
    quantity_delta, quantity_before, quantity_after,
    reference_type, note, created_by_name
  )
  VALUES (
    p_product_id, p_variant_id, v_barcode_id, p_reason,
    v_delta, v_qty_before, p_new_quantity,
    'adjustment', COALESCE(p_note, ''), COALESCE(p_created_by_name, '')
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'quantity_before', v_qty_before,
    'quantity_after', p_new_quantity,
    'delta', v_delta,
    'reason', p_reason
  );
END;
$$;

-- 9. Transactional RPC: Complete POS Sale with Inventory Pre-Validation & Movement Ledger
CREATE OR REPLACE FUNCTION public.complete_pos_sale_with_inventory(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'completed',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_remarks TEXT DEFAULT NULL,
  p_reference_number TEXT DEFAULT NULL,
  p_billing_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC := 0;
  v_total NUMERIC := 0;
  v_item JSONB;
  v_product_id BIGINT;
  v_variant_id UUID;
  v_quantity NUMERIC;
  v_unit_price NUMERIC;
  v_line_total NUMERIC;
  v_product_name TEXT;
  v_name_ta TEXT;
  v_unit TEXT;
  v_unit_type TEXT;
  v_base_quantity NUMERIC;
  v_is_manual BOOLEAN;
  v_discount NUMERIC;
  v_gst_amount NUMERIC;
  v_gst_rate NUMERIC;
  v_image_url TEXT;
  v_variant_name TEXT;
  v_source TEXT;
  v_note TEXT;
  v_category TEXT;
  v_current_stock NUMERIC;
  v_barcode_id UUID;
  v_created_at TIMESTAMPTZ := COALESCE(p_billing_date, NOW());
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order items cannot be empty';
  END IF;

  -- 1. Atomic Pre-Validation of Available Stock for All Items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');

    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 2. Calculate Subtotal & Generate Invoice Number
  v_invoice_no := public.get_next_invoice_no();

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE(
      (v_item ->> 'unit_price')::NUMERIC,
      (v_item ->> 'base_price')::NUMERIC,
      (v_item ->> 'price')::NUMERIC,
      0
    );
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(0, ROUND(v_subtotal + COALESCE(p_shipping, 0) + COALESCE(p_delivery_charge, 0) - COALESCE(p_discount_amount, 0), 2));

  -- 3. Insert Order Record
  INSERT INTO public.orders (
    invoice_no, user_id, customer_name, phone, address, items,
    subtotal, shipping, total, status, order_mode, order_type,
    delivery_charge, discount_amount, manual_discount_amount,
    manual_discount_type, manual_discount_value, coupon_code,
    coupon_percentage, total_gst, gst_amount, gst_enabled,
    payment_method, payment_mode, split_details, remarks,
    reference_number, billing_date, created_at, updated_at
  )
  VALUES (
    v_invoice_no, v_user_id, COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Customer'),
    COALESCE(p_phone, ''), COALESCE(p_address, ''), p_items,
    v_subtotal, COALESCE(p_shipping, 0), v_total, COALESCE(p_status, 'completed'),
    COALESCE(p_order_mode, 'offline'), COALESCE(p_order_type, 'pos_sale'),
    COALESCE(p_delivery_charge, 0), COALESCE(p_discount_amount, 0),
    COALESCE(p_manual_discount_amount, 0), COALESCE(p_manual_discount_type, 'flat'),
    COALESCE(p_manual_discount_value, 0), p_coupon_code,
    COALESCE(p_coupon_percentage, 0), COALESCE(p_total_gst, 0),
    COALESCE(p_total_gst, 0), COALESCE(p_gst_enabled, FALSE),
    COALESCE(p_payment_method, 'cash'), COALESCE(p_payment_method, 'cash'),
    COALESCE(p_split_details, '{}'::JSONB), p_remarks,
    p_reference_number, p_billing_date, v_created_at, NOW()
  )
  RETURNING id INTO v_order_id;

  -- 4. Insert Order Items, Deduct Stock & Record SALE Movements
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE((v_item ->> 'unit_price')::NUMERIC, (v_item ->> 'base_price')::NUMERIC, 0);
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');
    v_name_ta := COALESCE(v_item ->> 'product_tamil_name', v_item ->> 'tamil_name', '');
    v_unit := COALESCE(v_item ->> 'unit', 'piece');
    v_unit_type := COALESCE(v_item ->> 'unit_type', 'unit');
    v_base_quantity := COALESCE((v_item ->> 'base_quantity')::NUMERIC, 1);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_discount := COALESCE((v_item ->> 'discount')::NUMERIC, 0);
    v_gst_amount := COALESCE((v_item ->> 'gst_amount')::NUMERIC, 0);
    v_gst_rate := COALESCE((v_item ->> 'gst_rate')::NUMERIC, 0);
    v_image_url := v_item ->> 'image_url';
    v_variant_name := v_item ->> 'variant_name';
    v_source := COALESCE(v_item ->> 'source', 'catalogue');
    v_note := v_item ->> 'note';
    v_category := v_item ->> 'category';

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name,
      product_tamil_name, tamil_name, quantity, unit, unit_type,
      base_quantity, base_price, unit_price, line_total, image_url,
      is_manual, discount, gst_amount, gst_rate, variant_name,
      source, note, category, created_at
    )
    VALUES (
      v_order_id, v_product_id, v_variant_id, v_product_name, v_product_name,
      v_name_ta, v_name_ta, v_quantity, v_unit, v_unit_type,
      v_base_quantity, v_unit_price, v_unit_price, v_line_total, v_image_url,
      v_is_manual, v_discount, v_gst_amount, v_gst_rate, v_variant_name,
      v_source, v_note, v_category, v_created_at
    );

    -- Deduct Stock and Insert SALE Movement
    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = v_variant_id AND is_active = TRUE LIMIT 1;

        UPDATE public.product_variants
        SET stock = GREATEST(0, stock - v_quantity), updated_at = NOW()
        WHERE id = v_variant_id;

        -- Parent aggregate update
        UPDATE public.products
        SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE),
            stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE))::INTEGER,
            updated_at = NOW()
        WHERE id = v_product_id;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note
        )
        VALUES (
          v_product_id, v_variant_id, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout'
        );

      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = v_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - v_quantity),
            stock = GREATEST(0, stock - FLOOR(v_quantity)::INTEGER),
            updated_at = NOW()
        WHERE id = v_product_id;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note
        )
        VALUES (
          v_product_id, NULL, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout'
        );
      END IF;
    END IF;
  END LOOP;

  -- 5. Increment Coupon Usage Count
  IF p_coupon_code IS NOT NULL AND BTRIM(p_coupon_code) <> '' THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1, updated_at = NOW()
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code));
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'invoice_no', v_invoice_no,
    'total', v_total
  );
END;
$$;

-- 10. Store Settings: historical CLAD seed - now GUARDED -------------------
-- The CLAD / cladclothing26@gmail.com identity below is a retired brand.
-- It was replaced by the rebrand migrations (0016, 0017, 0021) and repaired
-- for databases that missed them by 20261004_0033. The statement is kept
-- only so a brand-new install reproduces the original history, so it now
-- matches the untouched 0001 defaults and skips any row that already holds
-- a real (or repaired) profile.
-- WHY THE GUARD: with a bare "WHERE id = 1" this block ran on every re-run
-- and pushed the retired CLAD header back over the live YG ENTERPRISES
-- POS 1 profile (Store Settings -> Shop Profile and every POS 1 invoice /
-- receipt / barcode label), undoing 0016 / 0017 / 0021 / 0033.
UPDATE public.store_settings
SET name = 'CLAD',
    owner_name = 'Rubi krishna',
    phone = '+91 7010312145',
    email = 'cladclothing26@gmail.com',
    address = 'Manapparai, Trichy, Tamil Nadu - 621 306',
    updated_at = NOW()
WHERE id = 1
  AND LOWER(BTRIM(COALESCE(name, ''))) = 'yg enterprises'
  AND COALESCE(email, '') = 'mypurpleboutique05@gmail.com';

COMMIT;

-- ============================================================
-- SECTION 13 / 32 â€” 20260903_0013_expense_tracker_addon.sql
-- ============================================================

-- ====================================================================
-- Migration 0013: Expense Tracker & Category Management Addon
-- ====================================================================

BEGIN;

-- 1. Expense Categories Table
CREATE TABLE IF NOT EXISTS public.expense_categories (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_expense_category_name UNIQUE (name)
);

-- 2. Seed Default Expense Categories
-- No conflict target on purpose: this section created
-- uq_expense_category_name UNIQUE (name), but section 28 (0029) drops that
-- constraint and replaces it with the branch-scoped unique index
-- expense_categories_branch_name_unique (branch, LOWER(BTRIM(name))).
-- A bare "ON CONFLICT DO NOTHING" matches both schemas, while the old
-- "ON CONFLICT (name)" failed with 42P10 (no unique or exclusion
-- constraint matching the ON CONFLICT specification) on every database
-- that had already run section 28 - i.e. on re-runs of this whole script.
INSERT INTO public.expense_categories (name, is_active) VALUES
  ('Maintenance', TRUE),
  ('Marketing', TRUE),
  ('Other', TRUE),
  ('Rent', TRUE),
  ('Salaries', TRUE),
  ('Supplies', TRUE)
ON CONFLICT DO NOTHING;

-- 3. Store Expenses Table
-- Note: category_id has ON DELETE SET NULL to preserve historical expense records even if a category is removed
CREATE TABLE IF NOT EXISTS public.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  category_id BIGINT REFERENCES public.expense_categories(id) ON DELETE SET NULL,
  category_name TEXT NOT NULL, -- denormalized snapshot to protect historical records
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  description TEXT DEFAULT '',
  payment_mode TEXT DEFAULT 'cash', -- 'cash', 'upi', 'card', 'bank_transfer'
  recorded_by_name TEXT DEFAULT 'Staff',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Fast Query Indexes
CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses(expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON public.expenses(category_id);
CREATE INDEX IF NOT EXISTS idx_expense_categories_active ON public.expense_categories(is_active);

-- 5. Enable Row Level Security (RLS)
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS expense_categories_all ON public.expense_categories;
CREATE POLICY expense_categories_all ON public.expense_categories FOR ALL USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS expenses_all ON public.expenses;
CREATE POLICY expenses_all ON public.expenses FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- 6. RPC: Summary Metric Calculation (Calculates Today, Week, Month, Year, All-Time)
CREATE OR REPLACE FUNCTION public.get_expense_summary_metrics(
  p_current_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today NUMERIC(12,2) := 0;
  v_this_week NUMERIC(12,2) := 0;
  v_this_month NUMERIC(12,2) := 0;
  v_this_year NUMERIC(12,2) := 0;
  v_total_all_time NUMERIC(12,2) := 0;
  v_week_start DATE := date_trunc('week', p_current_date)::DATE;
  v_month_start DATE := date_trunc('month', p_current_date)::DATE;
  v_year_start DATE := date_trunc('year', p_current_date)::DATE;
BEGIN
  SELECT 
    COALESCE(SUM(CASE WHEN expense_date = p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_week_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_month_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_year_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(amount), 0)
  INTO
    v_today, v_this_week, v_this_month, v_this_year, v_total_all_time
  FROM public.expenses;

  RETURN jsonb_build_object(
    'today', v_today,
    'this_week', v_this_week,
    'this_month', v_this_month,
    'this_year', v_this_year,
    'total_all_time', v_total_all_time
  );
END;
$$;

COMMIT;

-- ============================================================
-- SECTION 14 / 32 â€” 20260904_0015_unregistered_category.sql
-- ============================================================

-- ============================================================================
-- Migration: 20260904_0015_unregistered_category.sql
-- Description: Seed system category 'Unregistered' for ad-hoc POS non-inventory billing
-- ============================================================================

DO $$
BEGIN
  -- Insert into categories if not present
  IF NOT EXISTS (
    SELECT 1 FROM public.categories 
    WHERE LOWER(name_en) = 'unregistered'
  ) THEN
    INSERT INTO public.categories (name_en, name_ta, is_active, sort_order)
    VALUES ('Unregistered', 'à®ªà®¤à®¿à®µà¯à®šà¯†à®¯à¯à®¯à®ªà¯à®ªà®Ÿà®¾à®¤à®¤à¯', TRUE, 999);
  END IF;
END $$;

-- ============================================================
-- SECTION 15 / 32 â€” 20260911_0016_rebrand_to_chaji_mens_wear.sql
-- ============================================================

-- Migration: 20260911_0016_rebrand_to_chaji_mens_wear.sql
-- Rebrand store details to YG ENTERPRISES and initialize branding storage bucket

BEGIN;

-- 1. Update Store Settings
UPDATE public.store_settings
SET name = 'YG ENTERPRISES',
    owner_name = 'Chandru ajitha',
    phone = '+91 8925094465, +91 9344159498',
    email = 'chandrums1552004@gmail.com',
    address = 'Manapparai, Trichy, Tamil Nadu - 621 306',
    updated_at = NOW()
WHERE id = 1
  -- Guarded: only rebrand a row that is still on a legacy / placeholder
  -- identity (the 0001 default or the section 12 CLAD seed). A re-run
  -- therefore never overwrites a profile the owner has since edited in
  -- Store Settings.
  AND COALESCE(email, '') IN (
        'mypurpleboutique05@gmail.com',
        'cladclothing26@gmail.com'
      );

-- 2. Create public 'branding' storage bucket if not exists
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'branding',
  'branding',
  TRUE,
  10485760,
  ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']
)
ON CONFLICT (id) DO UPDATE SET
  public = TRUE,
  file_size_limit = 10485760;

-- 3. Storage Policies for branding bucket
DROP POLICY IF EXISTS branding_public_read ON storage.objects;
CREATE POLICY branding_public_read ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'branding');

DROP POLICY IF EXISTS branding_portal_upload ON storage.objects;
CREATE POLICY branding_portal_upload ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'branding');

DROP POLICY IF EXISTS branding_portal_update ON storage.objects;
CREATE POLICY branding_portal_update ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (bucket_id = 'branding')
  WITH CHECK (bucket_id = 'branding');

COMMIT;

-- ============================================================
-- SECTION 16 / 32 â€” 20260912_0017_update_store_address.sql
-- ============================================================

-- Migration: 20260912_0017_update_store_address.sql
-- Update store address for YG ENTERPRISES

BEGIN;

UPDATE public.store_settings
SET address = '1892 A, bypass road, Sevoor,arani-632316',
    updated_at = NOW()
WHERE id = 1
  -- Guarded: same "legacy identity only" rule as sections 16 / 21, so a
  -- re-run never moves the address of a profile the owner has edited.
  AND COALESCE(email, '') IN (
        'mypurpleboutique05@gmail.com',
        'cladclothing26@gmail.com',
        'chandrums1552004@gmail.com'
      );

COMMIT;

-- ============================================================
-- SECTION 17 / 32 â€” 20260917_0001_fix_soft_delete_unique_constraints.sql
-- ============================================================

-- Fix for products unique constraint
DROP INDEX IF EXISTS public.products_category_name_unique;
CREATE UNIQUE INDEX products_category_name_unique
  ON public.products (category_id, LOWER(BTRIM(name)))
  WHERE is_active = true;

-- Fix for variants unique constraint  
DROP INDEX IF EXISTS public.product_variants_product_name_unique;
CREATE UNIQUE INDEX product_variants_product_name_unique
  ON public.product_variants (product_id, LOWER(BTRIM(variant_name)))
  WHERE is_active = true;

-- ============================================================
-- SECTION 18 / 32 â€” 20260918_0018_advance_order_self_heal.sql
-- ============================================================

-- ============================================================
-- Migration 0018: Advance order self-healing & status integrity
-- Date: 2026-09-18
-- Purpose:
-- 1. Make complete_advance_order_v2 self-heal if invoice already generated
-- 2. Prevent update_advance_order_status from changing completed invoice orders
-- ============================================================

CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;
BEGIN
  -- Validate payment method
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  -- Lock and fetch the advance order
  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;

  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;

  -- Self-healing check: If invoice or completed order already exists, ensure completed status and return cleanly
  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    IF v_advance.status != 'completed' THEN
      UPDATE public.advance_orders
      SET status = 'completed',
          updated_at = v_now
      WHERE id = p_order_id;
    END IF;

    RETURN QUERY SELECT 
      coalesce(v_advance.completed_order_id, gen_random_uuid()),
      coalesce(v_advance.invoice_number, 'INV00000000'),
      coalesce(v_advance.completed_at, v_now);
    RETURN;
  END IF;

  -- Calculate total discount from manual discount and coupon
  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  -- Generate invoice number using the existing 8-digit sequence
  v_invoice := LPAD(nextval('public.invoice_number_seq')::TEXT, 8, '0');

  -- Build items JSONB - prefer products array, fall back to single product
  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;

  -- Create final sale order
  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_items, v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method),
    v_now, v_now
  );

  -- Insert order items
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    INSERT INTO public.order_items (
      order_id, product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id,
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      greatest(coalesce((v_item->>'quantity')::numeric, 1), 0),
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );
  END LOOP;

  -- Record final payment
  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  -- Mark advance order as completed
  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  -- Timeline events
  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

-- Prevent changing status of advance orders that already have an invoice
CREATE OR REPLACE FUNCTION public.update_advance_order_status(
  p_order_id uuid,
  p_status   text,
  p_remarks  text DEFAULT ''
)
RETURNS SETOF public.advance_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.advance_orders;
BEGIN
  SELECT * INTO v_order FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order % not found', p_order_id;
  END IF;

  IF (v_order.invoice_number IS NOT NULL OR v_order.completed_order_id IS NOT NULL) AND p_status != 'completed' THEN
    RAISE EXCEPTION 'Cannot change status of an order that already has an invoice generated';
  END IF;

  UPDATE public.advance_orders SET
    status     = p_status,
    remarks    = CASE WHEN trim(coalesce(p_remarks,'')) = '' THEN remarks ELSE p_remarks END,
    updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (advance_order_id, event_type, label, remarks, created_by, created_at)
  VALUES (
    p_order_id,
    p_status,
    CASE p_status
      WHEN 'pending_deposit'       THEN 'Status: Pending Deposit'
      WHEN 'waiting_final_payment' THEN 'Status: Waiting for Final Payment'
      WHEN 'ready_for_delivery'    THEN 'Status: Ready to Collect'
      WHEN 'completed'             THEN 'Order Completed'
      WHEN 'cancelled'             THEN 'Order Cancelled'
      ELSE p_status
    END,
    coalesce(p_remarks, ''),
    auth.uid(),
    now()
  );

  RETURN QUERY SELECT * FROM public.advance_orders WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text) TO public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_advance_order_status(uuid, text, text) TO authenticated, anon, public;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 19 / 32 â€” 20260918_0019_robust_public_invoice_lookup.sql
-- ============================================================

-- Migration: 20260918_0019_robust_public_invoice_lookup.sql
-- Enables get_public_invoice_by_number to seamlessly match invoices regardless of:
-- 1. "INV" prefix (e.g. "INV00000030" or "00000030")
-- 2. "PB-" legacy prefix (e.g. "PB-20260918-000001")
-- 3. Unpadded or stripped leading zeros (e.g. "30" matching "00000030")
-- 4. UUID order ID (e.g. from admin dashboard link)
-- 5. Case insensitivity and whitespace trimming

CREATE OR REPLACE FUNCTION public.get_public_invoice_by_number(p_invoice_no TEXT)
RETURNS SETOF public.orders
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM public.orders 
  WHERE invoice_no = NULLIF(BTRIM(p_invoice_no), '')
     OR LOWER(invoice_no) = LOWER(NULLIF(BTRIM(p_invoice_no), ''))
     OR invoice_no = REGEXP_REPLACE(BTRIM(p_invoice_no), '^(INV|PB)[-_ ]*', '', 'i')
     OR (
       REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g') <> ''
       AND invoice_no = LPAD(REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g'), 8, '0')
     )
     OR (
       REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g') <> ''
       AND invoice_no = REGEXP_REPLACE(REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g'), '^0+', '')
     )
     OR (
       p_invoice_no ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       AND id = p_invoice_no::UUID
     )
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_public_invoice_by_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_invoice_by_number(TEXT) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 20 / 32 â€” 20260924_0020_split_pos_branches.sql
-- ============================================================

-- ====================================================================
-- Migration 0020: Split POS into 2 fully isolated branches (pos1 / pos2)
-- Adds a `branch` column to catalog/order/inventory tables, gives each
-- branch its own invoice number sequence, and makes the POS sale RPCs
-- branch-aware. Idempotent: safe to re-run.
-- ====================================================================

BEGIN;

-- 1. Branch column on every branch-scoped table --------------------------

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.inventory_movements ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.barcode_registry ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';

DO $$
BEGIN
  ALTER TABLE public.products ADD CONSTRAINT products_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  ALTER TABLE public.categories ADD CONSTRAINT categories_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  ALTER TABLE public.orders ADD CONSTRAINT orders_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  ALTER TABLE public.inventory_movements ADD CONSTRAINT inventory_movements_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
  ALTER TABLE public.barcode_registry ADD CONSTRAINT barcode_registry_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

CREATE INDEX IF NOT EXISTS products_branch_idx ON public.products(branch);
CREATE INDEX IF NOT EXISTS product_variants_branch_idx ON public.product_variants(branch);
CREATE INDEX IF NOT EXISTS categories_branch_idx ON public.categories(branch);
CREATE INDEX IF NOT EXISTS orders_branch_idx ON public.orders(branch, created_at DESC);
CREATE INDEX IF NOT EXISTS inventory_movements_branch_idx ON public.inventory_movements(branch, created_at DESC);

-- 2. Uniqueness must be scoped per branch now -----------------------------

DROP INDEX IF EXISTS public.products_category_name_unique;
CREATE UNIQUE INDEX IF NOT EXISTS products_category_name_unique
  ON public.products (branch, category_id, LOWER(BTRIM(name)))
  WHERE is_active = true;

DROP INDEX IF EXISTS public.product_variants_product_name_unique;
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_product_name_unique
  ON public.product_variants (branch, product_id, LOWER(BTRIM(variant_name)))
  WHERE is_active = true;

-- 3. Per-branch invoice number sequences ----------------------------------
-- pos1 continues from wherever the shop's existing invoice_number_seq left
-- off; pos2 starts in a disjoint 8-digit range so numbers never collide
-- and the existing 8-digit display format needs no change.

CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq_pos1 START WITH 10000001;
CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq_pos2 START WITH 50000001;

DO $$
DECLARE
  v_old_last BIGINT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'invoice_number_seq') THEN
    SELECT last_value INTO v_old_last FROM public.invoice_number_seq;
    IF v_old_last IS NOT NULL AND v_old_last >= 10000001 THEN
      PERFORM setval('public.invoice_number_seq_pos1', v_old_last, TRUE);
    END IF;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.get_next_invoice_no();

CREATE OR REPLACE FUNCTION public.get_next_invoice_no(p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
VOLATILE
AS $$
BEGIN
  IF p_branch = 'pos2' THEN
    RETURN LPAD(nextval('public.invoice_number_seq_pos2')::TEXT, 8, '0');
  ELSE
    RETURN LPAD(nextval('public.invoice_number_seq_pos1')::TEXT, 8, '0');
  END IF;
END;
$$;

-- 4. Branch-aware create_order_with_stock (fallback RPC) ------------------

DROP FUNCTION IF EXISTS public.create_order_with_stock(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB
);

CREATE OR REPLACE FUNCTION public.create_order_with_stock(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'pending',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC(12,2) := 0;
  v_total NUMERIC(12,2);
  v_item JSONB;
  v_quantity NUMERIC(12,3);
  v_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_source TEXT;
  v_attempt INTEGER;
  v_uses_typed_item_ids BOOLEAN;
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one order item is required';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_quantity := GREATEST(COALESCE(NULLIF(v_item ->> 'quantity', '')::NUMERIC, 0), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_item ->> 'base_price', '')::NUMERIC, 0), 0);
    v_line_total := GREATEST(
      COALESCE(NULLIF(v_item ->> 'line_total', '')::NUMERIC, v_quantity * v_price),
      0
    );

    IF v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero';
    END IF;

    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(
    ROUND(
      v_subtotal + GREATEST(COALESCE(p_shipping, 0), 0)
        + GREATEST(COALESCE(p_delivery_charge, 0), 0)
        + GREATEST(COALESCE(p_total_gst, 0), 0)
        - GREATEST(COALESCE(p_discount_amount, 0), 0)
        - GREATEST(COALESCE(p_manual_discount_amount, 0), 0),
      2
    ),
    0
  );

  SELECT data_type = 'bigint'
  INTO v_uses_typed_item_ids
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'order_items' AND column_name = 'product_id';

  FOR v_attempt IN 1..5 LOOP
    v_invoice_no := public.get_next_invoice_no(v_branch);
    v_order_id := gen_random_uuid();

    BEGIN
      INSERT INTO public.orders (
        id, invoice_no, user_id, customer_name, phone, address, items, subtotal, shipping, total,
        status, order_mode, order_type, delivery_charge, discount_amount, manual_discount_amount,
        manual_discount_type, manual_discount_value, coupon_code, coupon_percentage, total_gst,
        gst_amount, gst_enabled, payment_method, payment_mode, split_details, branch, created_at, updated_at
      ) VALUES (
        v_order_id, v_invoice_no, auth.uid(),
        COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Walk-in Customer'),
        COALESCE(BTRIM(p_phone), ''), COALESCE(NULLIF(BTRIM(p_address), ''), 'POS Counter'),
        p_items, v_subtotal, GREATEST(COALESCE(p_shipping, 0), 0), v_total,
        COALESCE(NULLIF(BTRIM(p_status), ''), 'pending'),
        COALESCE(NULLIF(BTRIM(p_order_mode), ''), 'offline'),
        COALESCE(NULLIF(BTRIM(p_order_type), ''), 'pos_sale'),
        GREATEST(COALESCE(p_delivery_charge, 0), 0),
        GREATEST(COALESCE(p_discount_amount, 0), 0),
        GREATEST(COALESCE(p_manual_discount_amount, 0), 0),
        COALESCE(NULLIF(BTRIM(p_manual_discount_type), ''), 'flat'),
        GREATEST(COALESCE(p_manual_discount_value, 0), 0),
        NULLIF(BTRIM(COALESCE(p_coupon_code, '')), ''),
        GREATEST(COALESCE(p_coupon_percentage, 0), 0),
        GREATEST(COALESCE(p_total_gst, 0), 0), GREATEST(COALESCE(p_total_gst, 0), 0),
        COALESCE(p_gst_enabled, FALSE),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(p_split_details, '{}'::JSONB), v_branch, NOW(), NOW()
      );
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt = 5 THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_quantity := GREATEST(COALESCE(NULLIF(v_item ->> 'quantity', '')::NUMERIC, 0), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_item ->> 'base_price', '')::NUMERIC, 0), 0);
    v_line_total := GREATEST(
      COALESCE(NULLIF(v_item ->> 'line_total', '')::NUMERIC, v_quantity * v_price),
      0
    );
    v_source := COALESCE(NULLIF(v_item ->> 'source', ''), 'catalogue');

    IF v_uses_typed_item_ids THEN
      INSERT INTO public.order_items (
        order_id, product_id, variant_id, product_name, tamil_name, variant_name,
        quantity, unit, unit_price, line_total, is_manual, source, note
      ) VALUES (
        v_order_id, NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), '')::BIGINT,
        NULLIF(v_item ->> 'variant_id', '')::UUID, COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
        NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'variant_name', ''),
        v_quantity, COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'), v_price, v_line_total,
        v_source = 'manual', v_source, NULLIF(v_item ->> 'note', '')
      );
    ELSE
      INSERT INTO public.order_items (
        order_id, product_id, variant_id, product_name, tamil_name, variant_name,
        quantity, unit, unit_price, line_total, is_manual, source, note
      ) VALUES (
        v_order_id, NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), ''),
        NULLIF(v_item ->> 'variant_id', ''), COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
        NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'variant_name', ''),
        v_quantity, COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'), v_price, v_line_total,
        v_source = 'manual', v_source, NULLIF(v_item ->> 'note', '')
      );
    END IF;

    IF COALESCE(v_item ->> 'product_id', v_item ->> 'id', '') ~ '^[0-9]+$' THEN
      UPDATE public.products
      SET stock_quantity = GREATEST(stock_quantity - v_quantity, 0),
          stock = GREATEST(FLOOR(stock_quantity - v_quantity), 0)::INTEGER,
          updated_at = NOW()
      WHERE id::TEXT = COALESCE(v_item ->> 'product_id', v_item ->> 'id')
        AND branch = v_branch;
    END IF;

    IF NULLIF(v_item ->> 'variant_id', '') IS NOT NULL THEN
      UPDATE public.product_variants
      SET stock = GREATEST(stock - v_quantity, 0), updated_at = NOW()
      WHERE id::TEXT = v_item ->> 'variant_id'
        AND branch = v_branch;
    END IF;
  END LOOP;

  IF NULLIF(BTRIM(COALESCE(p_coupon_code, '')), '') IS NOT NULL THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code))
      AND is_active
      AND (usage_limit IS NULL OR usage_count < usage_limit);
  END IF;

  RETURN jsonb_build_object(
    'orderId', v_order_id,
    'invoiceNo', v_invoice_no,
    'createdAt', NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_with_stock(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_order_with_stock(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB, TEXT
) TO anon, authenticated;

-- 5. Branch-aware complete_pos_sale_with_inventory (primary POS RPC) ------

DROP FUNCTION IF EXISTS public.complete_pos_sale_with_inventory(
  TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC,
  TEXT, NUMERIC, TEXT, NUMERIC, TEXT, JSONB, NUMERIC, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION public.complete_pos_sale_with_inventory(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'completed',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_remarks TEXT DEFAULT NULL,
  p_reference_number TEXT DEFAULT NULL,
  p_billing_date TIMESTAMPTZ DEFAULT NULL,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC := 0;
  v_total NUMERIC := 0;
  v_item JSONB;
  v_product_id BIGINT;
  v_variant_id UUID;
  v_quantity NUMERIC;
  v_unit_price NUMERIC;
  v_line_total NUMERIC;
  v_product_name TEXT;
  v_name_ta TEXT;
  v_unit TEXT;
  v_unit_type TEXT;
  v_base_quantity NUMERIC;
  v_is_manual BOOLEAN;
  v_discount NUMERIC;
  v_gst_amount NUMERIC;
  v_gst_rate NUMERIC;
  v_image_url TEXT;
  v_variant_name TEXT;
  v_source TEXT;
  v_note TEXT;
  v_category TEXT;
  v_current_stock NUMERIC;
  v_barcode_id UUID;
  v_created_at TIMESTAMPTZ := COALESCE(p_billing_date, NOW());
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order items cannot be empty';
  END IF;

  -- 1. Atomic Pre-Validation of Available Stock for All Items (branch-scoped)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');

    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 2. Calculate Subtotal & Generate Invoice Number (from this branch's sequence)
  v_invoice_no := public.get_next_invoice_no(v_branch);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE(
      (v_item ->> 'unit_price')::NUMERIC,
      (v_item ->> 'base_price')::NUMERIC,
      (v_item ->> 'price')::NUMERIC,
      0
    );
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(0, ROUND(v_subtotal + COALESCE(p_shipping, 0) + COALESCE(p_delivery_charge, 0) - COALESCE(p_discount_amount, 0), 2));

  -- 3. Insert Order Record
  INSERT INTO public.orders (
    invoice_no, user_id, customer_name, phone, address, items,
    subtotal, shipping, total, status, order_mode, order_type,
    delivery_charge, discount_amount, manual_discount_amount,
    manual_discount_type, manual_discount_value, coupon_code,
    coupon_percentage, total_gst, gst_amount, gst_enabled,
    payment_method, payment_mode, split_details, remarks,
    reference_number, billing_date, branch, created_at, updated_at
  )
  VALUES (
    v_invoice_no, v_user_id, COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Customer'),
    COALESCE(p_phone, ''), COALESCE(p_address, ''), p_items,
    v_subtotal, COALESCE(p_shipping, 0), v_total, COALESCE(p_status, 'completed'),
    COALESCE(p_order_mode, 'offline'), COALESCE(p_order_type, 'pos_sale'),
    COALESCE(p_delivery_charge, 0), COALESCE(p_discount_amount, 0),
    COALESCE(p_manual_discount_amount, 0), COALESCE(p_manual_discount_type, 'flat'),
    COALESCE(p_manual_discount_value, 0), p_coupon_code,
    COALESCE(p_coupon_percentage, 0), COALESCE(p_total_gst, 0),
    COALESCE(p_total_gst, 0), COALESCE(p_gst_enabled, FALSE),
    COALESCE(p_payment_method, 'cash'), COALESCE(p_payment_method, 'cash'),
    COALESCE(p_split_details, '{}'::JSONB), p_remarks,
    p_reference_number, p_billing_date, v_branch, v_created_at, NOW()
  )
  RETURNING id INTO v_order_id;

  -- 4. Insert Order Items, Deduct Stock (branch-scoped) & Record SALE Movements
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE((v_item ->> 'unit_price')::NUMERIC, (v_item ->> 'base_price')::NUMERIC, 0);
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');
    v_name_ta := COALESCE(v_item ->> 'product_tamil_name', v_item ->> 'tamil_name', '');
    v_unit := COALESCE(v_item ->> 'unit', 'piece');
    v_unit_type := COALESCE(v_item ->> 'unit_type', 'unit');
    v_base_quantity := COALESCE((v_item ->> 'base_quantity')::NUMERIC, 1);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_discount := COALESCE((v_item ->> 'discount')::NUMERIC, 0);
    v_gst_amount := COALESCE((v_item ->> 'gst_amount')::NUMERIC, 0);
    v_gst_rate := COALESCE((v_item ->> 'gst_rate')::NUMERIC, 0);
    v_image_url := v_item ->> 'image_url';
    v_variant_name := v_item ->> 'variant_name';
    v_source := COALESCE(v_item ->> 'source', 'catalogue');
    v_note := v_item ->> 'note';
    v_category := v_item ->> 'category';

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name,
      product_tamil_name, tamil_name, quantity, unit, unit_type,
      base_quantity, base_price, unit_price, line_total, image_url,
      is_manual, discount, gst_amount, gst_rate, variant_name,
      source, note, category, created_at
    )
    VALUES (
      v_order_id, v_product_id, v_variant_id, v_product_name, v_product_name,
      v_name_ta, v_name_ta, v_quantity, v_unit, v_unit_type,
      v_base_quantity, v_unit_price, v_unit_price, v_line_total, v_image_url,
      v_is_manual, v_discount, v_gst_amount, v_gst_rate, v_variant_name,
      v_source, v_note, v_category, v_created_at
    );

    -- Deduct Stock and Insert SALE Movement (branch-scoped)
    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = v_variant_id AND is_active = TRUE LIMIT 1;

        UPDATE public.product_variants
        SET stock = GREATEST(0, stock - v_quantity), updated_at = NOW()
        WHERE id = v_variant_id AND branch = v_branch;

        -- Parent aggregate update
        UPDATE public.products
        SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE),
            stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE))::INTEGER,
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, v_variant_id, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );

      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = v_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - v_quantity),
            stock = GREATEST(0, stock - FLOOR(v_quantity)::INTEGER),
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, NULL, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );
      END IF;
    END IF;
  END LOOP;

  -- 5. Increment Coupon Usage Count (coupons remain shared across branches)
  IF p_coupon_code IS NOT NULL AND BTRIM(p_coupon_code) <> '' THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1, updated_at = NOW()
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code));
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'invoice_no', v_invoice_no,
    'total', v_total
  );
END;
$$;

-- 6. Advance orders (deposit-based custom orders) must also be branch-scoped:
-- completing one allocates an invoice number, so it has to draw from the same
-- per-branch sequence as regular POS sales or numbers would collide/cross-book.

ALTER TABLE public.advance_orders ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';

DO $$
BEGIN
  ALTER TABLE public.advance_orders ADD CONSTRAINT advance_orders_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

CREATE INDEX IF NOT EXISTS advance_orders_branch_idx ON public.advance_orders(branch, created_at DESC);

DROP FUNCTION IF EXISTS public.create_advance_order(text,text,text,text,text,text,numeric,numeric,date,text,text,text,jsonb);

CREATE OR REPLACE FUNCTION public.create_advance_order(
  p_customer_name text, p_phone text, p_address text, p_product_name text,
  p_category text, p_description text, p_total_amount numeric, p_deposit_amount numeric,
  p_expected_delivery_date date, p_remarks text, p_payment_method text, p_created_by_name text,
  p_products jsonb DEFAULT '[]'::jsonb,
  p_branch text DEFAULT 'pos1'
)
RETURNS public.advance_orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_order public.advance_orders; v_now timestamptz := now(); v_deposit_id text; v_branch text := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF trim(coalesce(p_customer_name,'')) = '' THEN RAISE EXCEPTION 'Customer name is required'; END IF;
  IF trim(coalesce(p_phone,'')) = '' THEN RAISE EXCEPTION 'Phone number is required'; END IF;
  IF trim(coalesce(p_product_name,'')) = '' THEN RAISE EXCEPTION 'Product name is required'; END IF;
  IF coalesce(p_total_amount,0) <= 0 THEN RAISE EXCEPTION 'Total amount must be greater than zero'; END IF;
  IF coalesce(p_deposit_amount,0) <= 0 OR p_deposit_amount >= p_total_amount THEN RAISE EXCEPTION 'Deposit must be greater than zero and less than the total amount'; END IF;
  IF lower(coalesce(p_payment_method,'')) NOT IN ('cash','upi','card') THEN RAISE EXCEPTION 'Select a valid deposit payment method'; END IF;
  v_deposit_id := 'DEP-' || to_char(v_now at time zone 'Asia/Kolkata','YYYYMMDD') || '-' || lpad(nextval('public.deposit_number_seq')::text,4,'0');
  INSERT INTO public.advance_orders(deposit_id,customer_name,phone,address,product_name,products,category,description,total_amount,deposit_amount,expected_delivery_date,remarks,created_by,created_by_name,created_at,updated_at,branch)
  VALUES(v_deposit_id,trim(p_customer_name),trim(p_phone),trim(coalesce(p_address,'')),trim(p_product_name),CASE WHEN jsonb_typeof(coalesce(p_products,'[]'::jsonb))='array' THEN coalesce(p_products,'[]'::jsonb) ELSE '[]'::jsonb END,trim(coalesce(p_category,'')),trim(coalesce(p_description,'')),round(p_total_amount,2),round(p_deposit_amount,2),p_expected_delivery_date,trim(coalesce(p_remarks,'')),auth.uid(),trim(coalesce(p_created_by_name,'')),v_now,v_now,v_branch)
  RETURNING * INTO v_order;
  INSERT INTO public.advance_order_payments(advance_order_id,payment_type,amount,payment_method,remarks,received_by,received_at)
  VALUES(v_order.id,'deposit',v_order.deposit_amount,lower(p_payment_method),coalesce(p_remarks,''),auth.uid(),v_now);
  INSERT INTO public.advance_order_timeline(advance_order_id,event_type,label,created_by,created_at) VALUES
    (v_order.id,'created','Created',auth.uid(),v_now),
    (v_order.id,'deposit_received','Deposit Received',auth.uid(),v_now);
  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_advance_order(text,text,text,text,text,text,numeric,numeric,date,text,text,text,jsonb,text) TO anon, authenticated;

-- Redefine the (self-healing) completion RPC to derive branch from the advance
-- order itself â€” safer than trusting a client-supplied branch â€” and to pull
-- the invoice number from that branch's sequence via get_next_invoice_no()
-- instead of hitting the old shared invoice_number_seq directly (which would
-- otherwise collide with regular POS sales once branches have separate sequences).
CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;
  v_branch         text;
BEGIN
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;

  v_branch := CASE WHEN v_advance.branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;

  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;

  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    IF v_advance.status != 'completed' THEN
      UPDATE public.advance_orders
      SET status = 'completed',
          updated_at = v_now
      WHERE id = p_order_id;
    END IF;

    RETURN QUERY SELECT
      coalesce(v_advance.completed_order_id, gen_random_uuid()),
      coalesce(v_advance.invoice_number, 'INV00000000'),
      coalesce(v_advance.completed_at, v_now);
    RETURN;
  END IF;

  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  v_invoice := public.get_next_invoice_no(v_branch);

  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;

  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, branch, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_items, v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method), v_branch,
    v_now, v_now
  );

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    INSERT INTO public.order_items (
      order_id, product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id,
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      greatest(coalesce((v_item->>'quantity')::numeric, 1), 0),
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );
  END LOOP;

  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text) TO public, anon, authenticated;

-- 7. Give POS 1 and POS 2 visibly different auto-generated barcode values.
-- POS 1 keeps the exact prefix/sequence it already had ('PBP'/'PBV', same
-- barcode_product_seq/barcode_variant_seq) so nothing about barcodes you've
-- already generated or printed changes. POS 2 gets its own fresh sequences
-- and a distinct 'P2P'/'P2V' prefix, so a scanned code instantly tells you
-- which branch it belongs to. Existing barcode_registry rows are untouched â€”
-- this only changes what NEW barcodes look like going forward.

CREATE SEQUENCE IF NOT EXISTS public.barcode_product_seq_pos2 START WITH 10000001;
CREATE SEQUENCE IF NOT EXISTS public.barcode_variant_seq_pos2 START WITH 10000001;

DROP FUNCTION IF EXISTS public.generate_barcode_value(TEXT);

CREATE OR REPLACE FUNCTION public.generate_barcode_value(p_entity_type TEXT, p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_branch = 'pos2' THEN
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
$$;

-- 8. Fix inventory_movements.branch on barcode receipt / stock adjustment
-- RPCs: these never took a branch param and would otherwise leave every
-- movement defaulted to 'pos1' regardless of which branch's stock moved.
-- Derive the branch from the product/variant row being touched instead.

CREATE OR REPLACE FUNCTION public.create_barcode_and_receive_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_quantity_received NUMERIC DEFAULT 0,
  p_unit_cost NUMERIC DEFAULT NULL,
  p_created_by_name TEXT DEFAULT '',
  p_custom_barcode TEXT DEFAULT NULL,
  p_note TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entity_type TEXT;
  v_barcode_id UUID;
  v_barcode_value TEXT;
  v_is_new_barcode BOOLEAN := FALSE;
  v_movement_type TEXT;
  v_qty_before NUMERIC := 0;
  v_qty_after NUMERIC := 0;
  v_prod_name TEXT;
  v_var_name TEXT := '';
  v_branch TEXT;
BEGIN
  IF p_quantity_received < 0 THEN
    RAISE EXCEPTION 'Quantity received cannot be negative';
  END IF;

  -- 1. Check Parent Product Exists (and capture its branch)
  SELECT name, branch INTO v_prod_name, v_branch FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product with ID % not found', p_product_id;
  END IF;

  -- 2. Verify Variant Belongs to Product if Variant is Provided
  IF p_variant_id IS NOT NULL THEN
    v_entity_type := 'variant';
    SELECT variant_name, stock INTO v_var_name, v_qty_before
    FROM public.product_variants
    WHERE id = p_variant_id AND product_id = p_product_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Variant % does not belong to Product %', p_variant_id, p_product_id;
    END IF;
  ELSE
    v_entity_type := 'product';
    SELECT stock_quantity INTO v_qty_before
    FROM public.products
    WHERE id = p_product_id;
  END IF;

  -- 3. Check for Existing Active Barcode in barcode_registry (SKU Identity)
  IF v_entity_type = 'variant' THEN
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE variant_id = p_variant_id AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  ELSE
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  -- 4. Reuse Existing or Create New Barcode
  IF v_barcode_id IS NOT NULL THEN
    v_is_new_barcode := FALSE;
    v_movement_type := CASE WHEN v_qty_before = 0 THEN 'INITIAL_BARCODE_STOCK' ELSE 'RESTOCK' END;
  ELSE
    v_is_new_barcode := TRUE;
    v_movement_type := 'INITIAL_BARCODE_STOCK';
    v_barcode_value := COALESCE(NULLIF(UPPER(BTRIM(p_custom_barcode)), ''), public.generate_barcode_value(v_entity_type, v_branch));

    INSERT INTO public.barcode_registry (
      barcode_value, entity_type, product_id, variant_id, is_active, created_by_name, branch
    )
    VALUES (
      v_barcode_value, v_entity_type, p_product_id, p_variant_id, TRUE, COALESCE(p_created_by_name, ''), v_branch
    )
    RETURNING id INTO v_barcode_id;
  END IF;

  -- 5. Synchronize compatibility column on target table
  IF v_entity_type = 'variant' THEN
    UPDATE public.product_variants
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_variant_id;
  ELSE
    UPDATE public.products
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- 6. Apply Stock Increment & Parent Aggregate Sync
  v_qty_after := v_qty_before + p_quantity_received;

  IF p_quantity_received > 0 THEN
    IF v_entity_type = 'variant' THEN
      UPDATE public.product_variants
      SET stock = v_qty_after, updated_at = NOW()
      WHERE id = p_variant_id;

      -- Refresh parent aggregate stock cache
      UPDATE public.products
      SET stock_quantity = (
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ),
          stock = FLOOR((
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ))::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    ELSE
      UPDATE public.products
      SET stock_quantity = v_qty_after,
          stock = FLOOR(v_qty_after)::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    END IF;
  END IF;

  -- 7. Record Immutable Inventory Movement
  IF p_quantity_received > 0 THEN
    INSERT INTO public.inventory_movements (
      product_id, variant_id, barcode_id, movement_type,
      quantity_delta, quantity_before, quantity_after,
      unit_cost, reference_type, reference_id, note, created_by_name, branch
    )
    VALUES (
      p_product_id, p_variant_id, v_barcode_id, v_movement_type,
      p_quantity_received, v_qty_before, v_qty_after,
      p_unit_cost, 'barcode_receipt', v_barcode_value,
      COALESCE(p_note, ''), COALESCE(p_created_by_name, ''), v_branch
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'barcode_id', v_barcode_id,
    'barcode_value', v_barcode_value,
    'is_new_barcode', v_is_new_barcode,
    'movement_type', v_movement_type,
    'quantity_before', v_qty_before,
    'quantity_received', p_quantity_received,
    'quantity_after', v_qty_after,
    'product_id', p_product_id,
    'variant_id', p_variant_id,
    'product_name', v_prod_name,
    'variant_name', v_var_name
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_inventory_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_new_quantity NUMERIC DEFAULT 0,
  p_reason TEXT DEFAULT 'RESTOCK',
  p_note TEXT DEFAULT '',
  p_created_by_name TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qty_before NUMERIC := 0;
  v_delta NUMERIC := 0;
  v_barcode_id UUID;
  v_branch TEXT;
BEGIN
  IF p_new_quantity < 0 THEN
    RAISE EXCEPTION 'Stock quantity cannot be negative';
  END IF;

  -- Verify variant if supplied
  IF p_variant_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_variants WHERE id = p_variant_id AND product_id = p_product_id) THEN
      RAISE EXCEPTION 'Variant does not belong to specified Product';
    END IF;

    SELECT stock, branch INTO v_qty_before, v_branch FROM public.product_variants WHERE id = p_variant_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = p_variant_id AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.product_variants
    SET stock = p_new_quantity, updated_at = NOW()
    WHERE id = p_variant_id;

    -- Refresh parent aggregate
    UPDATE public.products
    SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE),
        stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE))::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  ELSE
    SELECT stock_quantity, branch INTO v_qty_before, v_branch FROM public.products WHERE id = p_product_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.products
    SET stock_quantity = p_new_quantity,
        stock = FLOOR(p_new_quantity)::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- Record Movement
  INSERT INTO public.inventory_movements (
    product_id, variant_id, barcode_id, movement_type,
    quantity_delta, quantity_before, quantity_after,
    reference_type, note, created_by_name, branch
  )
  VALUES (
    p_product_id, p_variant_id, v_barcode_id, p_reason,
    v_delta, v_qty_before, p_new_quantity,
    'adjustment', COALESCE(p_note, ''), COALESCE(p_created_by_name, ''), v_branch
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'quantity_before', v_qty_before,
    'quantity_after', p_new_quantity,
    'delta', v_delta,
    'reason', p_reason
  );
END;
$$;

COMMIT;

-- ============================================================
-- SECTION 21 / 32 â€” 20260925_0021_cleanup_legacy_chaji_data.sql
-- ============================================================

-- ====================================================================
-- Migration 0021: Remove legacy CHAJI MENS WEAR data before seeding the
-- new YG Enterprises branch catalogs (migration 0022).
--
-- Scope, deliberately conservative:
--  - Clears the old product/variant/barcode/category catalog (all of it â€”
--    every row currently in these tables predates the YG rebrand and is
--    CHAJI menswear stock).
--  - Resets the store_settings row (name/owner/phone/email/address) to
--    YG Enterprises' real details.
--  - Empties the unused 'branding' storage bucket created for CHAJI.
--
-- Deliberately NOT touched: `orders` / `order_items` (real historical
-- sales/financial records survive regardless of brand â€” order_items
-- already stores product_name redundantly, and orders.product_id uses
-- ON DELETE SET NULL, so deleting the old catalog does not corrupt past
-- receipts) and `coupons` (not brand-specific).
-- ====================================================================

BEGIN;

-- 1. Clear the legacy product catalog (respecting FK delete order:
-- barcode_registry -> RESTRICT on product_id/variant_id, so it must go
-- first; product_variants and inventory_movements reference products
-- with CASCADE / SET NULL respectively, so those are safe once
-- barcode_registry is clear).
DELETE FROM public.barcode_registry;
DELETE FROM public.product_variants;
DELETE FROM public.products;
DELETE FROM public.categories;

-- 2. Reset store contact details to YG Enterprises (src/lib/brand.ts is the
-- client-side source of truth these values are kept in sync with).
UPDATE public.store_settings
SET name = 'YG ENTERPRISES',
    owner_name = 'M. Gurumoorthy',
    phone = '+91 98844 10700, +91 97878 08090',
    email = 'ygenterprises2000@gmail.com',
    address = '#189, N.S.C. Bose Road, (Opp. Bus Depot, Hotel Sankar Cafe Building), Chennai - 600 001',
    updated_at = NOW()
WHERE id = 1
  -- Guarded: only while the row is still on a legacy / placeholder identity
  -- (0001 default, section 12 CLAD seed or section 16 CHAJI rebrand). This is
  -- the same self-healing rule 20261004_0033 uses, so a database that missed
  -- this migration is still repaired, while a profile the owner has already
  -- edited from Admin -> Store Settings is never overwritten.
  AND COALESCE(email, '') IN (
        'mypurpleboutique05@gmail.com',
        'cladclothing26@gmail.com',
        'chandrums1552004@gmail.com'
      );

-- 3. NOTE: any leftover files in the 'branding' storage bucket (created for
-- CHAJI in migration 0016) are intentionally left alone here â€” Supabase
-- blocks direct `DELETE FROM storage.objects` with a protective trigger
-- ("Direct deletion from storage tables is not allowed"). Nothing in this
-- app reads from that bucket, so stray files there are harmless; clear them
-- from the Supabase Dashboard -> Storage -> branding (or the Storage API)
-- if you want it empty.

COMMIT;

-- ============================================================
-- SECTION 22 / 32 â€” 20260925_0022_seed_branch_starter_catalog.sql
-- ============================================================

-- ====================================================================
-- Migration 0021: Starter catalog for POS 1 (Jute & Wedding Bags) and
-- POS 2 (Clothing), demonstrating the branch-isolated catalogs added in
-- migration 0020. Safe to re-run: every insert is guarded so it never
-- duplicates a category/product that already exists for that branch.
-- Requires migration 0020 (branch columns) to already be applied.
-- ====================================================================

BEGIN;

-- 1. Categories -----------------------------------------------------------

INSERT INTO public.categories (name_en, name_ta, branch, sort_order, is_active)
SELECT v.name_en, v.name_ta, v.branch, v.sort_order, TRUE
FROM (VALUES
  ('Jute Bags',     '', 'pos1', 1),
  ('Wedding Bags',  '', 'pos1', 2),
  ('Wedding Cards', '', 'pos1', 3),
  ('Dresses',       '', 'pos2', 1),
  ('Ethnic Wear',   '', 'pos2', 2),
  ('Kids Wear',     '', 'pos2', 3)
) AS v(name_en, name_ta, branch, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.categories c
  WHERE c.branch = v.branch AND LOWER(BTRIM(c.name_en)) = LOWER(BTRIM(v.name_en))
)
AND NOT EXISTS (
  SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260925_0022_seed_branch_starter_catalog'
);

-- 2. Products ---------------------------------------------------------------
-- unit_type 'unit' / unit_label 'piece' â€” simple non-variant starter items.
-- Prices are placeholders; edit them freely from Inventory once seeded.

INSERT INTO public.products (
  name, category, category_id, branch, price, purchase_price, mrp,
  unit_type, unit_label, unit, base_quantity,
  stock_quantity, stock, low_stock_alert, is_active, sort_order
)
SELECT
  v.name, v.category,
  (SELECT id FROM public.categories WHERE branch = v.branch AND LOWER(BTRIM(name_en)) = LOWER(BTRIM(v.category))),
  v.branch, v.price, v.purchase_price, v.mrp,
  'unit', 'piece', 'piece', 1,
  v.stock, v.stock, 5, TRUE, v.sort_order
FROM (VALUES
  -- POS 1 Â· Jute & Wedding Bags / Wedding Cards -----------------------
  ('Plain Jute Shopping Bag',          'Jute Bags',     'pos1', 150::numeric,  80::numeric, 180::numeric, 40::numeric, 1),
  ('Printed Jute Tote Bag',            'Jute Bags',     'pos1', 220::numeric, 120::numeric, 260::numeric, 30::numeric, 2),
  ('Floral Jute Tote Bag',             'Jute Bags',     'pos1', 250::numeric, 140::numeric, 300::numeric, 30::numeric, 3),
  ('Designer Jute Bag with Handle',    'Jute Bags',     'pos1', 320::numeric, 180::numeric, 380::numeric, 20::numeric, 4),
  ('Bridal Wedding Return Gift Bag',   'Wedding Bags',  'pos1', 280::numeric, 150::numeric, 340::numeric, 25::numeric, 1),
  ('Embroidered Wedding Favor Bag',    'Wedding Bags',  'pos1', 350::numeric, 190::numeric, 420::numeric, 20::numeric, 2),
  ('Silk Wedding Potli Bag',           'Wedding Bags',  'pos1', 180::numeric, 100::numeric, 220::numeric, 35::numeric, 3),
  ('Traditional Wedding Invitation Card', 'Wedding Cards', 'pos1', 25::numeric, 12::numeric,  30::numeric, 200::numeric, 1),
  ('Floral Wedding Card with Envelope',   'Wedding Cards', 'pos1', 35::numeric, 18::numeric,  42::numeric, 150::numeric, 2),
  ('Premium Laser-Cut Wedding Card',      'Wedding Cards', 'pos1', 65::numeric, 35::numeric,  75::numeric, 100::numeric, 3),

  -- POS 2 Â· Dresses / Ethnic Wear / Kids Wear -------------------------
  ('Floral Print Cotton Dress',        'Dresses',       'pos2', 799::numeric,  450::numeric,  999::numeric, 30::numeric, 1),
  ('A-Line Party Dress',               'Dresses',       'pos2', 1199::numeric, 700::numeric, 1499::numeric, 20::numeric, 2),
  ('Casual Maxi Dress',                'Dresses',       'pos2', 899::numeric,  520::numeric, 1099::numeric, 25::numeric, 3),
  ('Cotton Anarkali Kurti',            'Ethnic Wear',   'pos2', 699::numeric,  400::numeric,  899::numeric, 30::numeric, 1),
  ('Printed Cotton Saree',             'Ethnic Wear',   'pos2', 1299::numeric, 750::numeric, 1599::numeric, 15::numeric, 2),
  ('Chiffon Party Saree',              'Ethnic Wear',   'pos2', 1599::numeric, 950::numeric, 1999::numeric, 10::numeric, 3),
  ('Kids Cotton Frock',                'Kids Wear',     'pos2', 449::numeric,  250::numeric,  549::numeric, 40::numeric, 1),
  ('Boys Casual Shirt',                'Kids Wear',     'pos2', 399::numeric,  220::numeric,  499::numeric, 40::numeric, 2)
) AS v(name, category, branch, price, purchase_price, mrp, stock, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.products p
  WHERE p.branch = v.branch AND LOWER(BTRIM(p.name)) = LOWER(BTRIM(v.name))
)
AND NOT EXISTS (
  SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260925_0022_seed_branch_starter_catalog'
);

-- Mark this seed as applied so a re-run can never recreate a product that an
-- operator has since deleted (see migration 0036).
INSERT INTO public.seed_ledger (seed_key)
VALUES ('20260925_0022_seed_branch_starter_catalog')
ON CONFLICT (seed_key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- SECTION 23 / 32 â€” 20260926_0023_branch_settings_and_attendance.sql
-- ============================================================

-- ====================================================================
-- Migration 0023: Per-branch Store Settings + Staff Attendance
--
-- 1. store_settings becomes 2 rows (one per branch) instead of a single
--    global row, with extra self-service profile fields (business type,
--    Instagram, logo, accent colour).
-- 2. New staff_members + attendance_records tables: staff pick their name
--    and punch in/out from the POS side; admin sees/overrides it per branch.
-- ====================================================================

BEGIN;

-- 1. Store settings: unlock a 2nd row and add profile fields --------------

ALTER TABLE public.store_settings DROP CONSTRAINT IF EXISTS store_settings_id_check;
ALTER TABLE public.store_settings ADD CONSTRAINT store_settings_id_check CHECK (id IN (1, 2));

ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS business_type TEXT NOT NULL DEFAULT '';
ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS instagram_id TEXT NOT NULL DEFAULT '';
ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS logo_url TEXT;
ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS theme_color TEXT NOT NULL DEFAULT '#8B1A1A';

DO $$
BEGIN
  ALTER TABLE public.store_settings ADD CONSTRAINT store_settings_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS store_settings_branch_unique ON public.store_settings(branch);

UPDATE public.store_settings SET branch = 'pos1', theme_color = '#8B1A1A' WHERE id = 1;

INSERT INTO public.store_settings (id, branch, name, owner_name, phone, email, address, business_type, theme_color, gst_enabled)
VALUES (
  2, 'pos2', 'YG ENTERPRISES', 'M. Gurumoorthy',
  '+91 98844 10700, +91 97878 08090', 'ygenterprises2000@gmail.com',
  '#189, N.S.C. Bose Road, (Opp. Bus Depot, Hotel Sankar Cafe Building), Chennai - 600 001',
  '', '#B8860B', FALSE
)
ON CONFLICT (id) DO NOTHING;

-- 2. Staff members & attendance ------------------------------------------

CREATE TABLE IF NOT EXISTS public.staff_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  branch TEXT NOT NULL CHECK (branch IN ('pos1', 'pos2')),
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'staff',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS staff_members_branch_idx ON public.staff_members(branch, is_active);

CREATE TABLE IF NOT EXISTS public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_member_id UUID NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  branch TEXT NOT NULL CHECK (branch IN ('pos1', 'pos2')),
  attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
  clock_in TIMESTAMPTZ,
  clock_out TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'absent', 'half_day', 'leave')),
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (staff_member_id, attendance_date)
);

CREATE INDEX IF NOT EXISTS attendance_records_branch_date_idx ON public.attendance_records(branch, attendance_date DESC);

ALTER TABLE public.staff_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_members_portal_manage ON public.staff_members;
CREATE POLICY staff_members_portal_manage ON public.staff_members FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS attendance_records_portal_manage ON public.attendance_records;
CREATE POLICY attendance_records_portal_manage ON public.attendance_records FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);

-- Punch in/out RPC: upserts today's row for that staff member. Punching
-- "in" only ever sets clock_in the first time (repeat taps don't overwrite
-- an existing clock-in); punching "out" always stamps the latest time.
CREATE OR REPLACE FUNCTION public.punch_attendance(
  p_staff_member_id UUID,
  p_action TEXT
)
RETURNS public.attendance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch TEXT;
  v_row public.attendance_records;
BEGIN
  SELECT branch INTO v_branch FROM public.staff_members WHERE id = p_staff_member_id AND is_active = TRUE;
  IF v_branch IS NULL THEN
    RAISE EXCEPTION 'Staff member not found';
  END IF;

  IF p_action NOT IN ('in', 'out') THEN
    RAISE EXCEPTION 'Invalid punch action';
  END IF;

  INSERT INTO public.attendance_records (staff_member_id, branch, attendance_date, clock_in, clock_out, status)
  VALUES (
    p_staff_member_id, v_branch, CURRENT_DATE,
    CASE WHEN p_action = 'in' THEN NOW() ELSE NULL END,
    CASE WHEN p_action = 'out' THEN NOW() ELSE NULL END,
    'present'
  )
  ON CONFLICT (staff_member_id, attendance_date) DO UPDATE SET
    clock_in = CASE
      WHEN p_action = 'in' AND public.attendance_records.clock_in IS NULL THEN NOW()
      ELSE public.attendance_records.clock_in
    END,
    clock_out = CASE WHEN p_action = 'out' THEN NOW() ELSE public.attendance_records.clock_out END,
    status = 'present',
    updated_at = NOW()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.punch_attendance(UUID, TEXT) TO anon, authenticated;

COMMIT;

-- ============================================================
-- SECTION 24 / 32 â€” 20260927_0024_pos2_fireworks_catalog.sql
-- ============================================================

-- ====================================================================
-- Migration 0024: Replace POS 2's starter catalog (clothing, seeded by
-- migration 0022) with a fireworks & crackers catalog matching POS 2's
-- real business. POS 1 already matches its real business (jute/wedding
-- bags, wedding cards) from migration 0022 and is untouched here.
--
-- Scope: every DELETE/SELECT below is filtered to branch = 'pos2', so
-- POS 1's catalog and both branches' `orders` / `order_items` history
-- are never touched. Idempotent: safe to re-run (product/category
-- inserts are guarded, business_type updates are plain overwrites).
-- ====================================================================

BEGIN;

-- Bootstrap the ledger table if missing (migration 0036 not yet applied).
DO $$
BEGIN
  IF to_regclass('public.seed_ledger') IS NULL THEN
    CREATE TABLE public.seed_ledger (
      seed_key   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  END IF;
END $$;

-- 1. Clear POS 2's old clothing catalog only (respecting FK delete order:
-- barcode_registry -> RESTRICT on product_id/variant_id, so it must go
-- first; product_variants and inventory_movements reference products
-- with CASCADE / SET NULL respectively).
--
-- DELETION SAFETY: the statements below are unconditional DELETEs scoped to
-- POS 2. Once this seed has been applied, re-running the file must not wipe
-- the live POS 2 catalog that an operator has since built or edited, so the
-- whole block is gated on the seed_ledger marker (see migration 0036).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.seed_ledger
    WHERE seed_key = '20260927_0024_pos2_fireworks_catalog'
  ) THEN
    RETURN;
  END IF;

  DELETE FROM public.barcode_registry WHERE branch = 'pos2';
  DELETE FROM public.product_variants WHERE branch = 'pos2';
  DELETE FROM public.products WHERE branch = 'pos2';
  DELETE FROM public.categories WHERE branch = 'pos2';
END $$;

-- 2. Seed POS 2's fireworks & crackers categories --------------------------

INSERT INTO public.categories (name_en, name_ta, branch, sort_order, is_active)
SELECT v.name_en, v.name_ta, v.branch, v.sort_order, TRUE
FROM (VALUES
  ('Sparklers',               '', 'pos2', 1),
  ('Flower Pots & Chakras',   '', 'pos2', 2),
  ('Sound & Aerial Crackers', '', 'pos2', 3),
  ('Gift Boxes',              '', 'pos2', 4)
) AS v(name_en, name_ta, branch, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.categories c
  WHERE c.branch = v.branch AND LOWER(BTRIM(c.name_en)) = LOWER(BTRIM(v.name_en))
)
AND NOT EXISTS (
  SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260927_0024_pos2_fireworks_catalog'
);

-- 3. Seed POS 2's fireworks & crackers products -----------------------------
-- Prices are placeholders; edit them freely from Inventory once seeded.

INSERT INTO public.products (
  name, category, category_id, branch, price, purchase_price, mrp,
  unit_type, unit_label, unit, base_quantity,
  stock_quantity, stock, low_stock_alert, is_active, sort_order
)
SELECT
  v.name, v.category,
  (SELECT id FROM public.categories WHERE branch = v.branch AND LOWER(BTRIM(name_en)) = LOWER(BTRIM(v.category))),
  v.branch, v.price, v.purchase_price, v.mrp,
  'unit', 'piece', 'piece', 1,
  v.stock, v.stock, 10, TRUE, v.sort_order
FROM (VALUES
  ('7cm Electric Sparklers (Box of 10)',  'Sparklers',               'pos2',   40::numeric,   22::numeric,   45::numeric, 100::numeric, 1),
  ('10cm Colour Sparklers (Box of 10)',   'Sparklers',               'pos2',   60::numeric,   35::numeric,   68::numeric,  80::numeric, 2),
  ('30cm Sparklers (Box of 5)',           'Sparklers',               'pos2',  120::numeric,   70::numeric,  135::numeric,  60::numeric, 3),
  ('Small Flower Pot (Box of 10)',        'Flower Pots & Chakras',   'pos2',  150::numeric,   90::numeric,  170::numeric,  50::numeric, 1),
  ('Deluxe Flower Pot (Box of 5)',        'Flower Pots & Chakras',   'pos2',  250::numeric,  150::numeric,  280::numeric,  40::numeric, 2),
  ('Ground Chakkar (Pack of 10)',         'Flower Pots & Chakras',   'pos2',   90::numeric,   50::numeric,  100::numeric,  60::numeric, 3),
  ('Lakshmi Sound Crackers (Box of 10)',  'Sound & Aerial Crackers', 'pos2',   90::numeric,   50::numeric,  100::numeric,  70::numeric, 1),
  ('2000 Wala Garland Cracker',           'Sound & Aerial Crackers', 'pos2',  450::numeric,  280::numeric,  500::numeric,  25::numeric, 2),
  ('7 Shot Aerial Fountain',              'Sound & Aerial Crackers', 'pos2',  350::numeric,  210::numeric,  390::numeric,  30::numeric, 3),
  ('Skyshot Rocket (Pack of 5)',          'Sound & Aerial Crackers', 'pos2',  300::numeric,  180::numeric,  330::numeric,  35::numeric, 4),
  ('Family Combo Gift Box',               'Gift Boxes',              'pos2', 1500::numeric,  950::numeric, 1650::numeric,  15::numeric, 1),
  ('Deluxe Assortment Gift Box',          'Gift Boxes',              'pos2', 2500::numeric, 1600::numeric, 2750::numeric,  10::numeric, 2)
) AS v(name, category, branch, price, purchase_price, mrp, stock, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.products p
  WHERE p.branch = v.branch AND LOWER(BTRIM(p.name)) = LOWER(BTRIM(v.name))
)
AND NOT EXISTS (
  SELECT 1 FROM public.seed_ledger WHERE seed_key = '20260927_0024_pos2_fireworks_catalog'
);

-- 4. Record each branch's actual business line in Store Settings
-- (Store Settings > Shop Profile > Business Type).
-- Gated on the same marker so a re-run never re-applies the placeholder
-- business type over a value the operator has since edited.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.seed_ledger
    WHERE seed_key = '20260927_0024_pos2_fireworks_catalog'
  ) THEN
    UPDATE public.store_settings SET business_type = 'Wedding Cards, Bags & Jute Bag Manufacturing', updated_at = NOW() WHERE branch = 'pos1';
    UPDATE public.store_settings SET business_type = 'Fireworks & Crackers', updated_at = NOW() WHERE branch = 'pos2';
  END IF;
END $$;

-- Mark this seed as applied. Every guard above is a no-op from here on, so a
-- future re-run can neither resurrect a deleted product nor wipe POS 2.
INSERT INTO public.seed_ledger (seed_key)
VALUES ('20260927_0024_pos2_fireworks_catalog')
ON CONFLICT (seed_key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- SECTION 25 / 32 â€” 20260928_0025_portal_credentials.sql
-- ============================================================

-- ====================================================================
-- Migration 0025: Admin-editable portal passwords
--
-- Login credentials for the Admin Orchestrator / POS 1 staff / POS 2
-- staff portals were previously fixed at build time via Vite env vars
-- (VITE_ADMIN_PASSWORD / VITE_POS1_STAFF_PASSWORD / VITE_POS2_STAFF_PASSWORD),
-- with no way to change a password without editing .env and redeploying.
--
-- This table lets the admin change any of the 3 passwords from inside
-- the app (Dashboard > Staff & Memberships). A NULL password_override
-- means "keep using the .env default" for that account; Portal IDs are
-- unaffected and still come from .env.
--
-- Note on trust model: like every other table in this schema, RLS here
-- is permissive (USING (TRUE)) because there is no real Supabase Auth
-- session for the POS portal logins -- this app authenticates client-side
-- against a fixed credential set, the same trust level as the .env
-- passwords it replaces (both are readable by anyone who inspects the
-- client, since the anon key is public). This is not a security upgrade,
-- just a way to change the password without a redeploy.
-- ====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.portal_credentials (
  role_key TEXT PRIMARY KEY CHECK (role_key IN ('admin', 'pos1_staff', 'pos2_staff')),
  password_override TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.portal_credentials (role_key, password_override)
VALUES ('admin', NULL), ('pos1_staff', NULL), ('pos2_staff', NULL)
ON CONFLICT (role_key) DO NOTHING;

ALTER TABLE public.portal_credentials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS portal_credentials_portal_manage ON public.portal_credentials;
CREATE POLICY portal_credentials_portal_manage ON public.portal_credentials FOR ALL TO anon, authenticated USING (TRUE) WITH CHECK (TRUE);

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- SECTION 26 / 32 â€” 20260929_0026_fix_null_remarks_checkout_error.sql
-- ============================================================

-- ====================================================================
-- Migration 0026: Fix "null value in column remarks... violates
-- not-null constraint" on POS checkout.
--
-- complete_pos_sale_with_inventory() (redefined in migration 0020 for
-- the branch split) inserts the raw p_remarks / p_reference_number
-- parameters directly into orders.remarks / orders.reference_number.
-- Both columns are NOT NULL (added in migration 0011 with DEFAULT ''),
-- but the RPC parameters default to NULL and the frontend doesn't
-- always pass them, so an explicit NULL was being inserted -- which
-- overrides the column's own DEFAULT '' and fails the NOT NULL check.
--
-- Fix: COALESCE both to '' before insert, same as every other nullable
-- text field in this function already does.
-- ====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.complete_pos_sale_with_inventory(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'completed',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_remarks TEXT DEFAULT NULL,
  p_reference_number TEXT DEFAULT NULL,
  p_billing_date TIMESTAMPTZ DEFAULT NULL,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC := 0;
  v_total NUMERIC := 0;
  v_item JSONB;
  v_product_id BIGINT;
  v_variant_id UUID;
  v_quantity NUMERIC;
  v_unit_price NUMERIC;
  v_line_total NUMERIC;
  v_product_name TEXT;
  v_name_ta TEXT;
  v_unit TEXT;
  v_unit_type TEXT;
  v_base_quantity NUMERIC;
  v_is_manual BOOLEAN;
  v_discount NUMERIC;
  v_gst_amount NUMERIC;
  v_gst_rate NUMERIC;
  v_image_url TEXT;
  v_variant_name TEXT;
  v_source TEXT;
  v_note TEXT;
  v_category TEXT;
  v_current_stock NUMERIC;
  v_barcode_id UUID;
  v_created_at TIMESTAMPTZ := COALESCE(p_billing_date, NOW());
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order items cannot be empty';
  END IF;

  -- 1. Atomic Pre-Validation of Available Stock for All Items (branch-scoped)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');

    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 2. Calculate Subtotal & Generate Invoice Number (from this branch's sequence)
  v_invoice_no := public.get_next_invoice_no(v_branch);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE(
      (v_item ->> 'unit_price')::NUMERIC,
      (v_item ->> 'base_price')::NUMERIC,
      (v_item ->> 'price')::NUMERIC,
      0
    );
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(0, ROUND(v_subtotal + COALESCE(p_shipping, 0) + COALESCE(p_delivery_charge, 0) - COALESCE(p_discount_amount, 0), 2));

  -- 3. Insert Order Record
  INSERT INTO public.orders (
    invoice_no, user_id, customer_name, phone, address, items,
    subtotal, shipping, total, status, order_mode, order_type,
    delivery_charge, discount_amount, manual_discount_amount,
    manual_discount_type, manual_discount_value, coupon_code,
    coupon_percentage, total_gst, gst_amount, gst_enabled,
    payment_method, payment_mode, split_details, remarks,
    reference_number, billing_date, branch, created_at, updated_at
  )
  VALUES (
    v_invoice_no, v_user_id, COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Customer'),
    COALESCE(p_phone, ''), COALESCE(p_address, ''), p_items,
    v_subtotal, COALESCE(p_shipping, 0), v_total, COALESCE(p_status, 'completed'),
    COALESCE(p_order_mode, 'offline'), COALESCE(p_order_type, 'pos_sale'),
    COALESCE(p_delivery_charge, 0), COALESCE(p_discount_amount, 0),
    COALESCE(p_manual_discount_amount, 0), COALESCE(p_manual_discount_type, 'flat'),
    COALESCE(p_manual_discount_value, 0), p_coupon_code,
    COALESCE(p_coupon_percentage, 0), COALESCE(p_total_gst, 0),
    COALESCE(p_total_gst, 0), COALESCE(p_gst_enabled, FALSE),
    COALESCE(p_payment_method, 'cash'), COALESCE(p_payment_method, 'cash'),
    COALESCE(p_split_details, '{}'::JSONB), COALESCE(p_remarks, ''),
    COALESCE(p_reference_number, ''), p_billing_date, v_branch, v_created_at, NOW()
  )
  RETURNING id INTO v_order_id;

  -- 4. Insert Order Items, Deduct Stock (branch-scoped) & Record SALE Movements
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE((v_item ->> 'unit_price')::NUMERIC, (v_item ->> 'base_price')::NUMERIC, 0);
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');
    v_name_ta := COALESCE(v_item ->> 'product_tamil_name', v_item ->> 'tamil_name', '');
    v_unit := COALESCE(v_item ->> 'unit', 'piece');
    v_unit_type := COALESCE(v_item ->> 'unit_type', 'unit');
    v_base_quantity := COALESCE((v_item ->> 'base_quantity')::NUMERIC, 1);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_discount := COALESCE((v_item ->> 'discount')::NUMERIC, 0);
    v_gst_amount := COALESCE((v_item ->> 'gst_amount')::NUMERIC, 0);
    v_gst_rate := COALESCE((v_item ->> 'gst_rate')::NUMERIC, 0);
    v_image_url := v_item ->> 'image_url';
    v_variant_name := v_item ->> 'variant_name';
    v_source := COALESCE(v_item ->> 'source', 'catalogue');
    v_note := v_item ->> 'note';
    v_category := v_item ->> 'category';

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name,
      product_tamil_name, tamil_name, quantity, unit, unit_type,
      base_quantity, base_price, unit_price, line_total, image_url,
      is_manual, discount, gst_amount, gst_rate, variant_name,
      source, note, category, created_at
    )
    VALUES (
      v_order_id, v_product_id, v_variant_id, v_product_name, v_product_name,
      v_name_ta, v_name_ta, v_quantity, v_unit, v_unit_type,
      v_base_quantity, v_unit_price, v_unit_price, v_line_total, v_image_url,
      v_is_manual, v_discount, v_gst_amount, v_gst_rate, v_variant_name,
      v_source, v_note, v_category, v_created_at
    );

    -- Deduct Stock and Insert SALE Movement (branch-scoped)
    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = v_variant_id AND is_active = TRUE LIMIT 1;

        UPDATE public.product_variants
        SET stock = GREATEST(0, stock - v_quantity), updated_at = NOW()
        WHERE id = v_variant_id AND branch = v_branch;

        -- Parent aggregate update
        UPDATE public.products
        SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE),
            stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE))::INTEGER,
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, v_variant_id, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );

      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = v_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - v_quantity),
            stock = GREATEST(0, stock - FLOOR(v_quantity)::INTEGER),
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, NULL, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );
      END IF;
    END IF;
  END LOOP;

  -- 5. Increment Coupon Usage Count (coupons remain shared across branches)
  IF p_coupon_code IS NOT NULL AND BTRIM(p_coupon_code) <> '' THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1, updated_at = NOW()
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code));
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'invoice_no', v_invoice_no,
    'total', v_total
  );
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- SECTION 27 / 32 â€” 20260930_0027_split_expenses_by_branch.sql
-- ============================================================

-- ====================================================================
-- Migration 0027: Split Expenses Ledger per branch
--
-- expenses never got a `branch` column when POS1/POS2 were split
-- (migration 0020), so an expense logged from either counter showed up
-- in one combined ledger. Adds branch isolation matching every other
-- table (products, orders, inventory, advance orders, barcodes).
--
-- expense_categories stays global/shared (a taxonomy list like
-- "Rent"/"Salaries", not a financial record) -- only the actual
-- expense entries are branch-scoped.
--
-- Existing rows default to 'pos1' (pre-split expenses predate the
-- branch split and belong to the original counter), same convention
-- used when products/orders were split.
-- ====================================================================

BEGIN;

ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';

DO $$
BEGIN
  ALTER TABLE public.expenses ADD CONSTRAINT expenses_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_expenses_branch ON public.expenses(branch, expense_date DESC);

DROP FUNCTION IF EXISTS public.get_expense_summary_metrics(DATE);

CREATE OR REPLACE FUNCTION public.get_expense_summary_metrics(
  p_current_date DATE DEFAULT CURRENT_DATE,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today NUMERIC(12,2) := 0;
  v_this_week NUMERIC(12,2) := 0;
  v_this_month NUMERIC(12,2) := 0;
  v_this_year NUMERIC(12,2) := 0;
  v_total_all_time NUMERIC(12,2) := 0;
  v_week_start DATE := date_trunc('week', p_current_date)::DATE;
  v_month_start DATE := date_trunc('month', p_current_date)::DATE;
  v_year_start DATE := date_trunc('year', p_current_date)::DATE;
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  SELECT
    COALESCE(SUM(CASE WHEN expense_date = p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_week_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_month_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_year_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(amount), 0)
  INTO
    v_today, v_this_week, v_this_month, v_this_year, v_total_all_time
  FROM public.expenses
  WHERE branch = v_branch;

  RETURN jsonb_build_object(
    'today', v_today,
    'this_week', v_this_week,
    'this_month', v_this_month,
    'this_year', v_this_year,
    'total_all_time', v_total_all_time
  );
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- SECTION 28 / 32 â€” 20260930_0029_isolate_coupons_and_expense_categories.sql
-- ============================================================

BEGIN;
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.expense_categories ADD COLUMN IF NOT EXISTS branch TEXT NOT NULL DEFAULT 'pos1';
ALTER TABLE public.expense_categories DROP CONSTRAINT IF EXISTS uq_expense_category_name;
DO $$ BEGIN
  ALTER TABLE public.coupons ADD CONSTRAINT coupons_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_branch_check CHECK (branch IN ('pos1', 'pos2'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DROP INDEX IF EXISTS public.coupons_code_upper_unique;
CREATE UNIQUE INDEX IF NOT EXISTS coupons_branch_code_upper_unique ON public.coupons (branch, UPPER(BTRIM(code)));
CREATE INDEX IF NOT EXISTS coupons_branch_active_idx ON public.coupons(branch, is_active, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS expense_categories_branch_name_unique ON public.expense_categories(branch, LOWER(BTRIM(name)));
CREATE INDEX IF NOT EXISTS expense_categories_branch_active_idx ON public.expense_categories(branch, is_active);
INSERT INTO public.expense_categories (name, is_active, branch)
SELECT seed.name, TRUE, 'pos2'
FROM (VALUES ('Maintenance'), ('Marketing'), ('Other'), ('Rent'), ('Salaries'), ('Supplies')) AS seed(name)
WHERE NOT EXISTS (SELECT 1 FROM public.expense_categories c WHERE c.branch = 'pos2' AND LOWER(BTRIM(c.name)) = LOWER(BTRIM(seed.name)));
DO $$
DECLARE r RECORD; v_definition TEXT; v_updated TEXT;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ILIKE '%UPDATE public.coupons%'
      AND pg_get_functiondef(p.oid) ILIKE '%p_coupon_code%'
      AND pg_get_functiondef(p.oid) ILIKE '%v_branch%'
  LOOP
    v_definition := pg_get_functiondef(r.oid);
    v_updated := replace(v_definition, 'WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code))',
      'WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code)) AND branch = v_branch');
    IF v_updated <> v_definition THEN EXECUTE v_updated; END IF;
  END LOOP;
END $$;

COMMIT;

-- ============================================================
-- SECTION 29 / 32 â€” 20261001_0030_hard_delete_inventory_item.sql
-- ============================================================

BEGIN;

-- 0030: physically remove a product or variant and its inventory audit rows,
-- while preserving historical order-item snapshots.
CREATE OR REPLACE FUNCTION public.delete_inventory_item(
  p_product_id bigint,
  p_variant_id uuid DEFAULT NULL,
  p_branch text DEFAULT 'pos1'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_branch text := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_variant_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_variants WHERE id = p_variant_id AND product_id = p_product_id AND branch = v_branch) THEN
      RAISE EXCEPTION 'Variant does not belong to the selected product and POS branch';
    END IF;
    DELETE FROM public.inventory_movements WHERE variant_id = p_variant_id AND branch = v_branch;
    DELETE FROM public.barcode_registry WHERE variant_id = p_variant_id AND product_id = p_product_id AND branch = v_branch;
    DELETE FROM public.product_variants WHERE id = p_variant_id AND product_id = p_product_id AND branch = v_branch;
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND branch = v_branch) THEN
    RAISE EXCEPTION 'Product does not belong to the selected POS branch';
  END IF;
  DELETE FROM public.inventory_movements WHERE branch = v_branch AND
    (product_id = p_product_id OR variant_id IN (SELECT id FROM public.product_variants WHERE product_id = p_product_id AND branch = v_branch));
  DELETE FROM public.barcode_registry WHERE product_id = p_product_id AND branch = v_branch;
  DELETE FROM public.product_variants WHERE product_id = p_product_id AND branch = v_branch;
  DELETE FROM public.products WHERE id = p_product_id AND branch = v_branch;
END;
$$;
GRANT EXECUTE ON FUNCTION public.delete_inventory_item(bigint, uuid, text) TO anon, authenticated;

COMMIT;

-- ============================================================
-- SECTION 30 / 32 â€” 20261002_0031_cascade_delete_inventory_movements.sql
-- ============================================================

BEGIN;

-- 0031: make inventory movement ledger rows disappear together with the
-- product or variant they belong to. Product / variant ids are unique and each
-- row belongs to exactly one POS branch, so POS 1 and POS 2 ledgers stay fully
-- separate.

-- 1. Clean up orphaned ledger rows left behind by earlier deletions
--    (the old ON DELETE SET NULL foreign keys blanked the links but kept rows).
DELETE FROM public.inventory_movements
WHERE product_id IS NULL
  AND variant_id IS NULL;

-- 2. Delete movements automatically before a variant is removed.
CREATE OR REPLACE FUNCTION public.delete_movements_for_variant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.inventory_movements WHERE variant_id = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS delete_movements_for_variant_trigger ON public.product_variants;
CREATE TRIGGER delete_movements_for_variant_trigger
BEFORE DELETE ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.delete_movements_for_variant();

-- 3. Delete movements automatically before a product is removed.
CREATE OR REPLACE FUNCTION public.delete_movements_for_product()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.inventory_movements WHERE product_id = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS delete_movements_for_product_trigger ON public.products;
CREATE TRIGGER delete_movements_for_product_trigger
BEFORE DELETE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.delete_movements_for_product();

COMMIT;

-- ============================================================
-- SECTION 31 / 32 â€” 20261003_0032_branch_isolation_integrity.sql
-- ============================================================

BEGIN;

-- 0032: POS branch isolation integrity (backend guarantee)
--
-- App-level queries are already branch-filtered, but nothing in the
-- database stopped a client from writing a child row (variant, stock
-- movement, barcode) whose `branch` disagreed with its parent product.
-- Such a row would silently show up in the WRONG POS counter's catalog,
-- stock analytics / stock ledger reports or barcode lookups.
--
-- This section:
--   1. Repairs any existing child row that disagrees with its parent.
--   2. Installs triggers keeping every child row's branch locked to the
--      branch of the product (or of the variant's product) it belongs to.
--
-- Idempotent: safe to re-run.
-- ====================================================================

-- 1. Repair disagreement between child rows and their parent product --------

-- Variants must live in the same branch as their parent product.
UPDATE public.product_variants v
SET branch = p.branch,
    updated_at = NOW()
FROM public.products p
WHERE v.product_id = p.id
  AND v.branch <> p.branch;

-- Barcode registry rows must live in the same branch as their product.
UPDATE public.barcode_registry b
SET branch = p.branch,
    updated_at = NOW()
FROM public.products p
WHERE b.product_id = p.id
  AND b.branch <> p.branch;

-- Stock movements that reference a variant must follow that variant's branch.
UPDATE public.inventory_movements m
SET branch = p.branch
FROM public.product_variants v
JOIN public.products p ON p.id = v.product_id
WHERE m.variant_id = v.id
  AND m.branch <> p.branch;

-- Product-level movements (variant_id IS NULL) follow the product's branch.
UPDATE public.inventory_movements m
SET branch = p.branch
FROM public.products p
WHERE m.product_id = p.id
  AND m.variant_id IS NULL
  AND m.branch <> p.branch;


-- 0032: Guard: a variant always belongs to its parent product's branch.
CREATE OR REPLACE FUNCTION public.enforce_variant_branch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_branch TEXT;
BEGIN
  IF NEW.product_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT branch INTO v_branch FROM public.products WHERE id = NEW.product_id;
  IF v_branch IS NOT NULL THEN
    NEW.branch := CASE WHEN v_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_variant_branch_trigger ON public.product_variants;
CREATE TRIGGER enforce_variant_branch_trigger
BEFORE INSERT OR UPDATE OF branch, product_id ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.enforce_variant_branch();

-- 0032: Guard: barcode registry rows follow their product's branch.
CREATE OR REPLACE FUNCTION public.enforce_barcode_registry_branch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_branch TEXT;
BEGIN
  IF NEW.product_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT branch INTO v_branch FROM public.products WHERE id = NEW.product_id;
  IF v_branch IS NOT NULL THEN
    NEW.branch := CASE WHEN v_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_barcode_registry_branch_trigger ON public.barcode_registry;
CREATE TRIGGER enforce_barcode_registry_branch_trigger
BEFORE INSERT OR UPDATE OF branch, product_id ON public.barcode_registry
FOR EACH ROW EXECUTE FUNCTION public.enforce_barcode_registry_branch();


-- 0032: Guard: stock movement ledger rows follow their product / variant.
-- This is what keeps per-branch stock analytics, stock history and
-- low-stock alarms from ever counting another counter's stock.
CREATE OR REPLACE FUNCTION public.enforce_inventory_movement_branch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_branch TEXT;
BEGIN
  IF NEW.variant_id IS NOT NULL THEN
    SELECT branch INTO v_branch FROM public.product_variants WHERE id = NEW.variant_id;
  END IF;

  IF v_branch IS NULL AND NEW.product_id IS NOT NULL THEN
    SELECT branch INTO v_branch FROM public.products WHERE id = NEW.product_id;
  END IF;

  -- Orphan rows (parent already deleted) keep whatever branch they carry.
  IF v_branch IS NOT NULL THEN
    NEW.branch := CASE WHEN v_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_inventory_movement_branch_trigger ON public.inventory_movements;
CREATE TRIGGER enforce_inventory_movement_branch_trigger
BEFORE INSERT OR UPDATE OF branch, product_id, variant_id ON public.inventory_movements
FOR EACH ROW EXECUTE FUNCTION public.enforce_inventory_movement_branch();

COMMIT;

-- ============================================================
-- SECTION 32 / 32 â€” 20261004_0033_repair_pos1_store_identity.sql
-- ============================================================

-- The POS 1 store_settings row still held the very first seed values
-- ("CLAD" / cladclothing26@gmail.com / Manapparai), which is why every
-- POS 1 invoice printed a CLAD header directly under the YG Enterprises
-- logo. Only rows still sitting on those legacy placeholders are
-- rewritten, so an identity already customised in Admin â†’ Store Settings
-- is never overwritten.

BEGIN;

UPDATE public.store_settings
SET name       = 'YG ENTERPRISES',
    owner_name = 'M. Gurumoorthy',
    phone      = '+91 98844 10700, +91 97878 08090',
    email      = 'ygenterprises2000@gmail.com',
    address    = '#189, N.S.C. Bose Road, (Opp. Bus Depot, Hotel Sankar Cafe Building), Chennai - 600 001',
    updated_at = NOW()
WHERE branch = 'pos1'
  AND (
        LOWER(BTRIM(COALESCE(name,  ''))) = 'clad'
     OR LOWER(BTRIM(COALESCE(email, ''))) = 'cladclothing26@gmail.com'
      );

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 34 / 34 -- 20261005_0034_repair_branch_aware_inventory_rpcs.sql
-- ============================================================

-- ====================================================================
-- Migration 0034: Repair branch-aware inventory/barcode RPCs
--
-- Root cause
-- ----------
-- Migration 0012 was executed AFTER 0020 on this database (the same
-- re-run that previously caused the 42P10 abort on 0013 stopped at
-- 0013, but on an earlier pass 0012 was replayed on top of 0020).
--
-- 0012 uses CREATE OR REPLACE for functions that 0020 had already
-- redefined with an EXTRA TRAILING PARAMETER:
--
--   generate_barcode_value(text)             <- 0012
--   generate_barcode_value(text, text)       <- 0020  (p_branch DEFAULT 'pos1')
--
-- Because the signatures differ, CREATE OR REPLACE does NOT replace the
-- existing function -- Postgres treats it as a NEW overload. Both now
-- coexist, and the default value on 0020's p_branch makes the 1-arg call
-- ambiguous:
--
--   ERROR 42725: function public.generate_barcode_value(text) is not unique
--
-- The same replay silently rolled BACK the branch-awareness that 0020
-- added inside the function BODIES (create_barcode_and_receive_stock,
-- adjust_inventory_stock and complete_pos_sale_with_inventory lost their
-- v_branch handling and their p_branch parameter), because those bodies
-- are replaced in place under the SAME signature.
--
-- Effect: "Generate & Print" fails for every SKU, and POS checkout /
-- stock receipts lose per-branch isolation.
--
-- Fix
-- ---
-- 1. Drop the stale 1-argument overload created by 0012.
-- 2. Re-assert the canonical branch-aware definitions, taken verbatim
--    from 0020 (barcode + stock RPCs) and 0026 (POS sale, which is the
--    0020 function plus the NULL-remarks COALESCE fix).
--
-- Idempotent: safe to re-run.
-- ====================================================================

BEGIN;

-- 1. Remove the ambiguous 1-argument overload left behind by 0012.
DROP FUNCTION IF EXISTS public.generate_barcode_value(TEXT);

-- 2. Re-assert canonical branch-aware definitions.

-- generate_barcode_value: branch-aware (from 0020)
CREATE OR REPLACE FUNCTION public.generate_barcode_value(p_entity_type TEXT, p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_branch = 'pos2' THEN
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
$$;

CREATE OR REPLACE FUNCTION public.create_barcode_and_receive_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_quantity_received NUMERIC DEFAULT 0,
  p_unit_cost NUMERIC DEFAULT NULL,
  p_created_by_name TEXT DEFAULT '',
  p_custom_barcode TEXT DEFAULT NULL,
  p_note TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entity_type TEXT;
  v_barcode_id UUID;
  v_barcode_value TEXT;
  v_is_new_barcode BOOLEAN := FALSE;
  v_movement_type TEXT;
  v_qty_before NUMERIC := 0;
  v_qty_after NUMERIC := 0;
  v_prod_name TEXT;
  v_var_name TEXT := '';
  v_branch TEXT;
BEGIN
  IF p_quantity_received < 0 THEN
    RAISE EXCEPTION 'Quantity received cannot be negative';
  END IF;

  -- 1. Check Parent Product Exists (and capture its branch)
  SELECT name, branch INTO v_prod_name, v_branch FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product with ID % not found', p_product_id;
  END IF;

  -- 2. Verify Variant Belongs to Product if Variant is Provided
  IF p_variant_id IS NOT NULL THEN
    v_entity_type := 'variant';
    SELECT variant_name, stock INTO v_var_name, v_qty_before
    FROM public.product_variants
    WHERE id = p_variant_id AND product_id = p_product_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Variant % does not belong to Product %', p_variant_id, p_product_id;
    END IF;
  ELSE
    v_entity_type := 'product';
    SELECT stock_quantity INTO v_qty_before
    FROM public.products
    WHERE id = p_product_id;
  END IF;

  -- 3. Check for Existing Active Barcode in barcode_registry (SKU Identity)
  IF v_entity_type = 'variant' THEN
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE variant_id = p_variant_id AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  ELSE
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  -- 4. Reuse Existing or Create New Barcode
  IF v_barcode_id IS NOT NULL THEN
    v_is_new_barcode := FALSE;
    v_movement_type := CASE WHEN v_qty_before = 0 THEN 'INITIAL_BARCODE_STOCK' ELSE 'RESTOCK' END;
  ELSE
    v_is_new_barcode := TRUE;
    v_movement_type := 'INITIAL_BARCODE_STOCK';
    v_barcode_value := COALESCE(NULLIF(UPPER(BTRIM(p_custom_barcode)), ''), public.generate_barcode_value(v_entity_type, v_branch));

    INSERT INTO public.barcode_registry (
      barcode_value, entity_type, product_id, variant_id, is_active, created_by_name, branch
    )
    VALUES (
      v_barcode_value, v_entity_type, p_product_id, p_variant_id, TRUE, COALESCE(p_created_by_name, ''), v_branch
    )
    RETURNING id INTO v_barcode_id;
  END IF;

  -- 5. Synchronize compatibility column on target table
  IF v_entity_type = 'variant' THEN
    UPDATE public.product_variants
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_variant_id;
  ELSE
    UPDATE public.products
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- 6. Apply Stock Increment & Parent Aggregate Sync
  v_qty_after := v_qty_before + p_quantity_received;

  IF p_quantity_received > 0 THEN
    IF v_entity_type = 'variant' THEN
      UPDATE public.product_variants
      SET stock = v_qty_after, updated_at = NOW()
      WHERE id = p_variant_id;

      -- Refresh parent aggregate stock cache
      UPDATE public.products
      SET stock_quantity = (
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ),
          stock = FLOOR((
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ))::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    ELSE
      UPDATE public.products
      SET stock_quantity = v_qty_after,
          stock = FLOOR(v_qty_after)::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    END IF;
  END IF;

  -- 7. Record Immutable Inventory Movement
  IF p_quantity_received > 0 THEN
    INSERT INTO public.inventory_movements (
      product_id, variant_id, barcode_id, movement_type,
      quantity_delta, quantity_before, quantity_after,
      unit_cost, reference_type, reference_id, note, created_by_name, branch
    )
    VALUES (
      p_product_id, p_variant_id, v_barcode_id, v_movement_type,
      p_quantity_received, v_qty_before, v_qty_after,
      p_unit_cost, 'barcode_receipt', v_barcode_value,
      COALESCE(p_note, ''), COALESCE(p_created_by_name, ''), v_branch
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'barcode_id', v_barcode_id,
    'barcode_value', v_barcode_value,
    'is_new_barcode', v_is_new_barcode,
    'movement_type', v_movement_type,
    'quantity_before', v_qty_before,
    'quantity_received', p_quantity_received,
    'quantity_after', v_qty_after,
    'product_id', p_product_id,
    'variant_id', p_variant_id,
    'product_name', v_prod_name,
    'variant_name', v_var_name
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_inventory_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_new_quantity NUMERIC DEFAULT 0,
  p_reason TEXT DEFAULT 'RESTOCK',
  p_note TEXT DEFAULT '',
  p_created_by_name TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qty_before NUMERIC := 0;
  v_delta NUMERIC := 0;
  v_barcode_id UUID;
  v_branch TEXT;
BEGIN
  IF p_new_quantity < 0 THEN
    RAISE EXCEPTION 'Stock quantity cannot be negative';
  END IF;

  -- Verify variant if supplied
  IF p_variant_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_variants WHERE id = p_variant_id AND product_id = p_product_id) THEN
      RAISE EXCEPTION 'Variant does not belong to specified Product';
    END IF;

    SELECT stock, branch INTO v_qty_before, v_branch FROM public.product_variants WHERE id = p_variant_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = p_variant_id AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.product_variants
    SET stock = p_new_quantity, updated_at = NOW()
    WHERE id = p_variant_id;

    -- Refresh parent aggregate
    UPDATE public.products
    SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE),
        stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE))::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  ELSE
    SELECT stock_quantity, branch INTO v_qty_before, v_branch FROM public.products WHERE id = p_product_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.products
    SET stock_quantity = p_new_quantity,
        stock = FLOOR(p_new_quantity)::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- Record Movement
  INSERT INTO public.inventory_movements (
    product_id, variant_id, barcode_id, movement_type,
    quantity_delta, quantity_before, quantity_after,
    reference_type, note, created_by_name, branch
  )
  VALUES (
    p_product_id, p_variant_id, v_barcode_id, p_reason,
    v_delta, v_qty_before, p_new_quantity,
    'adjustment', COALESCE(p_note, ''), COALESCE(p_created_by_name, ''), v_branch
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'quantity_before', v_qty_before,
    'quantity_after', p_new_quantity,
    'delta', v_delta,
    'reason', p_reason
  );
END;
$$;

-- complete_pos_sale_with_inventory: branch-aware + NULL-safe (from 0026)
CREATE OR REPLACE FUNCTION public.complete_pos_sale_with_inventory(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'completed',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_remarks TEXT DEFAULT NULL,
  p_reference_number TEXT DEFAULT NULL,
  p_billing_date TIMESTAMPTZ DEFAULT NULL,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC := 0;
  v_total NUMERIC := 0;
  v_item JSONB;
  v_product_id BIGINT;
  v_variant_id UUID;
  v_quantity NUMERIC;
  v_unit_price NUMERIC;
  v_line_total NUMERIC;
  v_product_name TEXT;
  v_name_ta TEXT;
  v_unit TEXT;
  v_unit_type TEXT;
  v_base_quantity NUMERIC;
  v_is_manual BOOLEAN;
  v_discount NUMERIC;
  v_gst_amount NUMERIC;
  v_gst_rate NUMERIC;
  v_image_url TEXT;
  v_variant_name TEXT;
  v_source TEXT;
  v_note TEXT;
  v_category TEXT;
  v_current_stock NUMERIC;
  v_barcode_id UUID;
  v_created_at TIMESTAMPTZ := COALESCE(p_billing_date, NOW());
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order items cannot be empty';
  END IF;

  -- 1. Atomic Pre-Validation of Available Stock for All Items (branch-scoped)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');

    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 2. Calculate Subtotal & Generate Invoice Number (from this branch's sequence)
  v_invoice_no := public.get_next_invoice_no(v_branch);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE(
      (v_item ->> 'unit_price')::NUMERIC,
      (v_item ->> 'base_price')::NUMERIC,
      (v_item ->> 'price')::NUMERIC,
      0
    );
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(0, ROUND(v_subtotal + COALESCE(p_shipping, 0) + COALESCE(p_delivery_charge, 0) - COALESCE(p_discount_amount, 0), 2));

  -- 3. Insert Order Record
  INSERT INTO public.orders (
    invoice_no, user_id, customer_name, phone, address, items,
    subtotal, shipping, total, status, order_mode, order_type,
    delivery_charge, discount_amount, manual_discount_amount,
    manual_discount_type, manual_discount_value, coupon_code,
    coupon_percentage, total_gst, gst_amount, gst_enabled,
    payment_method, payment_mode, split_details, remarks,
    reference_number, billing_date, branch, created_at, updated_at
  )
  VALUES (
    v_invoice_no, v_user_id, COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Customer'),
    COALESCE(p_phone, ''), COALESCE(p_address, ''), p_items,
    v_subtotal, COALESCE(p_shipping, 0), v_total, COALESCE(p_status, 'completed'),
    COALESCE(p_order_mode, 'offline'), COALESCE(p_order_type, 'pos_sale'),
    COALESCE(p_delivery_charge, 0), COALESCE(p_discount_amount, 0),
    COALESCE(p_manual_discount_amount, 0), COALESCE(p_manual_discount_type, 'flat'),
    COALESCE(p_manual_discount_value, 0), p_coupon_code,
    COALESCE(p_coupon_percentage, 0), COALESCE(p_total_gst, 0),
    COALESCE(p_total_gst, 0), COALESCE(p_gst_enabled, FALSE),
    COALESCE(p_payment_method, 'cash'), COALESCE(p_payment_method, 'cash'),
    COALESCE(p_split_details, '{}'::JSONB), COALESCE(p_remarks, ''),
    COALESCE(p_reference_number, ''), p_billing_date, v_branch, v_created_at, NOW()
  )
  RETURNING id INTO v_order_id;

  -- 4. Insert Order Items, Deduct Stock (branch-scoped) & Record SALE Movements
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE((v_item ->> 'unit_price')::NUMERIC, (v_item ->> 'base_price')::NUMERIC, 0);
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');
    v_name_ta := COALESCE(v_item ->> 'product_tamil_name', v_item ->> 'tamil_name', '');
    v_unit := COALESCE(v_item ->> 'unit', 'piece');
    v_unit_type := COALESCE(v_item ->> 'unit_type', 'unit');
    v_base_quantity := COALESCE((v_item ->> 'base_quantity')::NUMERIC, 1);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_discount := COALESCE((v_item ->> 'discount')::NUMERIC, 0);
    v_gst_amount := COALESCE((v_item ->> 'gst_amount')::NUMERIC, 0);
    v_gst_rate := COALESCE((v_item ->> 'gst_rate')::NUMERIC, 0);
    v_image_url := v_item ->> 'image_url';
    v_variant_name := v_item ->> 'variant_name';
    v_source := COALESCE(v_item ->> 'source', 'catalogue');
    v_note := v_item ->> 'note';
    v_category := v_item ->> 'category';

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name,
      product_tamil_name, tamil_name, quantity, unit, unit_type,
      base_quantity, base_price, unit_price, line_total, image_url,
      is_manual, discount, gst_amount, gst_rate, variant_name,
      source, note, category, created_at
    )
    VALUES (
      v_order_id, v_product_id, v_variant_id, v_product_name, v_product_name,
      v_name_ta, v_name_ta, v_quantity, v_unit, v_unit_type,
      v_base_quantity, v_unit_price, v_unit_price, v_line_total, v_image_url,
      v_is_manual, v_discount, v_gst_amount, v_gst_rate, v_variant_name,
      v_source, v_note, v_category, v_created_at
    );

    -- Deduct Stock and Insert SALE Movement (branch-scoped)
    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = v_variant_id AND is_active = TRUE LIMIT 1;

        UPDATE public.product_variants
        SET stock = GREATEST(0, stock - v_quantity), updated_at = NOW()
        WHERE id = v_variant_id AND branch = v_branch;

        -- Parent aggregate update
        UPDATE public.products
        SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE),
            stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE))::INTEGER,
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, v_variant_id, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );

      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = v_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - v_quantity),
            stock = GREATEST(0, stock - FLOOR(v_quantity)::INTEGER),
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, NULL, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );
      END IF;
    END IF;
  END LOOP;

  -- 5. Increment Coupon Usage Count (coupons remain shared across branches)
  IF p_coupon_code IS NOT NULL AND BTRIM(p_coupon_code) <> '' THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1, updated_at = NOW()
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code));
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'invoice_no', v_invoice_no,
    'total', v_total
  );
END;
$$;


COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 35 / 35 â€” 20261007_0037_force_yg_store_identity.sql
-- ============================================================

-- Migration 0033 repaired only rows still matching the exact 0012 CLAD seed.
-- Rows on any other legacy identity (Purple Boutique / Chaji Mens Wear) or
-- partially edited CLAD rows survived it, so "View Invoice" on both counters
-- kept printing CLAD / Chaji details under the YG Enterprises logo. This
-- rewrites the identity columns of every store_settings row sitting on ANY
-- known legacy placeholder. Theme, logo, business type and Instagram handle
-- are left untouched, and a genuinely customised profile matches no marker.

BEGIN;

UPDATE public.store_settings
SET name       = 'YG ENTERPRISES',
    owner_name = 'M. Gurumoorthy',
    phone      = '+91 98844 10700, +91 97878 08090',
    email      = 'ygenterprises2000@gmail.com',
    address    = '#189, N.S.C. Bose Road, (Opp. Bus Depot, Hotel Sankar Cafe Building), Chennai - 600 001',
    updated_at = NOW()
-- 'yg enterprises' is deliberately NOT matched: it is the current brand name, so
-- matching on it would let a re-run reset a phone/address the owner has already
-- customised. Only unambiguous legacy markers are matched.
WHERE LOWER(BTRIM(COALESCE(name,       ''))) IN ('clad', 'chaji', 'chaji mens wear', 'purple boutique')
   OR LOWER(BTRIM(COALESCE(owner_name, ''))) IN ('clad', 'rubi krishna', 'chandru ajitha')
   OR LOWER(BTRIM(COALESCE(email,      ''))) IN (
        'cladclothing26@gmail.com',
        'chandrums1552004@gmail.com',
        'mypurpleboutique05@gmail.com'
      )
   OR COALESCE(phone, '') LIKE '%7010312145%'
   OR COALESCE(phone, '') LIKE '%8925094465%'
   OR COALESCE(phone, '') LIKE '%9344159498%'
   OR COALESCE(phone, '') LIKE '%11-3312 7107%'
   OR LOWER(COALESCE(address, '')) LIKE '%manapparai%'
   OR LOWER(COALESCE(address, '')) LIKE '%tamarind suite%'
   OR LOWER(COALESCE(address, '')) LIKE '%cyberjaya%';

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- SECTION 36 / 36 -- 20261008_0038_advance_order_branch_isolation.sql
-- ============================================================

-- ===================================================================
-- Migration 0038: Keep completed advance-order bills on their own POS
-- ===================================================================
--
-- SYMPTOM
-- Completing an advance order on POS 2 (Fireworks) makes the finished
-- bill appear in POS 1's (Jute Management) Order Management list.
--
-- ROOT CAUSE
-- complete_advance_order_v2() has been redefined three times, and the
-- pre-branch version from 0018 is still the one live on this database:
--
--   0007 / 0018 -> INSERT INTO public.orders (... payment_method)
--                     -- no `branch` column at all
--   0020         -> INSERT INTO public.orders (..., branch, ...)
--                     v_branch := CASE WHEN v_advance.branch = 'pos2'
--                                       THEN 'pos2' ELSE 'pos1' END
--
-- The 0018 body omits `branch`, so the INSERT falls back to the column
-- DEFAULT 'pos1' declared by 0020. Every completed advance order is
-- therefore booked into POS 1's ledger no matter which counter it was
-- raised on.
--
-- The 0018 body is also doubly wrong for POS 2: it pulls the invoice
-- number from the retired shared invoice_number_seq rather than from
-- get_next_invoice_no(v_branch), so the two counters' numbering no
-- longer stay in their own 8-digit ranges.
--
-- WHAT
-- 1. Re-deploy the branch-aware 0020 body, so `orders.branch` is copied
--    from the advance order's own branch and the invoice number comes
--    from that counter's sequence.
-- 2. Backfill any bill already mis-filed into the wrong counter, using
--    advance_orders.completed_order_id as the authoritative link.
-- 3. Backfill a branch on any advance order left without one.
--
-- SAFE / IDEMPOTENT: re-running re-deploys the same function and the
-- backfill matches nothing once the rows are correct.
-- ===================================================================

BEGIN;

-- 1. Re-deploy the branch-aware completion RPC ------------------------

DROP FUNCTION IF EXISTS public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text);

CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;
  v_branch         text;
BEGIN
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;

  -- The advance order's own branch is the single source of truth. It is
  -- deliberately NOT taken from the client: a caller in the wrong branch
  -- context can then no longer cross-book the completed bill.
  v_branch := CASE WHEN v_advance.branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;

  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;

  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    IF v_advance.status != 'completed' THEN
      UPDATE public.advance_orders
      SET status = 'completed',
          updated_at = v_now
      WHERE id = p_order_id;
    END IF;

    RETURN QUERY SELECT
      coalesce(v_advance.completed_order_id, gen_random_uuid()),
      coalesce(v_advance.invoice_number, 'INV00000000'),
      coalesce(v_advance.completed_at, v_now);
    RETURN;
  END IF;

  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  -- Invoice number from THIS counter's sequence, so the two POS stay in
  -- their own disjoint 8-digit ranges.
  v_invoice := public.get_next_invoice_no(v_branch);

  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;

  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, branch, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_items, v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method), v_branch,
    v_now, v_now
  );

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    INSERT INTO public.order_items (
      order_id, product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id,
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      greatest(coalesce((v_item->>'quantity')::numeric, 1), 0),
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );
  END LOOP;

  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text) TO public, anon, authenticated;

-- 2. Backfill bills already filed under the wrong counter --------------
-- advance_orders.completed_order_id points at the orders row the RPC
-- created, so it is the reliable join key. Only order_type =
-- 'advance_order' is touched, so ordinary POS sales are never moved.

UPDATE public.orders o
SET branch = a.branch,
    updated_at = NOW()
FROM public.advance_orders a
WHERE a.completed_order_id = o.id
  AND o.order_type = 'advance_order'
  AND a.branch IS DISTINCT FROM o.branch;

-- 3. Backfill a branch on any advance order left without one ----------
-- The column has been NOT NULL DEFAULT 'pos1' since 0020, so this can
-- only affect rows added before the column existed.

UPDATE public.advance_orders
SET branch = 'pos1', updated_at = NOW()
WHERE branch IS NULL OR branch NOT IN ('pos1', 'pos2');

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 37 / 37 -- 20261006_0036_seed_ledger.sql
-- ============================================================

-- ====================================================================
-- Migration 0036: Seed ledger so catalog seeds stop resurrecting deletes
-- ====================================================================
-- Problem
-- -------
-- The catalog seed migrations (0002, 0022, 0024) guarded their inserts
-- with `WHERE NOT EXISTS (SELECT 1 FROM products WHERE <same name>)`.
-- That guard is name-based, not run-based: once an operator DELETES a
-- seeded product, the row is gone, the NOT EXISTS check passes again,
-- and the next re-run of those files silently RE-CREATED the deleted
-- product at its placeholder price/stock. Deleting a catalog item was
-- therefore not durable.
--
-- Fix
-- ---
-- Introduce public.seed_ledger, a tiny run-once marker table. Each
-- catalog seed now checks the ledger and returns early when its key is
-- already recorded, so a re-run is a no-op no matter what the operator
-- has since deleted. The per-row NOT EXISTS guards are kept as a
-- belt-and-braces duplicate check for genuinely fresh databases.
--
-- This migration also BACKFILLS the ledger so that re-running the old
-- seed files against an already-seeded database cannot resurrect the
-- test catalog that was just cleared.
-- ====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.seed_ledger (
  seed_key      TEXT PRIMARY KEY,
  applied_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.seed_ledger IS
  'Run-once markers for catalog seed migrations. Prevents re-running a seed from recreating products an operator has deleted.';

-- Backfill: mark the three catalog seeds as already applied so replaying
-- 0002 / 0022 / 0024 on this database can no longer recreate seeded rows.
INSERT INTO public.seed_ledger (seed_key) VALUES
  ('20260716_0002_purple_boutique_catalog'),
  ('20260925_0022_seed_branch_starter_catalog'),
  ('20260927_0024_pos2_fireworks_catalog')
ON CONFLICT (seed_key) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 38 / 38 -- 20261009_0039_branch_scoped_coupons_barcodes_categories.sql
-- ============================================================

-- ===================================================================
-- Migration 0039: Finish POS 1 / POS 2 isolation for coupons,
--                 barcodes and categories
-- ===================================================================
--
-- 1. COUPON USAGE WAS CHARGED TO BOTH COUNTERS
--    0029 lets each POS own a coupon with the same code, and patched the
--    checkout RPCs to bump usage only on the selling counter's coupon
--    (`... AND branch = v_branch`). 0034 then re-created
--    complete_pos_sale_with_inventory from an older body that lacks that
--    clause, so a POS 1 sale with code DIWALI10 also counts against (and
--    can exhaust the usage limit of) POS 2's DIWALI10.
--    Fix: re-apply the branch clause to every installed checkout routine
--    that has a v_branch, whatever body is live, then assert it stuck.
--
-- 2. BARCODES WERE UNIQUE ACROSS BOTH COUNTERS
--    barcode_registry.barcode_value is UNIQUE on its own, so:
--      - the same manufacturer barcode cannot be registered in both POS;
--      - the product editor's upsert (ON CONFLICT barcode_value) re-points
--        the OTHER counter's registry row at this counter's product.
--    Fix: uniqueness becomes (branch, barcode_value). The app's upsert is
--    switched to that key in the same change.
--
-- 3. CATEGORY NAMES WERE UNIQUE ACROSS BOTH COUNTERS
--    categories.name_en is UNIQUE on its own (from 0001), so once one POS
--    has a category, the other POS cannot create one with the same name --
--    including the automatic 'Unregistered' category used for ad-hoc
--    items, which made unregistered billing fail on the second counter.
--    Fix: uniqueness becomes (branch, lower(trim(name_en))), matching the
--    per-branch rule already used for coupons and expense categories.
--
-- Deploy order: apply this migration BEFORE deploying the app build that
-- upserts barcodes on (branch, barcode_value).
--
-- SAFE / IDEMPOTENT: every step is guarded and re-running is a no-op.
-- ===================================================================

BEGIN;

-- 1. Coupon usage stays on the selling counter's coupon ------------------

DO $$
DECLARE
  r RECORD;
  v_def TEXT;
  v_new TEXT;
  c_unscoped CONSTANT TEXT :=
    'WHERE UPPER\(BTRIM\(code\)\) = UPPER\(BTRIM\(p_coupon_code\)\)(?! AND branch = v_branch)';
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.prosrc ILIKE '%UPDATE public.coupons%'
      AND p.prosrc ILIKE '%v_branch%'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := regexp_replace(v_def, c_unscoped, '\& AND branch = v_branch', 'g');
    IF v_new <> v_def THEN
      EXECUTE v_new;
    END IF;
  END LOOP;

  -- Fail loudly rather than leave a counter-crossing checkout installed.
  FOR r IN
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.prosrc ILIKE '%UPDATE public.coupons%'
      AND p.prosrc ILIKE '%v_branch%'
      AND p.prosrc ~ c_unscoped
  LOOP
    RAISE EXCEPTION 'Coupon usage in %() is still shared between POS 1 and POS 2', r.proname;
  END LOOP;

  IF to_regprocedure('public.complete_pos_sale_with_inventory(text,text,text,jsonb,numeric,text,text,text,numeric,numeric,numeric,text,numeric,text,numeric,text,jsonb,numeric,boolean,text,text,timestamptz,text)') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_proc
       WHERE oid = 'public.complete_pos_sale_with_inventory(text,text,text,jsonb,numeric,text,text,text,numeric,numeric,numeric,text,numeric,text,numeric,text,jsonb,numeric,boolean,text,text,timestamptz,text)'::regprocedure
         AND prosrc ILIKE '%p_coupon_code)) AND branch = v_branch%'
     ) THEN
    RAISE EXCEPTION 'complete_pos_sale_with_inventory() does not scope coupon usage to its POS branch';
  END IF;
END $$;

-- 2 & 3. Per-branch uniqueness for barcodes and category names ------------
-- New per-branch indexes are created first, so uniqueness is never absent.

CREATE UNIQUE INDEX IF NOT EXISTS barcode_registry_branch_value_unique
  ON public.barcode_registry (branch, barcode_value);

CREATE UNIQUE INDEX IF NOT EXISTS categories_branch_name_unique
  ON public.categories (branch, LOWER(BTRIM(name_en)));

-- Drop the old single-column unique constraint / index on
-- barcode_registry(barcode_value) and categories(name_en), whatever it is
-- named on this database.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT i.indexrelid::regclass AS index_name,
           i.indrelid::regclass  AS table_name,
           c.conname
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
    LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid AND c.contype = 'u'
    WHERE i.indisunique
      AND NOT i.indisprimary
      AND i.indnatts = 1
      AND i.indexprs IS NULL
      AND (
        (i.indrelid = 'public.barcode_registry'::regclass AND a.attname = 'barcode_value')
        OR (i.indrelid = 'public.categories'::regclass AND a.attname = 'name_en')
      )
  LOOP
    IF r.conname IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.table_name, r.conname);
    ELSE
      EXECUTE format('DROP INDEX %s', r.index_name);
    END IF;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 39 / 39 -- 20261010_0040_advance_order_completion_deducts_stock.sql
-- ============================================================

-- ===================================================================
-- Migration 0040: Completing an advance order deducts its stock
-- ===================================================================
--
-- SYMPTOM
-- Completing an advance (deposit) order creates the "advance order
-- completed" bill in Order Management, but the products on it never
-- leave inventory: complete_advance_order_v2() inserts the bill and its
-- line items and touches no stock at all.
--
-- WHAT
-- complete_advance_order_v2() now, in the same transaction that creates
-- the bill:
--   1. Locks and checks stock for every catalog item on the order and
--      refuses to complete if the counter does not have enough.
--   2. Deducts it, refreshes the parent product's total for variants,
--      and records a SALE row in the stock ledger against the invoice.
--   3. Links each bill line to its product / variant.
--
-- POS ISOLATION
-- The branch comes from the advance order itself, never the client, and
-- every stock lookup, update and ledger row is filtered to that branch.
-- An item whose product is not in that counter's catalog (deleted since
-- the deposit, or typed in by hand) is billed but moves no stock, so a
-- POS 2 completion can never touch POS 1 inventory or vice versa.
--
-- Not stock-tracked: hand-typed items (no product id), items flagged
-- is_manual, and products in the 'Unregistered' category -- the same
-- rule POS checkout uses.
--
-- Stock is deducted exactly once: a second completion call returns the
-- existing invoice before reaching any stock code (unchanged guard).
--
-- SAFE / IDEMPOTENT: re-running re-deploys the same function.
-- ===================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_bill_items     jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;
  v_branch         text;
  v_raw_product    text;
  v_raw_variant    text;
  v_product_id     bigint;
  v_variant_id     uuid;
  v_quantity       numeric;
  v_name           text;
  v_stock          numeric;
  v_barcode_id     uuid;
  v_tracked        boolean;
BEGIN
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;

  -- The advance order's own branch is the single source of truth.
  v_branch := CASE WHEN v_advance.branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;

  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;

  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    IF v_advance.status != 'completed' THEN
      UPDATE public.advance_orders
      SET status = 'completed',
          updated_at = v_now
      WHERE id = p_order_id;
    END IF;

    RETURN QUERY SELECT
      coalesce(v_advance.completed_order_id, gen_random_uuid()),
      coalesce(v_advance.invoice_number, 'INV00000000'),
      coalesce(v_advance.completed_at, v_now);
    RETURN;
  END IF;

  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;
  v_bill_items := v_items;

  -- 1. Resolve each item against THIS counter's catalog, lock its stock
  --    row and make sure there is enough. Resolved ids are written back
  --    into v_items so the later steps never look outside the branch.
  FOR i IN 0 .. jsonb_array_length(v_items) - 1 LOOP
    v_item := v_items -> i;
    v_raw_product := btrim(coalesce(v_item ->> 'product_id', ''));
    v_raw_variant := btrim(coalesce(v_item ->> 'variant_id', ''));
    v_product_id := CASE WHEN v_raw_product ~ '^[0-9]+$' THEN v_raw_product::bigint END;
    v_variant_id := CASE
      WHEN v_raw_variant ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN v_raw_variant::uuid
    END;
    v_quantity := greatest(coalesce(nullif(v_item ->> 'quantity', '')::numeric, 1), 0);
    v_name := coalesce(nullif(btrim(v_item ->> 'name'), ''), 'Product');
    v_tracked := FALSE;
    v_stock := NULL;

    IF v_variant_id IS NOT NULL THEN
      SELECT pv.stock, pv.product_id INTO v_stock, v_product_id
      FROM public.product_variants pv
      WHERE pv.id = v_variant_id AND pv.branch = v_branch
      FOR UPDATE;
      IF NOT FOUND THEN
        v_variant_id := NULL;
        v_product_id := NULL;
      END IF;
    END IF;

    IF v_product_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = v_product_id AND p.branch = v_branch
    ) THEN
      v_product_id := NULL;
      v_variant_id := NULL;
    END IF;

    IF v_product_id IS NOT NULL
       AND NOT coalesce((v_item ->> 'is_manual')::boolean, FALSE)
       AND NOT EXISTS (
         SELECT 1 FROM public.products p
         WHERE p.id = v_product_id AND lower(btrim(coalesce(p.category, ''))) = 'unregistered'
       )
       AND v_quantity > 0 THEN
      v_tracked := TRUE;
      IF v_variant_id IS NULL THEN
        SELECT p.stock_quantity INTO v_stock
        FROM public.products p
        WHERE p.id = v_product_id AND p.branch = v_branch
        FOR UPDATE;
      END IF;

      IF coalesce(v_stock, 0) < v_quantity THEN
        RAISE EXCEPTION 'Not enough stock to complete this order: % (in stock: %, needed: %). Restock it in Inventory, then complete the order.',
          v_name, coalesce(v_stock, 0), v_quantity;
      END IF;
    END IF;

    v_items := jsonb_set(
      v_items, ARRAY[i::text],
      v_item || jsonb_build_object(
        '_product_id', v_product_id,
        '_variant_id', v_variant_id,
        '_tracked',    v_tracked
      )
    );
  END LOOP;

  -- 2. Bill, numbered from this counter's sequence.
  v_invoice := public.get_next_invoice_no(v_branch);

  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, branch, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_bill_items,
    v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method), v_branch,
    v_now, v_now
  );

  -- 3. Bill lines, stock deduction and stock ledger (all branch-scoped).
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    v_product_id := nullif(v_item ->> '_product_id', '')::bigint;
    v_variant_id := nullif(v_item ->> '_variant_id', '')::uuid;
    v_quantity := greatest(coalesce(nullif(v_item ->> 'quantity', '')::numeric, 1), 0);

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, variant_name, category,
      product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id, v_product_id, v_variant_id, nullif(v_item ->> 'variant_name', ''),
      nullif(v_item ->> 'category', ''),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      v_quantity,
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );

    CONTINUE WHEN NOT coalesce((v_item ->> '_tracked')::boolean, FALSE);

    IF v_variant_id IS NOT NULL THEN
      SELECT stock INTO v_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch;
      SELECT id INTO v_barcode_id FROM public.barcode_registry
      WHERE variant_id = v_variant_id AND branch = v_branch AND is_active = TRUE LIMIT 1;

      UPDATE public.product_variants
      SET stock = greatest(0, stock - v_quantity), updated_at = v_now
      WHERE id = v_variant_id AND branch = v_branch;

      UPDATE public.products
      SET stock_quantity = (SELECT coalesce(sum(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND branch = v_branch AND is_active = TRUE),
          stock = floor((SELECT coalesce(sum(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND branch = v_branch AND is_active = TRUE))::integer,
          updated_at = v_now
      WHERE id = v_product_id AND branch = v_branch;
    ELSE
      SELECT stock_quantity INTO v_stock FROM public.products WHERE id = v_product_id AND branch = v_branch;
      SELECT id INTO v_barcode_id FROM public.barcode_registry
      WHERE product_id = v_product_id AND variant_id IS NULL AND branch = v_branch AND is_active = TRUE LIMIT 1;

      UPDATE public.products
      SET stock_quantity = greatest(0, stock_quantity - v_quantity),
          stock = greatest(0, floor(stock_quantity - v_quantity))::integer,
          updated_at = v_now
      WHERE id = v_product_id AND branch = v_branch;
    END IF;

    INSERT INTO public.inventory_movements (
      product_id, variant_id, barcode_id, movement_type,
      quantity_delta, quantity_before, quantity_after,
      reference_type, reference_id, note, branch
    ) VALUES (
      v_product_id, v_variant_id, v_barcode_id, 'SALE',
      -v_quantity, v_stock, greatest(0, v_stock - v_quantity),
      'order', v_invoice, 'Advance order completed (' || v_advance.deposit_id || ')', v_branch
    );
  END LOOP;

  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text) TO public, anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 40 / 40 -- 20261011_0041_remove_jewellery_schema_restore_yg.sql
-- ============================================================

-- ===================================================================
-- Migration 0041: Undo the two Jewellery POS scripts, restore YG
-- ===================================================================
--
-- WHAT HAPPENED
-- Two scripts from the separate Jewellery POS project were run on the YG
-- Enterprises database:
--   A. "Jewellery POS extension"            (jewellery/supabase/migrations/jewellery_pos.sql)
--   B. "Jewellery POS - Complete Deployment" (jewellery/supabase/production_schema.sql)
--
-- They added jewellery tables, columns, categories, sequences and
-- functions; put an extra stock-deducting trigger on orders (which would
-- have double-deducted every YG sale); replaced YG's checkout,
-- advance-order, barcode, stock, expense, invoice-lookup and helper
-- functions with non-POS-aware versions; and re-added three uniqueness
-- rules that make POS 1 and POS 2 clash on coupon codes, barcodes and
-- category names.
--
-- WHAT THIS DOES -- every object is named explicitly, taken from those two
-- scripts; nothing else in the database is touched:
--   1. Deletes the 21 categories the scripts seeded into POS 1.
--   2. Drops the extra trigger they put on orders.
--   3. Drops the 3 cross-POS uniqueness rules they re-added, 2 other
--      indexes, and their 4 file-storage access rules (if present).
--   4. Drops the columns they added to YG tables (all hold only defaults).
--   5. Drops the tables, view, functions and sequences they created
--      (tables verified empty).
--   6. Restores YG's functions and triggers they replaced, verbatim from
--      YG's latest migrations (with 0039's per-POS coupon fix).
--   7. Verifies the result; any failure rolls the whole migration back.
--
-- Not touched: access policies and row-level security on YG tables (the
-- scripts re-created them with exactly YG's definitions), storage buckets,
-- and two columns the YG app itself relies on (orders.invoice_pdf_url,
-- advance_orders.reference_number), which script B may also have added.
-- ===================================================================

BEGIN;

-- 1. Categories seeded by the scripts (none has products) -----------------

DELETE FROM public.categories c
WHERE c.branch = 'pos1'
  AND (
    c.name_en IN (
      'Gold Jewellery', 'Silver Jewellery', 'Platinum Jewellery', 'Diamond Jewellery',
      'Rings', 'Necklaces', 'Chains', 'Bangles', 'Bracelets', 'Earrings', 'Pendants',
      'Nose Pins', 'Anklets', 'Mangalsutra', 'Wedding Jewellery', 'Kids Jewellery',
      'Coins', 'Other', 'German Silver Products', 'Photo Frames'
    )
    -- Script B's seed; YG creates its own per-POS 'Unregistered' with a Tamil name.
    OR (c.name_en = 'Unregistered' AND c.name_ta = 'Unregistered')
  )
  AND NOT EXISTS (SELECT 1 FROM public.products p WHERE p.category_id = c.id);

-- 2. Extra stock trigger on orders (script B) ------------------------------

DROP TRIGGER IF EXISTS orders_stock_trigger ON public.orders;

-- 3. Indexes and storage rules added by script B
-- Cross-POS uniqueness rules re-added by script B ------------------------

DROP INDEX IF EXISTS public.coupons_code_upper_unique;
DROP INDEX IF EXISTS public.categories_name_en_key;
DROP INDEX IF EXISTS public.barcode_registry_barcode_value_key;

-- Other indexes only script B created
DROP INDEX IF EXISTS public.idx_inv_movements_reference;
DROP INDEX IF EXISTS public.idx_product_variants_expiry;

-- File-storage access rules script B added (YG's own storage rules and
-- the buckets themselves are left as they are)
DROP POLICY IF EXISTS pos_files_read ON storage.objects;
DROP POLICY IF EXISTS pos_files_insert ON storage.objects;
DROP POLICY IF EXISTS pos_files_update ON storage.objects;
DROP POLICY IF EXISTS pos_files_delete ON storage.objects;

-- 4. Columns added to YG tables ---------------------------------------------

ALTER TABLE public.products
  DROP COLUMN IF EXISTS has_special_offer,
  DROP COLUMN IF EXISTS special_offer_note,
  DROP COLUMN IF EXISTS special_offer_cost,
  DROP COLUMN IF EXISTS expiry_date,
  DROP COLUMN IF EXISTS mfg_date,
  DROP COLUMN IF EXISTS location,
  DROP COLUMN IF EXISTS metal_type,
  DROP COLUMN IF EXISTS purity,
  DROP COLUMN IF EXISTS gross_weight,
  DROP COLUMN IF EXISTS stone_weight,
  DROP COLUMN IF EXISTS net_weight,
  DROP COLUMN IF EXISTS making_charge,
  DROP COLUMN IF EXISTS making_charge_type,
  DROP COLUMN IF EXISTS wastage,
  DROP COLUMN IF EXISTS wastage_type,
  DROP COLUMN IF EXISTS stone_charge,
  DROP COLUMN IF EXISTS other_charge,
  DROP COLUMN IF EXISTS huid,
  DROP COLUMN IF EXISTS design_number,
  DROP COLUMN IF EXISTS subcategory,
  DROP COLUMN IF EXISTS other_weight,
  DROP COLUMN IF EXISTS hallmark_status,
  DROP COLUMN IF EXISTS stone_details;

ALTER TABLE public.product_variants
  DROP COLUMN IF EXISTS expiry_date,
  DROP COLUMN IF EXISTS quantity,
  DROP COLUMN IF EXISTS mfg_date,
  DROP COLUMN IF EXISTS quantity_unit_id,
  DROP COLUMN IF EXISTS damage_stock;

ALTER TABLE public.orders
  DROP COLUMN IF EXISTS is_credit,
  DROP COLUMN IF EXISTS credit_due_date,
  DROP COLUMN IF EXISTS credit_status,
  DROP COLUMN IF EXISTS credit_paid_at,
  DROP COLUMN IF EXISTS scheme_id,
  DROP COLUMN IF EXISTS scheme_number,
  DROP COLUMN IF EXISTS scheme_amount_used,
  DROP COLUMN IF EXISTS scheme_discount,
  DROP COLUMN IF EXISTS scheme_balance_after,
  DROP COLUMN IF EXISTS customer_gstin,
  DROP COLUMN IF EXISTS exchange_amount,
  DROP COLUMN IF EXISTS advance_amount_used,
  DROP COLUMN IF EXISTS amount_paid;

ALTER TABLE public.order_items
  DROP COLUMN IF EXISTS special_offer_note,
  DROP COLUMN IF EXISTS special_offer_cost;

ALTER TABLE public.store_settings
  DROP COLUMN IF EXISTS instagram_handle,
  DROP COLUMN IF EXISTS low_stock_threshold,
  DROP COLUMN IF EXISTS admin_id,
  DROP COLUMN IF EXISTS admin_password,
  DROP COLUMN IF EXISTS staff_id,
  DROP COLUMN IF EXISTS staff_password,
  DROP COLUMN IF EXISTS expiry_alert_days,
  DROP COLUMN IF EXISTS accent_color,
  DROP COLUMN IF EXISTS shop_contact_number,
  DROP COLUMN IF EXISTS customer_event_messages,
  DROP COLUMN IF EXISTS scheme_rules,
  DROP COLUMN IF EXISTS gstin,
  DROP COLUMN IF EXISTS state_name,
  DROP COLUMN IF EXISTS state_code,
  DROP COLUMN IF EXISTS pos_permissions;

-- 5. Functions, tables, view and sequences created by the scripts -----------
-- No CASCADE: if anything outside the scripts depended on these, the
-- migration stops instead of silently removing it.


-- Script A functions
DROP FUNCTION IF EXISTS public.scheme_paid_status(DATE);
DROP FUNCTION IF EXISTS public.jewellery_upsert_customer(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.create_jewellery_scheme(TEXT, TEXT, TEXT, NUMERIC, INTEGER, INTEGER, DATE, DATE, TEXT, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.create_jewellery_scheme(TEXT, TEXT, TEXT, NUMERIC, INTEGER, INTEGER, DATE, DATE, TEXT, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.record_scheme_installment(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.redeem_jewellery_scheme(UUID, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.link_scheme_redemption(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.reverse_scheme_redemption(UUID);
DROP FUNCTION IF EXISTS public.cancel_jewellery_scheme(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.transfer_jewellery_scheme(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.refresh_scheme_maturity();
DROP FUNCTION IF EXISTS public.reserve_customer_advance(UUID, NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.link_advance_usage(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.reverse_advance_usage(UUID);
DROP FUNCTION IF EXISTS public.cancel_customer_advance(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.approve_sales_return(UUID, TEXT);
DROP FUNCTION IF EXISTS public.reject_sales_return(UUID, TEXT);

-- Script B functions that YG never had
DROP FUNCTION IF EXISTS public.orders_stock_trigger();
DROP FUNCTION IF EXISTS public.apply_order_sale_stock(public.orders);
DROP FUNCTION IF EXISTS public.reverse_order_sale_stock(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.order_counts_as_sold(TEXT);
DROP FUNCTION IF EXISTS public.mark_credit_order_paid(UUID);
DROP FUNCTION IF EXISTS public.next_invoice_no();
DROP FUNCTION IF EXISTS public.create_order_without_stock(TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, TEXT, NUMERIC);

-- Script B's versions of YG functions (their signatures differ from YG's,
-- so they must go before YG's are re-created, or calls become ambiguous)
DROP FUNCTION IF EXISTS public.complete_pos_sale_with_inventory(TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.create_order_with_stock(TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.create_advance_order(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.complete_advance_order_v2(UUID, TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.update_advance_order_status(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.add_advance_order_event(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.adjust_inventory_stock(INTEGER, TEXT, NUMERIC, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.create_barcode_and_receive_stock(INTEGER, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.generate_barcode_value(TEXT);
DROP FUNCTION IF EXISTS public.get_expense_summary_metrics(DATE);
DROP FUNCTION IF EXISTS public.get_public_invoice_by_number(TEXT);

-- Tables and view (after the functions that return their row types)
DROP VIEW IF EXISTS public.current_metal_rates;
DROP TABLE IF EXISTS public.scheme_redemptions;
DROP TABLE IF EXISTS public.scheme_installments;
DROP TABLE IF EXISTS public.advance_usages;
DROP TABLE IF EXISTS public.sales_returns;
DROP TABLE IF EXISTS public.customer_advances;
DROP TABLE IF EXISTS public.jewellery_schemes;
DROP TABLE IF EXISTS public.old_gold_exchanges;
DROP TABLE IF EXISTS public.quotations;
DROP TABLE IF EXISTS public.repairs;
DROP TABLE IF EXISTS public.audit_logs;
DROP TABLE IF EXISTS public.metal_rates;
DROP TABLE IF EXISTS public.damage_stock;
DROP TABLE IF EXISTS public.product_price_history;
DROP TABLE IF EXISTS public.unit_conversions;
DROP TABLE IF EXISTS public.unit_types;
DROP TABLE IF EXISTS public.barcode_custom_sizes;
DROP TABLE IF EXISTS public.customers;

-- Trigger functions of those tables (their triggers went with the tables)
DROP FUNCTION IF EXISTS public.metal_rates_append_only();
DROP FUNCTION IF EXISTS public.scheme_installments_protect_paid();
DROP FUNCTION IF EXISTS public.audit_logs_append_only();
DROP FUNCTION IF EXISTS public.audit_metal_rate_insert();

-- Sequences created by the scripts (YG's own sequences are kept)
DROP SEQUENCE IF EXISTS public.invoice_no_seq;
DROP SEQUENCE IF EXISTS public.scheme_number_seq;
DROP SEQUENCE IF EXISTS public.scheme_receipt_seq;
DROP SEQUENCE IF EXISTS public.advance_receipt_seq;
DROP SEQUENCE IF EXISTS public.old_gold_seq;
DROP SEQUENCE IF EXISTS public.return_number_seq;
DROP SEQUENCE IF EXISTS public.quotation_number_seq;
DROP SEQUENCE IF EXISTS public.repair_number_seq;

-- 6. Restore YG's own functions, verbatim from YG's latest migrations --------

-- is_admin  (from 20260716_0001_purple_boutique_schema.sql)
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

-- touch_updated_at  (from 20260716_0001_purple_boutique_schema.sql)
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- handle_new_user  (from 20260716_0001_purple_boutique_schema.sql)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := CASE WHEN COALESCE(NEW.raw_user_meta_data ->> 'role', '') = 'admin' THEN 'admin' ELSE 'customer' END;
BEGIN
  INSERT INTO public.profiles (id, customer_code, name, mobile, email, role)
  VALUES (
    NEW.id,
    'CUST-' || LPAD(nextval('public.customer_code_seq')::TEXT, 5, '0'),
    COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'name'), ''), split_part(COALESCE(NEW.email, ''), '@', 1), 'Customer'),
    COALESCE(NEW.raw_user_meta_data ->> 'mobile', ''),
    NEW.email,
    v_role
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    mobile = EXCLUDED.mobile,
    email = EXCLUDED.email,
    updated_at = NOW();

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::JSONB) || jsonb_build_object('role', v_role)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- sync_product_category_name  (from 20260716_0001_purple_boutique_schema.sql)
CREATE OR REPLACE FUNCTION public.sync_product_category_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.category_id IS NOT NULL THEN
    SELECT name_en INTO NEW.category FROM public.categories WHERE id = NEW.category_id;
  END IF;
  RETURN NEW;
END;
$$;

-- sync_category_name_to_products  (from 20260716_0001_purple_boutique_schema.sql)
CREATE OR REPLACE FUNCTION public.sync_category_name_to_products()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.name_en IS DISTINCT FROM OLD.name_en THEN
    UPDATE public.products SET category = NEW.name_en, updated_at = NOW() WHERE category_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

-- ensure_one_default_variant  (from 20260716_0001_purple_boutique_schema.sql)
CREATE OR REPLACE FUNCTION public.ensure_one_default_variant()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.is_default THEN
    UPDATE public.product_variants
    SET is_default = FALSE, updated_at = NOW()
    WHERE product_id = NEW.product_id AND id <> NEW.id AND is_default;
  END IF;
  RETURN NEW;
END;
$$;

-- generate_barcode_value  (from 20261005_0034_repair_branch_aware_inventory_rpcs.sql)
CREATE OR REPLACE FUNCTION public.generate_barcode_value(p_entity_type TEXT, p_branch TEXT DEFAULT 'pos1')
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_branch = 'pos2' THEN
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
$$;

-- create_order_with_stock  (from 20260924_0020_split_pos_branches.sql + 0039 per-POS coupon usage)
CREATE OR REPLACE FUNCTION public.create_order_with_stock(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'pending',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC(12,2) := 0;
  v_total NUMERIC(12,2);
  v_item JSONB;
  v_quantity NUMERIC(12,3);
  v_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_source TEXT;
  v_attempt INTEGER;
  v_uses_typed_item_ids BOOLEAN;
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one order item is required';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_quantity := GREATEST(COALESCE(NULLIF(v_item ->> 'quantity', '')::NUMERIC, 0), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_item ->> 'base_price', '')::NUMERIC, 0), 0);
    v_line_total := GREATEST(
      COALESCE(NULLIF(v_item ->> 'line_total', '')::NUMERIC, v_quantity * v_price),
      0
    );

    IF v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero';
    END IF;

    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(
    ROUND(
      v_subtotal + GREATEST(COALESCE(p_shipping, 0), 0)
        + GREATEST(COALESCE(p_delivery_charge, 0), 0)
        + GREATEST(COALESCE(p_total_gst, 0), 0)
        - GREATEST(COALESCE(p_discount_amount, 0), 0)
        - GREATEST(COALESCE(p_manual_discount_amount, 0), 0),
      2
    ),
    0
  );

  SELECT data_type = 'bigint'
  INTO v_uses_typed_item_ids
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'order_items' AND column_name = 'product_id';

  FOR v_attempt IN 1..5 LOOP
    v_invoice_no := public.get_next_invoice_no(v_branch);
    v_order_id := gen_random_uuid();

    BEGIN
      INSERT INTO public.orders (
        id, invoice_no, user_id, customer_name, phone, address, items, subtotal, shipping, total,
        status, order_mode, order_type, delivery_charge, discount_amount, manual_discount_amount,
        manual_discount_type, manual_discount_value, coupon_code, coupon_percentage, total_gst,
        gst_amount, gst_enabled, payment_method, payment_mode, split_details, branch, created_at, updated_at
      ) VALUES (
        v_order_id, v_invoice_no, auth.uid(),
        COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Walk-in Customer'),
        COALESCE(BTRIM(p_phone), ''), COALESCE(NULLIF(BTRIM(p_address), ''), 'POS Counter'),
        p_items, v_subtotal, GREATEST(COALESCE(p_shipping, 0), 0), v_total,
        COALESCE(NULLIF(BTRIM(p_status), ''), 'pending'),
        COALESCE(NULLIF(BTRIM(p_order_mode), ''), 'offline'),
        COALESCE(NULLIF(BTRIM(p_order_type), ''), 'pos_sale'),
        GREATEST(COALESCE(p_delivery_charge, 0), 0),
        GREATEST(COALESCE(p_discount_amount, 0), 0),
        GREATEST(COALESCE(p_manual_discount_amount, 0), 0),
        COALESCE(NULLIF(BTRIM(p_manual_discount_type), ''), 'flat'),
        GREATEST(COALESCE(p_manual_discount_value, 0), 0),
        NULLIF(BTRIM(COALESCE(p_coupon_code, '')), ''),
        GREATEST(COALESCE(p_coupon_percentage, 0), 0),
        GREATEST(COALESCE(p_total_gst, 0), 0), GREATEST(COALESCE(p_total_gst, 0), 0),
        COALESCE(p_gst_enabled, FALSE),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(NULLIF(BTRIM(p_payment_method), ''), 'cash'),
        COALESCE(p_split_details, '{}'::JSONB), v_branch, NOW(), NOW()
      );
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt = 5 THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_quantity := GREATEST(COALESCE(NULLIF(v_item ->> 'quantity', '')::NUMERIC, 0), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_item ->> 'base_price', '')::NUMERIC, 0), 0);
    v_line_total := GREATEST(
      COALESCE(NULLIF(v_item ->> 'line_total', '')::NUMERIC, v_quantity * v_price),
      0
    );
    v_source := COALESCE(NULLIF(v_item ->> 'source', ''), 'catalogue');

    IF v_uses_typed_item_ids THEN
      INSERT INTO public.order_items (
        order_id, product_id, variant_id, product_name, tamil_name, variant_name,
        quantity, unit, unit_price, line_total, is_manual, source, note
      ) VALUES (
        v_order_id, NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), '')::BIGINT,
        NULLIF(v_item ->> 'variant_id', '')::UUID, COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
        NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'variant_name', ''),
        v_quantity, COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'), v_price, v_line_total,
        v_source = 'manual', v_source, NULLIF(v_item ->> 'note', '')
      );
    ELSE
      INSERT INTO public.order_items (
        order_id, product_id, variant_id, product_name, tamil_name, variant_name,
        quantity, unit, unit_price, line_total, is_manual, source, note
      ) VALUES (
        v_order_id, NULLIF(COALESCE(v_item ->> 'product_id', v_item ->> 'id'), ''),
        NULLIF(v_item ->> 'variant_id', ''), COALESCE(NULLIF(v_item ->> 'name', ''), 'Product'),
        NULLIF(v_item ->> 'tamil_name', ''), NULLIF(v_item ->> 'variant_name', ''),
        v_quantity, COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece'), v_price, v_line_total,
        v_source = 'manual', v_source, NULLIF(v_item ->> 'note', '')
      );
    END IF;

    IF COALESCE(v_item ->> 'product_id', v_item ->> 'id', '') ~ '^[0-9]+$' THEN
      UPDATE public.products
      SET stock_quantity = GREATEST(stock_quantity - v_quantity, 0),
          stock = GREATEST(FLOOR(stock_quantity - v_quantity), 0)::INTEGER,
          updated_at = NOW()
      WHERE id::TEXT = COALESCE(v_item ->> 'product_id', v_item ->> 'id')
        AND branch = v_branch;
    END IF;

    IF NULLIF(v_item ->> 'variant_id', '') IS NOT NULL THEN
      UPDATE public.product_variants
      SET stock = GREATEST(stock - v_quantity, 0), updated_at = NOW()
      WHERE id::TEXT = v_item ->> 'variant_id'
        AND branch = v_branch;
    END IF;
  END LOOP;

  IF NULLIF(BTRIM(COALESCE(p_coupon_code, '')), '') IS NOT NULL THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code)) AND branch = v_branch
      AND is_active
      AND (usage_limit IS NULL OR usage_count < usage_limit);
  END IF;

  RETURN jsonb_build_object(
    'orderId', v_order_id,
    'invoiceNo', v_invoice_no,
    'createdAt', NOW()
  );
END;
$$;

-- complete_pos_sale_with_inventory  (from 20261005_0034_repair_branch_aware_inventory_rpcs.sql + 0039 per-POS coupon usage)
CREATE OR REPLACE FUNCTION public.complete_pos_sale_with_inventory(
  p_customer_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_items JSONB,
  p_shipping NUMERIC DEFAULT 0,
  p_status TEXT DEFAULT 'completed',
  p_order_mode TEXT DEFAULT 'offline',
  p_order_type TEXT DEFAULT 'pos_sale',
  p_delivery_charge NUMERIC DEFAULT 0,
  p_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_amount NUMERIC DEFAULT 0,
  p_manual_discount_type TEXT DEFAULT 'flat',
  p_manual_discount_value NUMERIC DEFAULT 0,
  p_coupon_code TEXT DEFAULT NULL,
  p_coupon_percentage NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_split_details JSONB DEFAULT '{}'::JSONB,
  p_total_gst NUMERIC DEFAULT 0,
  p_gst_enabled BOOLEAN DEFAULT FALSE,
  p_remarks TEXT DEFAULT NULL,
  p_reference_number TEXT DEFAULT NULL,
  p_billing_date TIMESTAMPTZ DEFAULT NULL,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_invoice_no TEXT;
  v_order_id UUID;
  v_subtotal NUMERIC := 0;
  v_total NUMERIC := 0;
  v_item JSONB;
  v_product_id BIGINT;
  v_variant_id UUID;
  v_quantity NUMERIC;
  v_unit_price NUMERIC;
  v_line_total NUMERIC;
  v_product_name TEXT;
  v_name_ta TEXT;
  v_unit TEXT;
  v_unit_type TEXT;
  v_base_quantity NUMERIC;
  v_is_manual BOOLEAN;
  v_discount NUMERIC;
  v_gst_amount NUMERIC;
  v_gst_rate NUMERIC;
  v_image_url TEXT;
  v_variant_name TEXT;
  v_source TEXT;
  v_note TEXT;
  v_category TEXT;
  v_current_stock NUMERIC;
  v_barcode_id UUID;
  v_created_at TIMESTAMPTZ := COALESCE(p_billing_date, NOW());
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order items cannot be empty';
  END IF;

  -- 1. Atomic Pre-Validation of Available Stock for All Items (branch-scoped)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');

    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 2. Calculate Subtotal & Generate Invoice Number (from this branch's sequence)
  v_invoice_no := public.get_next_invoice_no(v_branch);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE(
      (v_item ->> 'unit_price')::NUMERIC,
      (v_item ->> 'base_price')::NUMERIC,
      (v_item ->> 'price')::NUMERIC,
      0
    );
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_subtotal := v_subtotal + v_line_total;
  END LOOP;

  v_total := GREATEST(0, ROUND(v_subtotal + COALESCE(p_shipping, 0) + COALESCE(p_delivery_charge, 0) - COALESCE(p_discount_amount, 0), 2));

  -- 3. Insert Order Record
  INSERT INTO public.orders (
    invoice_no, user_id, customer_name, phone, address, items,
    subtotal, shipping, total, status, order_mode, order_type,
    delivery_charge, discount_amount, manual_discount_amount,
    manual_discount_type, manual_discount_value, coupon_code,
    coupon_percentage, total_gst, gst_amount, gst_enabled,
    payment_method, payment_mode, split_details, remarks,
    reference_number, billing_date, branch, created_at, updated_at
  )
  VALUES (
    v_invoice_no, v_user_id, COALESCE(NULLIF(BTRIM(p_customer_name), ''), 'Customer'),
    COALESCE(p_phone, ''), COALESCE(p_address, ''), p_items,
    v_subtotal, COALESCE(p_shipping, 0), v_total, COALESCE(p_status, 'completed'),
    COALESCE(p_order_mode, 'offline'), COALESCE(p_order_type, 'pos_sale'),
    COALESCE(p_delivery_charge, 0), COALESCE(p_discount_amount, 0),
    COALESCE(p_manual_discount_amount, 0), COALESCE(p_manual_discount_type, 'flat'),
    COALESCE(p_manual_discount_value, 0), p_coupon_code,
    COALESCE(p_coupon_percentage, 0), COALESCE(p_total_gst, 0),
    COALESCE(p_total_gst, 0), COALESCE(p_gst_enabled, FALSE),
    COALESCE(p_payment_method, 'cash'), COALESCE(p_payment_method, 'cash'),
    COALESCE(p_split_details, '{}'::JSONB), COALESCE(p_remarks, ''),
    COALESCE(p_reference_number, ''), p_billing_date, v_branch, v_created_at, NOW()
  )
  RETURNING id INTO v_order_id;

  -- 4. Insert Order Items, Deduct Stock (branch-scoped) & Record SALE Movements
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item ->> 'product_id', '')::BIGINT;
    v_variant_id := NULLIF(v_item ->> 'variant_id', '')::UUID;
    v_quantity := COALESCE((v_item ->> 'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE((v_item ->> 'unit_price')::NUMERIC, (v_item ->> 'base_price')::NUMERIC, 0);
    v_line_total := COALESCE((v_item ->> 'line_total')::NUMERIC, ROUND(v_quantity * v_unit_price, 2));
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');
    v_name_ta := COALESCE(v_item ->> 'product_tamil_name', v_item ->> 'tamil_name', '');
    v_unit := COALESCE(v_item ->> 'unit', 'piece');
    v_unit_type := COALESCE(v_item ->> 'unit_type', 'unit');
    v_base_quantity := COALESCE((v_item ->> 'base_quantity')::NUMERIC, 1);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::BOOLEAN, FALSE);
    v_discount := COALESCE((v_item ->> 'discount')::NUMERIC, 0);
    v_gst_amount := COALESCE((v_item ->> 'gst_amount')::NUMERIC, 0);
    v_gst_rate := COALESCE((v_item ->> 'gst_rate')::NUMERIC, 0);
    v_image_url := v_item ->> 'image_url';
    v_variant_name := v_item ->> 'variant_name';
    v_source := COALESCE(v_item ->> 'source', 'catalogue');
    v_note := v_item ->> 'note';
    v_category := v_item ->> 'category';

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name,
      product_tamil_name, tamil_name, quantity, unit, unit_type,
      base_quantity, base_price, unit_price, line_total, image_url,
      is_manual, discount, gst_amount, gst_rate, variant_name,
      source, note, category, created_at
    )
    VALUES (
      v_order_id, v_product_id, v_variant_id, v_product_name, v_product_name,
      v_name_ta, v_name_ta, v_quantity, v_unit, v_unit_type,
      v_base_quantity, v_unit_price, v_unit_price, v_line_total, v_image_url,
      v_is_manual, v_discount, v_gst_amount, v_gst_rate, v_variant_name,
      v_source, v_note, v_category, v_created_at
    );

    -- Deduct Stock and Insert SALE Movement (branch-scoped)
    IF NOT v_is_manual AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = v_variant_id AND is_active = TRUE LIMIT 1;

        UPDATE public.product_variants
        SET stock = GREATEST(0, stock - v_quantity), updated_at = NOW()
        WHERE id = v_variant_id AND branch = v_branch;

        -- Parent aggregate update
        UPDATE public.products
        SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE),
            stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE))::INTEGER,
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, v_variant_id, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );

      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id AND branch = v_branch;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = v_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - v_quantity),
            stock = GREATEST(0, stock - FLOOR(v_quantity)::INTEGER),
            updated_at = NOW()
        WHERE id = v_product_id AND branch = v_branch;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, branch
        )
        VALUES (
          v_product_id, NULL, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice_no, 'POS Sale checkout', v_branch
        );
      END IF;
    END IF;
  END LOOP;

  -- 5. Increment Coupon Usage Count (coupons remain shared across branches)
  IF p_coupon_code IS NOT NULL AND BTRIM(p_coupon_code) <> '' THEN
    UPDATE public.coupons
    SET usage_count = usage_count + 1, updated_at = NOW()
    WHERE UPPER(BTRIM(code)) = UPPER(BTRIM(p_coupon_code)) AND branch = v_branch;
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'invoice_no', v_invoice_no,
    'total', v_total
  );
END;
$$;

-- get_public_invoice_by_number  (from 20260918_0019_robust_public_invoice_lookup.sql)
CREATE OR REPLACE FUNCTION public.get_public_invoice_by_number(p_invoice_no TEXT)
RETURNS SETOF public.orders
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM public.orders 
  WHERE invoice_no = NULLIF(BTRIM(p_invoice_no), '')
     OR LOWER(invoice_no) = LOWER(NULLIF(BTRIM(p_invoice_no), ''))
     OR invoice_no = REGEXP_REPLACE(BTRIM(p_invoice_no), '^(INV|PB)[-_ ]*', '', 'i')
     OR (
       REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g') <> ''
       AND invoice_no = LPAD(REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g'), 8, '0')
     )
     OR (
       REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g') <> ''
       AND invoice_no = REGEXP_REPLACE(REGEXP_REPLACE(BTRIM(p_invoice_no), '\D', '', 'g'), '^0+', '')
     )
     OR (
       p_invoice_no ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       AND id = p_invoice_no::UUID
     )
  LIMIT 1;
$$;

-- adjust_inventory_stock  (from 20261005_0034_repair_branch_aware_inventory_rpcs.sql)
CREATE OR REPLACE FUNCTION public.adjust_inventory_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_new_quantity NUMERIC DEFAULT 0,
  p_reason TEXT DEFAULT 'RESTOCK',
  p_note TEXT DEFAULT '',
  p_created_by_name TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_qty_before NUMERIC := 0;
  v_delta NUMERIC := 0;
  v_barcode_id UUID;
  v_branch TEXT;
BEGIN
  IF p_new_quantity < 0 THEN
    RAISE EXCEPTION 'Stock quantity cannot be negative';
  END IF;

  -- Verify variant if supplied
  IF p_variant_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.product_variants WHERE id = p_variant_id AND product_id = p_product_id) THEN
      RAISE EXCEPTION 'Variant does not belong to specified Product';
    END IF;

    SELECT stock, branch INTO v_qty_before, v_branch FROM public.product_variants WHERE id = p_variant_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = p_variant_id AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.product_variants
    SET stock = p_new_quantity, updated_at = NOW()
    WHERE id = p_variant_id;

    -- Refresh parent aggregate
    UPDATE public.products
    SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE),
        stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = p_product_id AND is_active = TRUE))::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  ELSE
    SELECT stock_quantity, branch INTO v_qty_before, v_branch FROM public.products WHERE id = p_product_id FOR UPDATE;
    SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

    v_delta := p_new_quantity - v_qty_before;

    UPDATE public.products
    SET stock_quantity = p_new_quantity,
        stock = FLOOR(p_new_quantity)::INTEGER,
        updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- Record Movement
  INSERT INTO public.inventory_movements (
    product_id, variant_id, barcode_id, movement_type,
    quantity_delta, quantity_before, quantity_after,
    reference_type, note, created_by_name, branch
  )
  VALUES (
    p_product_id, p_variant_id, v_barcode_id, p_reason,
    v_delta, v_qty_before, p_new_quantity,
    'adjustment', COALESCE(p_note, ''), COALESCE(p_created_by_name, ''), v_branch
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'quantity_before', v_qty_before,
    'quantity_after', p_new_quantity,
    'delta', v_delta,
    'reason', p_reason
  );
END;
$$;

-- create_advance_order  (from 20260924_0020_split_pos_branches.sql)
CREATE OR REPLACE FUNCTION public.create_advance_order(
  p_customer_name text, p_phone text, p_address text, p_product_name text,
  p_category text, p_description text, p_total_amount numeric, p_deposit_amount numeric,
  p_expected_delivery_date date, p_remarks text, p_payment_method text, p_created_by_name text,
  p_products jsonb DEFAULT '[]'::jsonb,
  p_branch text DEFAULT 'pos1'
)
RETURNS public.advance_orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_order public.advance_orders; v_now timestamptz := now(); v_deposit_id text; v_branch text := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  IF trim(coalesce(p_customer_name,'')) = '' THEN RAISE EXCEPTION 'Customer name is required'; END IF;
  IF trim(coalesce(p_phone,'')) = '' THEN RAISE EXCEPTION 'Phone number is required'; END IF;
  IF trim(coalesce(p_product_name,'')) = '' THEN RAISE EXCEPTION 'Product name is required'; END IF;
  IF coalesce(p_total_amount,0) <= 0 THEN RAISE EXCEPTION 'Total amount must be greater than zero'; END IF;
  IF coalesce(p_deposit_amount,0) <= 0 OR p_deposit_amount >= p_total_amount THEN RAISE EXCEPTION 'Deposit must be greater than zero and less than the total amount'; END IF;
  IF lower(coalesce(p_payment_method,'')) NOT IN ('cash','upi','card') THEN RAISE EXCEPTION 'Select a valid deposit payment method'; END IF;
  v_deposit_id := 'DEP-' || to_char(v_now at time zone 'Asia/Kolkata','YYYYMMDD') || '-' || lpad(nextval('public.deposit_number_seq')::text,4,'0');
  INSERT INTO public.advance_orders(deposit_id,customer_name,phone,address,product_name,products,category,description,total_amount,deposit_amount,expected_delivery_date,remarks,created_by,created_by_name,created_at,updated_at,branch)
  VALUES(v_deposit_id,trim(p_customer_name),trim(p_phone),trim(coalesce(p_address,'')),trim(p_product_name),CASE WHEN jsonb_typeof(coalesce(p_products,'[]'::jsonb))='array' THEN coalesce(p_products,'[]'::jsonb) ELSE '[]'::jsonb END,trim(coalesce(p_category,'')),trim(coalesce(p_description,'')),round(p_total_amount,2),round(p_deposit_amount,2),p_expected_delivery_date,trim(coalesce(p_remarks,'')),auth.uid(),trim(coalesce(p_created_by_name,'')),v_now,v_now,v_branch)
  RETURNING * INTO v_order;
  INSERT INTO public.advance_order_payments(advance_order_id,payment_type,amount,payment_method,remarks,received_by,received_at)
  VALUES(v_order.id,'deposit',v_order.deposit_amount,lower(p_payment_method),coalesce(p_remarks,''),auth.uid(),v_now);
  INSERT INTO public.advance_order_timeline(advance_order_id,event_type,label,created_by,created_at) VALUES
    (v_order.id,'created','Created',auth.uid(),v_now),
    (v_order.id,'deposit_received','Deposit Received',auth.uid(),v_now);
  RETURN v_order;
END;
$$;

-- complete_advance_order_v2  (from 20261010_0040_advance_order_completion_deducts_stock.sql)
CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_bill_items     jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;
  v_branch         text;
  v_raw_product    text;
  v_raw_variant    text;
  v_product_id     bigint;
  v_variant_id     uuid;
  v_quantity       numeric;
  v_name           text;
  v_stock          numeric;
  v_barcode_id     uuid;
  v_tracked        boolean;
BEGIN
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;

  -- The advance order's own branch is the single source of truth.
  v_branch := CASE WHEN v_advance.branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;

  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;

  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL THEN
    IF v_advance.status != 'completed' THEN
      UPDATE public.advance_orders
      SET status = 'completed',
          updated_at = v_now
      WHERE id = p_order_id;
    END IF;

    RETURN QUERY SELECT
      coalesce(v_advance.completed_order_id, gen_random_uuid()),
      coalesce(v_advance.invoice_number, 'INV00000000'),
      coalesce(v_advance.completed_at, v_now);
    RETURN;
  END IF;

  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;
  v_bill_items := v_items;

  -- 1. Resolve each item against THIS counter's catalog, lock its stock
  --    row and make sure there is enough. Resolved ids are written back
  --    into v_items so the later steps never look outside the branch.
  FOR i IN 0 .. jsonb_array_length(v_items) - 1 LOOP
    v_item := v_items -> i;
    v_raw_product := btrim(coalesce(v_item ->> 'product_id', ''));
    v_raw_variant := btrim(coalesce(v_item ->> 'variant_id', ''));
    v_product_id := CASE WHEN v_raw_product ~ '^[0-9]+$' THEN v_raw_product::bigint END;
    v_variant_id := CASE
      WHEN v_raw_variant ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN v_raw_variant::uuid
    END;
    v_quantity := greatest(coalesce(nullif(v_item ->> 'quantity', '')::numeric, 1), 0);
    v_name := coalesce(nullif(btrim(v_item ->> 'name'), ''), 'Product');
    v_tracked := FALSE;
    v_stock := NULL;

    IF v_variant_id IS NOT NULL THEN
      SELECT pv.stock, pv.product_id INTO v_stock, v_product_id
      FROM public.product_variants pv
      WHERE pv.id = v_variant_id AND pv.branch = v_branch
      FOR UPDATE;
      IF NOT FOUND THEN
        v_variant_id := NULL;
        v_product_id := NULL;
      END IF;
    END IF;

    IF v_product_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = v_product_id AND p.branch = v_branch
    ) THEN
      v_product_id := NULL;
      v_variant_id := NULL;
    END IF;

    IF v_product_id IS NOT NULL
       AND NOT coalesce((v_item ->> 'is_manual')::boolean, FALSE)
       AND NOT EXISTS (
         SELECT 1 FROM public.products p
         WHERE p.id = v_product_id AND lower(btrim(coalesce(p.category, ''))) = 'unregistered'
       )
       AND v_quantity > 0 THEN
      v_tracked := TRUE;
      IF v_variant_id IS NULL THEN
        SELECT p.stock_quantity INTO v_stock
        FROM public.products p
        WHERE p.id = v_product_id AND p.branch = v_branch
        FOR UPDATE;
      END IF;

      IF coalesce(v_stock, 0) < v_quantity THEN
        RAISE EXCEPTION 'Not enough stock to complete this order: % (in stock: %, needed: %). Restock it in Inventory, then complete the order.',
          v_name, coalesce(v_stock, 0), v_quantity;
      END IF;
    END IF;

    v_items := jsonb_set(
      v_items, ARRAY[i::text],
      v_item || jsonb_build_object(
        '_product_id', v_product_id,
        '_variant_id', v_variant_id,
        '_tracked',    v_tracked
      )
    );
  END LOOP;

  -- 2. Bill, numbered from this counter's sequence.
  v_invoice := public.get_next_invoice_no(v_branch);

  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, branch, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_bill_items,
    v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method), v_branch,
    v_now, v_now
  );

  -- 3. Bill lines, stock deduction and stock ledger (all branch-scoped).
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    v_product_id := nullif(v_item ->> '_product_id', '')::bigint;
    v_variant_id := nullif(v_item ->> '_variant_id', '')::uuid;
    v_quantity := greatest(coalesce(nullif(v_item ->> 'quantity', '')::numeric, 1), 0);

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, variant_name, category,
      product_name, name, quantity, unit, unit_type,
      base_price, line_total, is_manual
    ) VALUES (
      v_order_id, v_product_id, v_variant_id, nullif(v_item ->> 'variant_name', ''),
      nullif(v_item ->> 'category', ''),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      coalesce(nullif(trim(v_item->>'name'), ''), 'Product'),
      v_quantity,
      coalesce(nullif(v_item->>'unit', ''), 'piece'),
      coalesce(nullif(v_item->>'unit_type', ''), 'unit'),
      greatest(coalesce((v_item->>'base_price')::numeric, 0), 0),
      greatest(coalesce((v_item->>'line_total')::numeric, 0), 0),
      false
    );

    CONTINUE WHEN NOT coalesce((v_item ->> '_tracked')::boolean, FALSE);

    IF v_variant_id IS NOT NULL THEN
      SELECT stock INTO v_stock FROM public.product_variants WHERE id = v_variant_id AND branch = v_branch;
      SELECT id INTO v_barcode_id FROM public.barcode_registry
      WHERE variant_id = v_variant_id AND branch = v_branch AND is_active = TRUE LIMIT 1;

      UPDATE public.product_variants
      SET stock = greatest(0, stock - v_quantity), updated_at = v_now
      WHERE id = v_variant_id AND branch = v_branch;

      UPDATE public.products
      SET stock_quantity = (SELECT coalesce(sum(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND branch = v_branch AND is_active = TRUE),
          stock = floor((SELECT coalesce(sum(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND branch = v_branch AND is_active = TRUE))::integer,
          updated_at = v_now
      WHERE id = v_product_id AND branch = v_branch;
    ELSE
      SELECT stock_quantity INTO v_stock FROM public.products WHERE id = v_product_id AND branch = v_branch;
      SELECT id INTO v_barcode_id FROM public.barcode_registry
      WHERE product_id = v_product_id AND variant_id IS NULL AND branch = v_branch AND is_active = TRUE LIMIT 1;

      UPDATE public.products
      SET stock_quantity = greatest(0, stock_quantity - v_quantity),
          stock = greatest(0, floor(stock_quantity - v_quantity))::integer,
          updated_at = v_now
      WHERE id = v_product_id AND branch = v_branch;
    END IF;

    INSERT INTO public.inventory_movements (
      product_id, variant_id, barcode_id, movement_type,
      quantity_delta, quantity_before, quantity_after,
      reference_type, reference_id, note, branch
    ) VALUES (
      v_product_id, v_variant_id, v_barcode_id, 'SALE',
      -v_quantity, v_stock, greatest(0, v_stock - v_quantity),
      'order', v_invoice, 'Advance order completed (' || v_advance.deposit_id || ')', v_branch
    );
  END LOOP;

  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

-- update_advance_order_status  (from 20260918_0018_advance_order_self_heal.sql)
CREATE OR REPLACE FUNCTION public.update_advance_order_status(
  p_order_id uuid,
  p_status   text,
  p_remarks  text DEFAULT ''
)
RETURNS SETOF public.advance_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.advance_orders;
BEGIN
  SELECT * INTO v_order FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order % not found', p_order_id;
  END IF;

  IF (v_order.invoice_number IS NOT NULL OR v_order.completed_order_id IS NOT NULL) AND p_status != 'completed' THEN
    RAISE EXCEPTION 'Cannot change status of an order that already has an invoice generated';
  END IF;

  UPDATE public.advance_orders SET
    status     = p_status,
    remarks    = CASE WHEN trim(coalesce(p_remarks,'')) = '' THEN remarks ELSE p_remarks END,
    updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.advance_order_timeline (advance_order_id, event_type, label, remarks, created_by, created_at)
  VALUES (
    p_order_id,
    p_status,
    CASE p_status
      WHEN 'pending_deposit'       THEN 'Status: Pending Deposit'
      WHEN 'waiting_final_payment' THEN 'Status: Waiting for Final Payment'
      WHEN 'ready_for_delivery'    THEN 'Status: Ready to Collect'
      WHEN 'completed'             THEN 'Order Completed'
      WHEN 'cancelled'             THEN 'Order Cancelled'
      ELSE p_status
    END,
    coalesce(p_remarks, ''),
    auth.uid(),
    now()
  );

  RETURN QUERY SELECT * FROM public.advance_orders WHERE id = p_order_id;
END;
$$;

-- add_advance_order_event  (from 20260728_0010_final_audit_fixes.sql)
CREATE OR REPLACE FUNCTION public.add_advance_order_event(
  p_order_id   uuid,
  p_event_type text,
  p_label      text,
  p_remarks    text DEFAULT ''
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.advance_order_timeline (advance_order_id, event_type, label, remarks, created_by, created_at)
  VALUES (p_order_id, p_event_type, p_label, coalesce(p_remarks,''), auth.uid(), now());
END;
$$;

-- create_barcode_and_receive_stock  (from 20261005_0034_repair_branch_aware_inventory_rpcs.sql)
CREATE OR REPLACE FUNCTION public.create_barcode_and_receive_stock(
  p_product_id BIGINT,
  p_variant_id UUID DEFAULT NULL,
  p_quantity_received NUMERIC DEFAULT 0,
  p_unit_cost NUMERIC DEFAULT NULL,
  p_created_by_name TEXT DEFAULT '',
  p_custom_barcode TEXT DEFAULT NULL,
  p_note TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entity_type TEXT;
  v_barcode_id UUID;
  v_barcode_value TEXT;
  v_is_new_barcode BOOLEAN := FALSE;
  v_movement_type TEXT;
  v_qty_before NUMERIC := 0;
  v_qty_after NUMERIC := 0;
  v_prod_name TEXT;
  v_var_name TEXT := '';
  v_branch TEXT;
BEGIN
  IF p_quantity_received < 0 THEN
    RAISE EXCEPTION 'Quantity received cannot be negative';
  END IF;

  -- 1. Check Parent Product Exists (and capture its branch)
  SELECT name, branch INTO v_prod_name, v_branch FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product with ID % not found', p_product_id;
  END IF;

  -- 2. Verify Variant Belongs to Product if Variant is Provided
  IF p_variant_id IS NOT NULL THEN
    v_entity_type := 'variant';
    SELECT variant_name, stock INTO v_var_name, v_qty_before
    FROM public.product_variants
    WHERE id = p_variant_id AND product_id = p_product_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Variant % does not belong to Product %', p_variant_id, p_product_id;
    END IF;
  ELSE
    v_entity_type := 'product';
    SELECT stock_quantity INTO v_qty_before
    FROM public.products
    WHERE id = p_product_id;
  END IF;

  -- 3. Check for Existing Active Barcode in barcode_registry (SKU Identity)
  IF v_entity_type = 'variant' THEN
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE variant_id = p_variant_id AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  ELSE
    SELECT id, barcode_value INTO v_barcode_id, v_barcode_value
    FROM public.barcode_registry
    WHERE product_id = p_product_id AND variant_id IS NULL AND is_active = TRUE
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  -- 4. Reuse Existing or Create New Barcode
  IF v_barcode_id IS NOT NULL THEN
    v_is_new_barcode := FALSE;
    v_movement_type := CASE WHEN v_qty_before = 0 THEN 'INITIAL_BARCODE_STOCK' ELSE 'RESTOCK' END;
  ELSE
    v_is_new_barcode := TRUE;
    v_movement_type := 'INITIAL_BARCODE_STOCK';
    v_barcode_value := COALESCE(NULLIF(UPPER(BTRIM(p_custom_barcode)), ''), public.generate_barcode_value(v_entity_type, v_branch));

    INSERT INTO public.barcode_registry (
      barcode_value, entity_type, product_id, variant_id, is_active, created_by_name, branch
    )
    VALUES (
      v_barcode_value, v_entity_type, p_product_id, p_variant_id, TRUE, COALESCE(p_created_by_name, ''), v_branch
    )
    RETURNING id INTO v_barcode_id;
  END IF;

  -- 5. Synchronize compatibility column on target table
  IF v_entity_type = 'variant' THEN
    UPDATE public.product_variants
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_variant_id;
  ELSE
    UPDATE public.products
    SET barcode = v_barcode_value, updated_at = NOW()
    WHERE id = p_product_id;
  END IF;

  -- 6. Apply Stock Increment & Parent Aggregate Sync
  v_qty_after := v_qty_before + p_quantity_received;

  IF p_quantity_received > 0 THEN
    IF v_entity_type = 'variant' THEN
      UPDATE public.product_variants
      SET stock = v_qty_after, updated_at = NOW()
      WHERE id = p_variant_id;

      -- Refresh parent aggregate stock cache
      UPDATE public.products
      SET stock_quantity = (
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ),
          stock = FLOOR((
            SELECT COALESCE(SUM(stock), 0)
            FROM public.product_variants
            WHERE product_id = p_product_id AND is_active = TRUE
          ))::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    ELSE
      UPDATE public.products
      SET stock_quantity = v_qty_after,
          stock = FLOOR(v_qty_after)::INTEGER,
          updated_at = NOW()
      WHERE id = p_product_id;
    END IF;
  END IF;

  -- 7. Record Immutable Inventory Movement
  IF p_quantity_received > 0 THEN
    INSERT INTO public.inventory_movements (
      product_id, variant_id, barcode_id, movement_type,
      quantity_delta, quantity_before, quantity_after,
      unit_cost, reference_type, reference_id, note, created_by_name, branch
    )
    VALUES (
      p_product_id, p_variant_id, v_barcode_id, v_movement_type,
      p_quantity_received, v_qty_before, v_qty_after,
      p_unit_cost, 'barcode_receipt', v_barcode_value,
      COALESCE(p_note, ''), COALESCE(p_created_by_name, ''), v_branch
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'barcode_id', v_barcode_id,
    'barcode_value', v_barcode_value,
    'is_new_barcode', v_is_new_barcode,
    'movement_type', v_movement_type,
    'quantity_before', v_qty_before,
    'quantity_received', p_quantity_received,
    'quantity_after', v_qty_after,
    'product_id', p_product_id,
    'variant_id', p_variant_id,
    'product_name', v_prod_name,
    'variant_name', v_var_name
  );
END;
$$;

-- get_expense_summary_metrics  (from 20260930_0027_split_expenses_by_branch.sql)
CREATE OR REPLACE FUNCTION public.get_expense_summary_metrics(
  p_current_date DATE DEFAULT CURRENT_DATE,
  p_branch TEXT DEFAULT 'pos1'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today NUMERIC(12,2) := 0;
  v_this_week NUMERIC(12,2) := 0;
  v_this_month NUMERIC(12,2) := 0;
  v_this_year NUMERIC(12,2) := 0;
  v_total_all_time NUMERIC(12,2) := 0;
  v_week_start DATE := date_trunc('week', p_current_date)::DATE;
  v_month_start DATE := date_trunc('month', p_current_date)::DATE;
  v_year_start DATE := date_trunc('year', p_current_date)::DATE;
  v_branch TEXT := CASE WHEN p_branch = 'pos2' THEN 'pos2' ELSE 'pos1' END;
BEGIN
  SELECT
    COALESCE(SUM(CASE WHEN expense_date = p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_week_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_month_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN expense_date >= v_year_start AND expense_date <= p_current_date THEN amount ELSE 0 END), 0),
    COALESCE(SUM(amount), 0)
  INTO
    v_today, v_this_week, v_this_month, v_this_year, v_total_all_time
  FROM public.expenses
  WHERE branch = v_branch;

  RETURN jsonb_build_object(
    'today', v_today,
    'this_week', v_this_week,
    'this_month', v_this_month,
    'this_year', v_this_year,
    'total_all_time', v_total_all_time
  );
END;
$$;

-- 7. Restore YG's own triggers ----------------------------------------------

-- on_auth_user_created  (from 20260716_0001_purple_boutique_schema.sql)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- sync_product_category_name_trigger  (from 20260716_0001_purple_boutique_schema.sql)
DROP TRIGGER IF EXISTS sync_product_category_name_trigger ON public.products;
CREATE TRIGGER sync_product_category_name_trigger
BEFORE INSERT OR UPDATE OF category_id ON public.products
FOR EACH ROW EXECUTE FUNCTION public.sync_product_category_name();

-- sync_category_name_to_products_trigger  (from 20260716_0001_purple_boutique_schema.sql)
DROP TRIGGER IF EXISTS sync_category_name_to_products_trigger ON public.categories;
CREATE TRIGGER sync_category_name_to_products_trigger
AFTER UPDATE OF name_en ON public.categories
FOR EACH ROW EXECUTE FUNCTION public.sync_category_name_to_products();

-- ensure_one_default_variant_trigger  (from 20260716_0001_purple_boutique_schema.sql)
DROP TRIGGER IF EXISTS ensure_one_default_variant_trigger ON public.product_variants;
CREATE TRIGGER ensure_one_default_variant_trigger
AFTER INSERT OR UPDATE OF is_default ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.ensure_one_default_variant();

-- 8. Access for the app (same roles YG's migrations grant) -------------------

GRANT EXECUTE ON FUNCTION public.complete_pos_sale_with_inventory(TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, TEXT, NUMERIC, TEXT, JSONB, NUMERIC, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_order_with_stock(TEXT, TEXT, TEXT, JSONB, NUMERIC, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_advance_order(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, DATE, TEXT, TEXT, TEXT, JSONB, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(UUID, TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_barcode_value(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_barcode_and_receive_stock(BIGINT, UUID, NUMERIC, NUMERIC, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_inventory_stock(BIGINT, UUID, NUMERIC, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_expense_summary_metrics(DATE, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_invoice_by_number(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_advance_order_status(UUID, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_advance_order_event(UUID, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 9. Verify -- any failure rolls back everything above -----------------------

DO $$
DECLARE
  v_missing TEXT;
  v_left TEXT;
BEGIN
  SELECT string_agg(x, ', ') INTO v_missing
  FROM unnest(ARRAY[
    'public.complete_pos_sale_with_inventory(text,text,text,jsonb,numeric,text,text,text,numeric,numeric,numeric,text,numeric,text,numeric,text,jsonb,numeric,boolean,text,text,timestamptz,text)',
    'public.create_order_with_stock(text,text,text,jsonb,numeric,text,text,text,numeric,numeric,numeric,text,numeric,text,numeric,numeric,boolean,text,jsonb,text)',
    'public.create_advance_order(text,text,text,text,text,text,numeric,numeric,date,text,text,text,jsonb,text)',
    'public.complete_advance_order_v2(uuid,text,numeric,text,numeric,numeric,text)',
    'public.generate_barcode_value(text,text)',
    'public.create_barcode_and_receive_stock(bigint,uuid,numeric,numeric,text,text,text)',
    'public.adjust_inventory_stock(bigint,uuid,numeric,text,text,text)',
    'public.get_expense_summary_metrics(date,text)',
    'public.get_public_invoice_by_number(text)',
    'public.update_advance_order_status(uuid,text,text)',
    'public.add_advance_order_event(uuid,text,text,text)',
    'public.get_next_invoice_no(text)',
    'public.delete_inventory_item(bigint,uuid,text)',
    'public.is_admin()', 'public.touch_updated_at()', 'public.handle_new_user()',
    'public.sync_product_category_name()', 'public.sync_category_name_to_products()',
    'public.ensure_one_default_variant()'
  ]) AS x
  WHERE to_regprocedure(x) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'YG function(s) not restored: %', v_missing;
  END IF;

  -- Exactly one version of each restored RPC (no jewellery overload left).
  SELECT string_agg(proname, ', ') INTO v_left FROM (
    SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'complete_pos_sale_with_inventory', 'create_order_with_stock', 'create_advance_order',
      'complete_advance_order_v2', 'generate_barcode_value', 'create_barcode_and_receive_stock',
      'adjust_inventory_stock', 'get_expense_summary_metrics', 'get_public_invoice_by_number',
      'update_advance_order_status', 'add_advance_order_event')
    GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'Extra versions still installed: %', v_left;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'complete_advance_order_v2'
                 AND prosrc ILIKE '%Not enough stock to complete this order%') THEN
    RAISE EXCEPTION 'complete_advance_order_v2 is not the stock-deducting version';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('complete_pos_sale_with_inventory', 'create_order_with_stock')
             AND prosrc ~ 'WHERE UPPER\(BTRIM\(code\)\) = UPPER\(BTRIM\(p_coupon_code\)\)(?! AND branch = v_branch)') THEN
    RAISE EXCEPTION 'Checkout still counts coupon use on both POS';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'orders_stock_trigger') THEN
    RAISE EXCEPTION 'orders_stock_trigger is still installed';
  END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgname IN (
        'enforce_variant_branch_trigger', 'enforce_barcode_registry_branch_trigger',
        'enforce_inventory_movement_branch_trigger', 'on_auth_user_created',
        'sync_product_category_name_trigger', 'sync_category_name_to_products_trigger',
        'ensure_one_default_variant_trigger')) <> 7 THEN
    RAISE EXCEPTION 'A YG trigger is missing';
  END IF;

  IF to_regclass('public.coupons_code_upper_unique') IS NOT NULL
     OR to_regclass('public.categories_name_en_key') IS NOT NULL
     OR to_regclass('public.barcode_registry_barcode_value_key') IS NOT NULL THEN
    RAISE EXCEPTION 'A cross-POS uniqueness rule is still installed';
  END IF;
  IF to_regclass('public.coupons_branch_code_upper_unique') IS NULL
     OR to_regclass('public.barcode_registry_branch_value_unique') IS NULL
     OR to_regclass('public.categories_branch_name_unique') IS NULL THEN
    RAISE EXCEPTION 'A per-POS uniqueness rule is missing';
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- SECTION 41 / 41 -- 20261012_0042_restart_invoice_numbers.sql
-- ============================================================

-- ===================================================================
-- Migration 0042: Restart each POS's invoice numbers from the start
-- ===================================================================
--
-- Test and deleted bills had already used up invoice numbers, so the next
-- real bill would not have been the first number. This puts each POS's
-- counter back to its first number:
--
--   POS 1 -> 10000001      POS 2 -> 50000001
--
-- It can never create a duplicate: if a POS still has bills, its counter
-- continues right after the highest number already used in its range
-- instead of restarting. Advance-order completion bills use the same
-- counters, so they are covered too.
--
-- SAFE / IDEMPOTENT: re-running gives the same result.
-- ===================================================================

BEGIN;

-- Hold off new bills while the counters are being set.
LOCK TABLE public.orders IN SHARE ROW EXCLUSIVE MODE;

SELECT setval(
  'public.invoice_number_seq_pos1',
  COALESCE((
    SELECT MAX(invoice_no::BIGINT) + 1 FROM public.orders
    WHERE invoice_no ~ '^[0-9]+$' AND invoice_no::BIGINT BETWEEN 10000001 AND 49999999
  ), 10000001),
  FALSE
);

SELECT setval(
  'public.invoice_number_seq_pos2',
  COALESCE((
    SELECT MAX(invoice_no::BIGINT) + 1 FROM public.orders
    WHERE invoice_no ~ '^[0-9]+$' AND invoice_no::BIGINT >= 50000001
  ), 50000001),
  FALSE
);

COMMIT;

-- Shows the next number each POS will use (reads only; uses up nothing).
SELECT
  (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM public.invoice_number_seq_pos1) AS pos1_next_bill,
  (SELECT CASE WHEN is_called THEN last_value + 1 ELSE last_value END FROM public.invoice_number_seq_pos2) AS pos2_next_bill;

-- ============================================================
-- SECTION 42 / 42 -- 20261013_0043_store_gstin.sql
-- ============================================================

-- ===================================================================
-- Migration 0043: GST number (GSTIN) per POS
-- ===================================================================
--
-- Invoices and thermal receipts print the shop's GSTIN under the shop
-- details. It is stored per POS on store_settings and edited in
-- Admin -> Store Settings -> "GST Number (GSTIN)". An empty value hides it.
--
-- Fills in 33AJEPG5088P1ZS for both POS, but only where no GSTIN has been
-- saved yet, so re-running never overwrites a number changed in Settings.
--
-- Deploy order: run this BEFORE deploying the app build that reads and
-- saves the GSTIN (saving Store Settings needs the column to exist).
--
-- SAFE / IDEMPOTENT.
-- ===================================================================

BEGIN;

ALTER TABLE public.store_settings ADD COLUMN IF NOT EXISTS gstin TEXT NOT NULL DEFAULT '';

UPDATE public.store_settings
SET gstin = '33AJEPG5088P1ZS', updated_at = NOW()
WHERE branch IN ('pos1', 'pos2')
  AND BTRIM(gstin) = '';

COMMIT;

NOTIFY pgrst, 'reload schema';

SELECT branch, gstin FROM public.store_settings ORDER BY branch;
