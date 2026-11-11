-- Migration: Add HSN column to invoice_items table
-- Date: 2026-05-04
-- Purpose: Add HSN code support for invoice items

-- Add hsn column to invoice_items table
ALTER TABLE public.invoice_items ADD COLUMN IF NOT EXISTS hsn text NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.invoice_items.hsn IS 'HSN/SAC code for the product item';
