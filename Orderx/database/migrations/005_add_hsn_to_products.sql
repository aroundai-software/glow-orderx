-- Migration: Add HSN column to products table
-- Date: 2026-06-24
-- Purpose: Add HSN code support for products

-- Add hsn column to products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS hsn text NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.products.hsn IS 'HSN/SAC code for the product';
