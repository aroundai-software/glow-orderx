-- Migration: Add order edit settings to company_settings
-- Run this in Supabase SQL Editor

ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS order_edit_window_minutes INTEGER NOT NULL DEFAULT 30;

ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS allow_order_editing BOOLEAN NOT NULL DEFAULT true;
