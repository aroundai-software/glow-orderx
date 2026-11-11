-- Migration: Add hide_stock_quantity_salesman toggle to company_settings
-- When true, salesmen cannot see remaining stock quantities across product catalog, details dialog, and cart.

ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS hide_stock_quantity_salesman boolean NOT NULL DEFAULT false;
