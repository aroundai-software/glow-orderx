-- Migration: Add discount columns to order_items and products
-- Date: 2026-06-24
-- Purpose: Add missing discount columns that are used in the code but missing from the schema

-- Add missing discount columns to order_items table
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS cash_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS offer_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS item_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS order_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mrp numeric(10, 2) DEFAULT 0;

-- Add missing discount columns to invoice_items table (for consistency)
ALTER TABLE public.invoice_items
  ADD COLUMN IF NOT EXISTS cash_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS offer_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS item_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS order_discount_amount numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mrp numeric(10, 2) DEFAULT 0;

-- Add missing promotional discount columns to products table
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS "ComboStartDate" timestamp with time zone,
  ADD COLUMN IF NOT EXISTS "ComboEndDate" timestamp with time zone,
  ADD COLUMN IF NOT EXISTS "ComboQtyOffTake" numeric(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "SpecialStartDate" timestamp with time zone,
  ADD COLUMN IF NOT EXISTS "SpecialEndDate" timestamp with time zone,
  ADD COLUMN IF NOT EXISTS "SpecialDiscount" numeric(5, 2) DEFAULT 0;
