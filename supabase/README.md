# YG Enterprises Supabase setup

Apply the migrations in filename order to the dedicated YG Enterprises Supabase project (or paste `RUN_ALL_MIGRATIONS.sql` in one go via the SQL Editor).

1. Run `20260716_0001_purple_boutique_schema.sql` (base schema — filename kept for history, content is YG Enterprises' schema).
2. Run `20260716_0002_purple_boutique_catalog.sql` (filename kept for history).
3. Continue through the remaining files in `supabase/migrations/` in filename order.
4. Create the owner account in Supabase Authentication and set its `role` metadata to `admin` if customer login is enabled.

The schema migration is idempotent. Invoice numbers use the format `PB-YYYY-000001` (POS 1) / a disjoint numeric range (POS 2) and are allocated under a locked database sequence per branch to prevent duplicates during concurrent billing.

Migration `20260930_0029_isolate_coupons_and_expense_categories.sql` gives coupons and expense categories separate POS 1 / POS 2 records. Legacy shared coupons and categories remain assigned to POS 1; POS 2 gets its own default expense categories. Apply this migration to the connected Supabase project before deploying the updated app.

Migration `20261001_0030_hard_delete_inventory_item.sql` permanently deletes a product or variant together with its barcode registry entries and inventory movement rows. Historical invoice line items keep their saved names, quantities, and totals. Apply this migration before deploying the product deletion change.

Migration `20261006_0036_seed_ledger.sql` adds `public.seed_ledger`, a run-once marker table, and backfills it for the three catalog seeds (`0002`, `0022`, `0024`).

Why this is required: those seeds previously guarded their inserts with a NAME-based `WHERE NOT EXISTS (SELECT 1 FROM products WHERE <same name>)` check. That guard is name-based rather than run-based, so once an operator deleted a seeded product the row was gone, the check passed again, and re-running the migrations silently RE-CREATED the deleted product at its placeholder price and 999 opening stock. Deleted catalog items were therefore not durable.

With the ledger in place, each seed records itself on first run and every subsequent run is a no-op, so a product an operator has deleted stays deleted. The same guard also protects `0024`'s unconditional `DELETE ... WHERE branch = 'pos2'` block, which previously wiped the entire POS 2 catalog on every re-run, and its `store_settings.business_type` overwrites, which previously clobbered operator edits.

Apply this migration once. It is safe to re-run (`CREATE TABLE IF NOT EXISTS` plus `ON CONFLICT DO NOTHING`).

Migration `20261110_0047_pos3_christmas_branch.sql` adds the Christmas POS (`pos3`) as a third isolated branch: it allows `pos3` in every branch CHECK except `advance_orders` and `coupons` (POS 3 has neither, enforced in the database), gives it its own invoice (60000001+) and barcode (P3P / P3V) sequences, teaches the sale / stock / expense RPCs and branch triggers to resolve `pos3` instead of falling back to `pos1`, adds a `pos3_staff` login key, a `pos3` store profile and default expense categories, and adds an optional `wholesale_price` to products / variants. Run it before deploying the POS 3 build. It is idempotent and does not touch POS 1 / POS 2 data.
