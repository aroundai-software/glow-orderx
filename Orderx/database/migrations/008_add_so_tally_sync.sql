-- Migration: Sales Order → Tally sync
-- Run this in the Supabase SQL Editor before using the "Sync SO to Tally" toggle.
--
-- What this does:
--   1. company_settings.sync_so_to_tally
--        Admin System-tab switch. OFF = exe skips SO push. ON = exe pushes SOs.
--   2. sales_orders.alter_id
--        New UUID generated every time an order is edited in the app.
--        The exe uses a non-null alter_id to find edited orders and overwrite them in Tally.
--   3. sales_orders.is_edited
--        Set true on edit (the app already reads this on invoices).
--   4. sales_orders.so_synced_to_tally / so_tally_sync_date / tally_so_guid
--        Track which SOs have been pushed to Tally.
--        This is NOT the same as synced_to_tally (that flag means billed in Tally and locks editing).
--
-- Sync rules (handled by the exe, not SQL):
--   First sync  → all orders (so_synced_to_tally defaults to false)
--   Later syncs → new orders (so_synced_to_tally = false) + edited orders (alter_id is not null)

-- ── company_settings ────────────────────────────────────────────────────────
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS sync_so_to_tally boolean NOT NULL DEFAULT false;

-- ── sales_orders ────────────────────────────────────────────────────────────
ALTER TABLE sales_orders
  ADD COLUMN IF NOT EXISTS alter_id text;

ALTER TABLE sales_orders
  ADD COLUMN IF NOT EXISTS is_edited boolean NOT NULL DEFAULT false;

ALTER TABLE sales_orders
  ADD COLUMN IF NOT EXISTS so_synced_to_tally boolean NOT NULL DEFAULT false;

ALTER TABLE sales_orders
  ADD COLUMN IF NOT EXISTS so_tally_sync_date timestamptz;

ALTER TABLE sales_orders
  ADD COLUMN IF NOT EXISTS tally_so_guid text;

CREATE INDEX IF NOT EXISTS idx_sales_orders_so_tally_pending
  ON sales_orders (company_id)
  WHERE so_synced_to_tally = false OR alter_id IS NOT NULL;
